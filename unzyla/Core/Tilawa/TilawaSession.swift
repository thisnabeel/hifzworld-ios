import Foundation
import OnnxRuntimeBindings

// Ported from `@tilawa/core` `recitation/zipformerRunner.ts` + `recitation/session.ts` (MIT).
// The session keeps the recognize path (locate, track, emit ayahs, whole-ayah fallback) and drops
// correction mode, which verse search does not need.

/// I/O manifest shipped next to the model (`zipformer_interp_gentle_a05.io.json`).
nonisolated struct TilawaZipformerIO: Decodable, Sendable {
    struct Input: Decodable, Sendable {
        let name: String
        let dims: [Int]
        let dtype: String
    }

    let T: Int
    let hop: Int
    let featureDim: Int
    let vocabSize: Int
    let inputs: [Input]
}

/// Streaming Zipformer2-CTC: 61-frame windows, 48-frame hop, cache tensors carried between runs.
nonisolated final class TilawaZipformerRunner {
    enum RunError: LocalizedError {
        case missingOutput(String)
        var errorDescription: String? {
            switch self {
            case .missingOutput(let name): return "Recitation model output \(name) is missing."
            }
        }
    }

    let io: TilawaZipformerIO
    private let env: ORTEnv
    private let session: ORTSession
    private let stateInputs: [TilawaZipformerIO.Input]
    private let outputNames: Set<String>
    private var buffer: [[Float]] = []
    private var states: [String: ORTValue] = [:]

    init(modelPath: String, io: TilawaZipformerIO) throws {
        self.io = io
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        stateInputs = io.inputs.filter { $0.name != "x" }
        outputNames = Set(["log_probs"] + stateInputs.map { "new_\($0.name)" })
        try initStates()
    }

    func reset() throws {
        buffer.removeAll()
        try initStates()
    }

    func accept(_ frames: [[Float]]) throws -> (logProbs: [Float], frames: Int) {
        buffer.append(contentsOf: frames)
        let t = io.T
        let dim = io.featureDim
        let vocab = io.vocabSize
        var logProbs: [Float] = []
        while buffer.count >= t {
            var x = [Float]()
            x.reserveCapacity(t * dim)
            for i in 0..<t { x.append(contentsOf: buffer[i]) }
            let xData = x.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
            var feeds: [String: ORTValue] = [
                "x": try ORTValue(tensorData: xData, elementType: .float, shape: [1, NSNumber(value: t), NSNumber(value: dim)]),
            ]
            for input in stateInputs { feeds[input.name] = states[input.name] }
            let out = try session.run(withInputs: feeds, outputNames: outputNames, runOptions: nil)
            guard let lp = out["log_probs"] else { throw RunError.missingOutput("log_probs") }
            let data = try lp.tensorData() as Data
            let shape = try lp.tensorTypeAndShapeInfo().shape.map(\.intValue)
            let count = data.count / MemoryLayout<Float>.size
            let f = shape.count >= 2 ? shape[1] : count / vocab
            data.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                logProbs.append(contentsOf: floats.prefix(f * vocab))
            }
            for input in stateInputs {
                guard let next = out["new_\(input.name)"] else { throw RunError.missingOutput("new_\(input.name)") }
                states[input.name] = next
            }
            buffer.removeFirst(io.hop)
        }
        return (logProbs, logProbs.count / vocab)
    }

    private func initStates() throws {
        states.removeAll()
        for input in stateInputs {
            let n = input.dims.reduce(1, *)
            let isInt64 = input.dtype == "int64"
            let bytes = n * (isInt64 ? MemoryLayout<Int64>.size : MemoryLayout<Float>.size)
            guard let data = NSMutableData(length: bytes) else { continue }
            states[input.name] = try ORTValue(
                tensorData: data,
                elementType: isInt64 ? .int64 : .float,
                shape: input.dims.map { NSNumber(value: $0) }
            )
        }
    }
}

