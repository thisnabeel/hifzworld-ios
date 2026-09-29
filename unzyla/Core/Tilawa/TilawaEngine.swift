import Foundation

// Ported from `@tilawa/core` `recitation/engine.ts` + `recitation/emission.ts` (MIT).

nonisolated enum TilawaEngineEvent: Equatable {
    case located(surah: Int, ayah: Int, word: Int, replayed: Int)
    case relocated(fromSurah: Int, fromAyah: Int, surah: Int, ayah: Int, word: Int)
    case cursor(surah: Int, ayah: Int, word: Int, wordIndex: Int)
    case verdicts([TilawaWordVerdict])
    case lost
    case idle(silent: Bool)
    case completed(surah: Int)
    case locateFailed
}

/// Locates a recitation anywhere in the Quran, then follows it word by word.
nonisolated final class TilawaRecitationEngine {
    enum State {
        case searching
        case tracking
    }

    private struct VerdictKey: Equatable {
        let state: TilawaVerdictState
        let distance: Double
        let heardRatio: Double
        let margin: Double
    }

    let corpus: TilawaCorpus
    let index: TilawaQuranIndex
    let cfg: TilawaEngineConfig
    private(set) var state: State = .searching
    private(set) var tracker: TilawaTracker?
    private(set) var tracer: TilawaVerdictTracer?
    private(set) var framesDecoded = 0
    private(set) var heardTotal = 0

    private var buffer: [TilawaHeardChar] = []
    private var hint: TilawaSearchHint?
    private var stay = false
    private var searchStartFrame = 0
    private var lastSearchFrame = 0
    private var lastSearchHeard = 0
    private var lastRelocateFrame = 0
    private var lastProgressFrame = 0
    private var lastCharFrame = 0
    private var locateFailedEmitted = false
    private var lostEmitted = false
    private var completedEmitted = false
    private var struggles = 0
    private var relocateCandidate: TilawaSearchHint?
    private var lastCursorWord = -1
    private var lastStates: [Int: VerdictKey] = [:]
    private var prevSettled = false
    private var lastStruggleChars = 0
    var onBeforeRelocate: (() -> Void)?

    init(corpus: TilawaCorpus, index: TilawaQuranIndex, config: TilawaEngineConfig) {
        self.corpus = corpus
        self.index = index
        self.cfg = config
    }

    func setHint(_ hint: TilawaSearchHint?) {
        self.hint = hint
    }

    func setStayOnSurah(_ stay: Bool) {
        self.stay = stay
    }

    func startSearch() {
        state = .searching
        tracker = nil
        tracer = nil
        buffer = []
        heardTotal = 0
        searchStartFrame = framesDecoded
        lastSearchFrame = framesDecoded
        lastSearchHeard = 0
        lastRelocateFrame = framesDecoded
        lastProgressFrame = framesDecoded
        lastCharFrame = framesDecoded
        locateFailedEmitted = false
        lostEmitted = false
        completedEmitted = false
        struggles = 0
        relocateCandidate = nil
        lastCursorWord = -1
        lastStates.removeAll()
        prevSettled = false
        lastStruggleChars = 0
    }

    func feed(_ tokens: [TilawaCtcToken], framesDecoded frames: Int) -> [TilawaEngineEvent] {
        if frames < framesDecoded {
            searchStartFrame = frames
            lastSearchFrame = frames
            lastRelocateFrame = frames
            lastProgressFrame = frames
            lastCharFrame = frames
        }
        framesDecoded = frames
        let chars = TilawaCtcDecoder.expand(tokens)
        if !chars.isEmpty {
            lastCharFrame = frames
            heardTotal += chars.count
            buffer.append(contentsOf: chars)
            if buffer.count > TilawaAudio.bufferCap {
                buffer.removeFirst(buffer.count - TilawaAudio.bufferCap)
            }
        }
        if state == .searching { return feedSearching() }
        return feedTracking(chars)
    }

    private enum LockHow {
        case located
        case relocated(fromSurah: Int, fromAyah: Int)
    }

    private func lock(wordIndex: Int, replay: [TilawaHeardChar], how: LockHow) -> [TilawaEngineEvent] {
        if case .relocated = how { onBeforeRelocate?() }
        let surah = corpus.wordSurah[wordIndex]
        let ayah = corpus.wordAyah[wordIndex]
        let word = corpus.wordInAyah[wordIndex]
        let prev: (surah: Int, ayah: Int)?
        if let tracker {
            prev = (tracker.surah, corpus.wordAyah[tracker.cursorWordIndex])
        } else if case let .relocated(fromSurah, fromAyah) = how {
            prev = (fromSurah, fromAyah)
        } else {
            prev = nil
        }
        let newTracker = TilawaTracker(corpus: corpus, table: index.table, surah: surah, startWordIndex: wordIndex, config: cfg)
        tracker = newTracker
        tracer = TilawaVerdictTracer(tracker: newTracker, table: index.table, config: cfg)
        state = .tracking
        lostEmitted = false
        completedEmitted = false
        struggles = 0
        relocateCandidate = nil
        lastCursorWord = -1
        lastStates.removeAll()
        prevSettled = false
        lastRelocateFrame = framesDecoded
        lastStruggleChars = heardTotal
        var events: [TilawaEngineEvent] = []
        if case .relocated = how, let prev {
            events.append(.relocated(fromSurah: prev.surah, fromAyah: prev.ayah, surah: surah, ayah: ayah, word: word))
        } else {
            events.append(.located(surah: surah, ayah: ayah, word: word, replayed: replay.count))
        }
        if !replay.isEmpty { newTracker.feed(replay) }
        events.append(contentsOf: trackingEvents(gotChars: false))
        return events
    }

    private func feedSearching() -> [TilawaEngineEvent] {
        var events: [TilawaEngineEvent] = []
        let due = buffer.count >= cfg.searchMinChars
            && (heardTotal - lastSearchHeard >= cfg.searchEveryChars
                || (heardTotal - lastSearchHeard > 0 && framesDecoded - lastSearchFrame >= cfg.searchEveryFrames))
        if due {
            lastSearchFrame = framesDecoded
            lastSearchHeard = heardTotal
            let qLen = min(cfg.searchQueryChars, buffer.count)
            let qStart = buffer.count - qLen
            let query = buffer[qStart...].map(\.ch)
            let result = index.search(query, hint: hint)
            if result.decisive, let hit = result.hits.first {
                let replay = Array(buffer[(qStart + hit.queryStart)...])
                return lock(wordIndex: hit.wordIndex, replay: replay, how: .located)
            }
        }
        if !locateFailedEmitted && framesDecoded - searchStartFrame >= cfg.locateFailedFrames {
            locateFailedEmitted = true
            events.append(.locateFailed)
        }
        return events
    }

    private func feedTracking(_ chars: [TilawaHeardChar]) -> [TilawaEngineEvent] {
        guard let tracker, tracer != nil else { return [] }
        if !chars.isEmpty { tracker.feed(chars) }
        var events = trackingEvents(gotChars: !chars.isEmpty)
        if tracker.lost {
            if !lostEmitted {
                lostEmitted = true
                events.append(.lost)
            }
        } else {
            lostEmitted = false
        }

        if framesDecoded - lastRelocateFrame >= cfg.relocateEveryFrames {
            lastRelocateFrame = framesDecoded
            let heardSinceTick = heardTotal - lastStruggleChars
            lastStruggleChars = heardTotal
            if stay {
                struggles = 0
            } else {
                if let moved = maybeRelocate() { return events + moved }
                if heardSinceTick > 0 {
                    struggles = tracker.lost || isHeld() ? struggles + 1 : 0
                    if cfg.maxStruggles > 0 && struggles >= cfg.maxStruggles {
                        events.append(.idle(silent: false))
                        struggles = 0
                        lastProgressFrame = framesDecoded
                    }
                }
            }
        }

        if framesDecoded - lastProgressFrame >= cfg.idleFrames {
            events.append(.idle(silent: true))
            lastProgressFrame = framesDecoded
        }
        return events
    }

    private func maybeRelocate() -> [TilawaEngineEvent]? {
        guard let tracker, buffer.count >= cfg.searchMinChars else { return nil }
        let qLen = min(cfg.relocateQueryChars, buffer.count)
        let qStart = buffer.count - qLen
        let query = buffer[qStart...].map(\.ch)
        let result = index.search(query, hint: nil, limit: 1)
        let hit = result.hits.first
        let rate = tracker.costRate()
        let candidate = hit.map { TilawaSearchHint(surah: $0.surah, ayah: $0.ayah) }
        let agrees = candidate != nil && candidate == relocateCandidate
        relocateCandidate = candidate
        if let hit, let rate,
           rate >= cfg.lostRate,
           hit.surah != tracker.surah,
           hit.distance <= cfg.relocateMaxDistance,
           hit.distance + cfg.relocateRateMargin <= rate,
           agrees {
            let fromAyah = corpus.wordAyah[tracker.cursorWordIndex]
            let replay = Array(buffer[(qStart + hit.queryStart)...])
            return lock(wordIndex: hit.wordIndex, replay: replay, how: .relocated(fromSurah: tracker.surah, fromAyah: fromAyah))
        }
        return nil
    }

    private func isHeld() -> Bool {
        guard let rate = tracker?.costRate(window: cfg.holdWindow) else { return false }
        return rate >= cfg.holdRate
    }

    private func isSettled() -> Bool {
        framesDecoded - lastCharFrame >= cfg.settleFrames
    }

    private func trackingEvents(gotChars: Bool) -> [TilawaEngineEvent] {
        guard let tracker, let tracer else { return [] }
        if isHeld() { return [] }
        var events: [TilawaEngineEvent] = []
        let cursorIdx = tracker.cursorWordIndex
        if cursorIdx != lastCursorWord {
            lastCursorWord = cursorIdx
            lastProgressFrame = framesDecoded
            events.append(.cursor(
                surah: corpus.wordSurah[cursorIdx],
                ayah: corpus.wordAyah[cursorIdx],
                word: corpus.wordInAyah[cursorIdx],
                wordIndex: cursorIdx
            ))
        }
        let settled = isSettled()
        let silenceSettle = !gotChars && settled && !prevSettled
        let vs = tracer.verdicts(settled: settled)
        var changes: [TilawaWordVerdict] = []
        let refreshPending = gotChars && prevSettled
        for v in vs {
            let key = VerdictKey(state: v.state, distance: v.distance, heardRatio: v.heardRatio, margin: v.margin)
            let prev = lastStates[v.wordIndex]
            if prev == key { continue }
            let wasPending = prev?.state == .pending
            if wasPending && v.state == .pending && !refreshPending { continue }
            changes.append(v)
            lastStates[v.wordIndex] = key
            if v.state != .pending && !silenceSettle {
                lastProgressFrame = framesDecoded
            }
        }
        if !changes.isEmpty { events.append(.verdicts(changes)) }
        let present = Set(vs.map(\.wordIndex))
        lastStates = lastStates.filter { present.contains($0.key) }
        prevSettled = settled
        if !completedEmitted && tracker.reachedEnd {
            let lastW = tracker.endWord - 1
            if let lastV = vs.first(where: { $0.wordIndex == lastW }), lastV.state != .pending {
                completedEmitted = true
                events.append(.completed(surah: tracker.surah))
            }
        }
        return events
    }
}

