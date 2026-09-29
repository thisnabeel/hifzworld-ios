@preconcurrency import AVFoundation
import Foundation

/// Owns the microphone and the recognition session. All engine work runs on one serial queue;
/// events come back through `onEvents` on that queue.
nonisolated final class TilawaRecognizer: @unchecked Sendable {
    enum StartError: LocalizedError {
        case microphoneUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: return "The microphone isn't available right now."
            }
        }
    }

    static let shared = TilawaRecognizer()

    /// Receives engine events and a rough input level (0…1) for the UI.
    var onEvents: (@Sendable ([TilawaSessionEvent]) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let queue = DispatchQueue(label: "tilawa.recognizer", qos: .userInitiated)
    private var resources: TilawaResources?
    private var session: TilawaSession?
    private let audioEngine = AVAudioEngine()
    private var pending: [Float] = []
    private var running = false
    private var generation = 0

    private static let chunkSamples = 4800
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(TilawaAudio.sampleRate),
        channels: 1,
        interleaved: false
    )!

    private init() {}

    /// Load the corpus, build the index and the ONNX session. Safe to call repeatedly.
    func prepare() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if self.resources == nil {
                        self.resources = try TilawaResources(
                            modelURL: TilawaAssets.url(for: TilawaAssets.model),
                            ioURL: TilawaAssets.url(for: TilawaAssets.io),
                            corpusURL: TilawaAssets.url(for: TilawaAssets.corpus)
                        )
                    }
                    if self.session == nil, let resources = self.resources {
                        self.session = try TilawaSession(resources: resources)
                    }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Start listening. Call `prepare()` first and hold microphone permission.
    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: Self.targetFormat) else {
            throw StartError.microphoneUnavailable
        }

        queue.sync {
            generation += 1
            pending.removeAll()
            running = true
            try? session?.reset()
        }
        let gen = queue.sync { generation }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleTap(buffer, converter: converter, generation: gen)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            queue.sync { running = false }
            throw error
        }
    }

    /// Stop the microphone and flush the model; the final events arrive through `onEvents`.
    func stop() {
        stopAudio()
        queue.async {
            guard self.running else { return }
            self.running = false
            self.flushPending()
            self.deliver { try self.session?.stop() ?? [] }
        }
    }

    /// Stop without producing final results.
    func cancel() {
        stopAudio()
        queue.async {
            self.running = false
            self.generation += 1
            self.pending.removeAll()
            try? self.session?.reset()
        }
    }

    private func stopAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Runs on the audio render thread.
    private func handleTap(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, generation gen: Int) {
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))

        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        onLevel?(min(1, rms * 12))

        queue.async {
            guard self.running, self.generation == gen else { return }
            self.pending.append(contentsOf: samples)
            if self.pending.count >= Self.chunkSamples { self.flushPending() }
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let chunk = pending
        pending.removeAll(keepingCapacity: true)
        deliver { try self.session?.feed(chunk) ?? [] }
    }

    private func deliver(_ work: () throws -> [TilawaSessionEvent]) {
        do {
            let events = try work()
            if !events.isEmpty { onEvents?(events) }
        } catch {
            running = false
            onError?(error)
        }
    }
}