/// Everything expensive to build once per app run: corpus, n-gram index, fallback table, model.
nonisolated final class TilawaResources: @unchecked Sendable {
    let corpus: TilawaCorpus
    let index: TilawaQuranIndex
    let fallback: TilawaAyahFallback
    let modelPath: String
    let io: TilawaZipformerIO
    let config: TilawaEngineConfig

    init(modelURL: URL, ioURL: URL, corpusURL: URL, config: TilawaEngineConfig = .default) throws {
        let corpus = try TilawaCorpus(data: Data(contentsOf: corpusURL))
        self.corpus = corpus
        self.index = TilawaQuranIndex(corpus: corpus, config: config)
        self.fallback = TilawaAyahFallback(corpus: corpus, config: config)
        self.io = try JSONDecoder().decode(TilawaZipformerIO.self, from: Data(contentsOf: ioURL))
        self.modelPath = modelURL.path
        self.config = config
    }
}

nonisolated struct TilawaVerseMatch: Equatable, Sendable {
    let surah: Int
    let ayah: Int
    let confidence: Double

    var verseKey: String { "\(surah):\(ayah)" }
}

nonisolated enum TilawaSessionEvent: Equatable, Sendable {
    /// The engine locked onto a position (not yet a confirmed ayah).
    case candidate(surah: Int, ayah: Int)
    /// Enough of an ayah's words were heard to report it.
    case verseMatch(TilawaVerseMatch)
    /// End of audio: every reported ayah in order, plus alternatives from the whole-ayah search.
    case final(verses: [TilawaVerseMatch], alternatives: [TilawaVerseMatch])
}