/// Per-ayah verdict counts; an ayah is reported once enough of its words land.
nonisolated struct TilawaAyahTally: Equatable {
    let surah: Int
    let ayah: Int
    var ok = 0
    var unsure = 0
    var wrong = 0
    var skipped = 0
    var pending = 0
    var words: Int
    var firstSeen: Int

    var key: String { "\(surah):\(ayah)" }

    var confidence: Double {
        words <= 0 ? 0 : Double(ok + unsure) / Double(words)
    }

    func meetsGate(minWordFraction: Double) -> Bool {
        Double(ok + unsure) >= max(1, minWordFraction * Double(words)) && wrong <= ok + unsure
    }

    mutating func add(_ state: TilawaVerdictState) {
        switch state {
        case .ok: ok += 1
        case .unsure: unsure += 1
        case .wrong: wrong += 1
        case .skipped: skipped += 1
        case .pending: pending += 1
        }
    }
}

nonisolated enum TilawaEmission {
    static let minWordFraction = 0.5
    static let fallbackMaxDistance = 0.5

    static func snapshotTallies(
        _ verdicts: [TilawaWordVerdict],
        wordCount: (Int, Int) -> Int
    ) -> [String: TilawaAyahTally] {
        var order: [String: TilawaAyahTally] = [:]
        for v in verdicts {
            let key = "\(v.surah):\(v.ayah)"
            if order[key] == nil {
                order[key] = TilawaAyahTally(
                    surah: v.surah,
                    ayah: v.ayah,
                    words: wordCount(v.surah, v.ayah),
                    firstSeen: order.count
                )
            }
            order[key]?.add(v.state)
        }
        return order
    }

    /// Add `src` counts into `dest`, keeping earlier `firstSeen`. Iterates `src` in its own first-seen order.
    static func accumulate(_ dest: inout [String: TilawaAyahTally], _ src: [String: TilawaAyahTally]) {
        for s in src.values.sorted(by: { $0.firstSeen < $1.firstSeen }) {
            guard var existing = dest[s.key] else {
                var copy = s
                copy.firstSeen = dest.count
                dest[s.key] = copy
                continue
            }
            existing.ok += s.ok
            existing.unsure += s.unsure
            existing.wrong += s.wrong
            existing.skipped += s.skipped
            existing.pending += s.pending
            existing.words = max(existing.words, s.words)
            dest[s.key] = existing
        }
    }

    static func merge(_ accumulated: [String: TilawaAyahTally], _ current: [String: TilawaAyahTally]) -> [String: TilawaAyahTally] {
        var out = accumulated
        accumulate(&out, current)
        return out
    }

    static func newlyEligible(
        _ tallies: [String: TilawaAyahTally],
        alreadyEmitted: Set<String>,
        minWordFraction: Double = minWordFraction
    ) -> [TilawaAyahTally] {
        tallies.values
            .filter { $0.meetsGate(minWordFraction: minWordFraction) && !alreadyEmitted.contains($0.key) }
            .sorted { $0.firstSeen < $1.firstSeen }
    }

    static func fallbackConfidence(_ distance: Double) -> Double {
        guard distance.isFinite else { return 0 }
        return min(1, max(0, 1 - distance))
    }
}