/// PCM in, verse events out. Not thread-safe; drive it from one serial queue.
nonisolated final class TilawaSession {
    private static let tailSeconds = 2.0
    private static let alternativesMaxChars = 250

    private let resources: TilawaResources
    private let runner: TilawaZipformerRunner
    private let cfg: TilawaEngineConfig
    private let minWordFraction = TilawaEmission.minWordFraction
    private let fbank = TilawaFbank()
    private let decoder = TilawaCtcDecoder()
    private var engine: TilawaRecitationEngine
    private var accumulated: [String: TilawaAyahTally] = [:]
    private var emitted = Set<String>()
    private var transcript: PhonemeUnits = []

    init(resources: TilawaResources) throws {
        self.resources = resources
        self.cfg = resources.config
        self.runner = try TilawaZipformerRunner(modelPath: resources.modelPath, io: resources.io)
        self.engine = TilawaRecitationEngine(corpus: resources.corpus, index: resources.index, config: resources.config)
        self.engine = makeEngine()
    }

    /// Drop all state — new recitation, same model and corpus.
    func reset() throws {
        accumulated = [:]
        emitted = []
        transcript = []
        try resetDecoder()
        engine = makeEngine()
    }

    /// Push mono 16 kHz float PCM. Any chunk size; ~300–500 ms works well.
    func feed(_ samples: [Float]) throws -> [TilawaSessionEvent] {
        try runFrames(fbank.acceptWaveform(samples))
    }

    /// End of audio: flush the model tail and report the final sequence.
    func stop() throws -> [TilawaSessionEvent] {
        var out = try feed([Float](repeating: 0, count: Int(Self.tailSeconds * Double(TilawaAudio.sampleRate))))
        let frames = fbank.inputFinished()
        if !frames.isEmpty { out += try runFrames(frames) }
        let flushed = decoder.flush()
        if !flushed.isEmpty { out += try consumeTokens(flushed) }

        dumpTallies()
        for t in TilawaEmission.newlyEligible(accumulated, alreadyEmitted: emitted, minWordFraction: minWordFraction) {
            emitted.insert(t.key)
            out.append(.verseMatch(match(t)))
        }

        // Whole-ayah ranking scans all 6,236 ayahs; beyond the original's nothing-emitted fallback,
        // only run it for short recitations, where the alternatives are most useful.
        let ranked = emitted.isEmpty || transcript.count <= Self.alternativesMaxChars
            ? resources.fallback.rank(transcript, maxDistance: TilawaEmission.fallbackMaxDistance, limit: 4)
            : []
        let alternatives = ranked.map {
            TilawaVerseMatch(surah: $0.surah, ayah: $0.ayah, confidence: TilawaEmission.fallbackConfidence($0.distance))
        }
        if emitted.isEmpty, let fallback = ranked.first {
            let words = resources.corpus.ayahWordCount(fallback.surah, fallback.ayah)
            let tally = TilawaAyahTally(
                surah: fallback.surah,
                ayah: fallback.ayah,
                ok: words,
                words: words,
                firstSeen: accumulated.count
            )
            accumulated[tally.key] = tally
            emitted.insert(tally.key)
            out.append(.verseMatch(TilawaVerseMatch(
                surah: fallback.surah,
                ayah: fallback.ayah,
                confidence: TilawaEmission.fallbackConfidence(fallback.distance)
            )))
        }

        let gated = accumulated.values
            .filter { $0.meetsGate(minWordFraction: minWordFraction) }
            .sorted { $0.firstSeen < $1.firstSeen }
            .map(match)
        out.append(.final(verses: gated, alternatives: alternatives))
        return out
    }

    private func match(_ t: TilawaAyahTally) -> TilawaVerseMatch {
        TilawaVerseMatch(surah: t.surah, ayah: t.ayah, confidence: (t.confidence * 100).rounded() / 100)
    }

    private func makeEngine() -> TilawaRecitationEngine {
        let engine = TilawaRecitationEngine(corpus: resources.corpus, index: resources.index, config: cfg)
        engine.setStayOnSurah(false)
        engine.startSearch()
        engine.onBeforeRelocate = { [weak self] in self?.dumpTallies() }
        return engine
    }

    private func resetDecoder() throws {
        fbank.reset()
        decoder.reset()
        try runner.reset()
    }

    private func wordCount(_ surah: Int, _ ayah: Int) -> Int {
        resources.corpus.ayahWordCount(surah, ayah)
    }

    private func currentSnapshot() -> [String: TilawaAyahTally] {
        guard let tracer = engine.tracer else { return [:] }
        return TilawaEmission.snapshotTallies(tracer.verdicts(settled: true), wordCount: wordCount)
    }

    private func dumpTallies() {
        TilawaEmission.accumulate(&accumulated, currentSnapshot())
    }

    private func runFrames(_ frames: [[Float]]) throws -> [TilawaSessionEvent] {
        if frames.isEmpty { return [] }
        let result = try runner.accept(frames)
        if result.frames == 0 { return [] }
        let tokens = decoder.consume(result.logProbs, frames: result.frames, classes: runner.io.vocabSize)
        return try consumeTokens(tokens)
    }

    private func consumeTokens(_ tokens: [TilawaCtcToken]) throws -> [TilawaSessionEvent] {
        var out: [TilawaSessionEvent] = []
        for t in tokens { transcript.append(contentsOf: t.sym) }
        for ev in engine.feed(tokens, framesDecoded: decoder.framesDecoded) {
            out += try handle(ev)
        }
        out += emitNewMatches(nil)
        return out
    }

    private func handle(_ ev: TilawaEngineEvent) throws -> [TilawaSessionEvent] {
        switch ev {
        case let .located(surah, ayah, _, _):
            return [.candidate(surah: surah, ayah: ayah)]
        case .idle, .completed:
            dumpTallies()
            let out = emitNewMatches(accumulated)
            engine.startSearch()
            try resetDecoder()
            return out
        default:
            return []
        }
    }

    private func emitNewMatches(_ source: [String: TilawaAyahTally]?) -> [TilawaSessionEvent] {
        let tallies = source ?? TilawaEmission.merge(accumulated, currentSnapshot())
        var out: [TilawaSessionEvent] = []
        for t in TilawaEmission.newlyEligible(tallies, alreadyEmitted: emitted, minWordFraction: minWordFraction) {
            emitted.insert(t.key)
            out.append(.verseMatch(match(t)))
        }
        return out
    }
}
