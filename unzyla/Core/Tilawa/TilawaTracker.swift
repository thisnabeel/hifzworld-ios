import Foundation

// Ported from `@tilawa/core` `recitation/tracker.ts` + `recitation/verdicts.ts` (MIT).
// Vowel-mismatch scoring (only used by the original's correction mode) is left out.

/// Online DP alignment of heard phonemes against one surah, allowing jumps and repeats.
nonisolated final class TilawaTracker {
    private static let rateMinN = 24

    let corpus: TilawaCorpus
    let table: TilawaCostTable
    let cfg: TilawaEngineConfig
    let surah: Int
    let firstWord: Int
    let endWord: Int
    let len: Int
    let surahStart: Int
    let ref: [UInt8]
    let wordStarts: [Int]
    let ayahAtStart: [Int]
    let localWordOfPos: [Int]
    let startLocal: Int

    private(set) var column: [Float]
    private(set) var cursorCell: Int
    private(set) var cursorLocalWord: Int
    private(set) var cursorCost: Float
    private(set) var trail: [Int] = []
    private(set) var costs: [Float] = []
    private(set) var heard: [TilawaHeardChar] = []
    private(set) var lost = false

    init(corpus: TilawaCorpus, table: TilawaCostTable, surah: Int, startWordIndex: Int, config: TilawaEngineConfig) {
        self.corpus = corpus
        self.table = table
        self.cfg = config
        self.surah = surah
        let rec = corpus.surahs[surah - 1]
        firstWord = rec.firstWord
        endWord = rec.endWord
        surahStart = corpus.wordStart[rec.firstWord]
        let surahEnd = corpus.wordStart[rec.endWord]
        len = surahEnd - surahStart
        ref = table.encode(corpus.text[surahStart..<surahEnd])
        let nWords = rec.endWord - rec.firstWord
        var starts = [Int](repeating: 0, count: nWords)
        var ayahs = [Int](repeating: 0, count: nWords)
        for i in 0..<nWords {
            let w = rec.firstWord + i
            starts[i] = corpus.wordStart[w] - surahStart
            ayahs[i] = corpus.wordAyah[w]
        }
        wordStarts = starts
        ayahAtStart = ayahs
        var ofPos = [Int](repeating: 0, count: len)
        for i in 0..<nWords {
            let a = starts[i]
            let b = i + 1 < nWords ? starts[i + 1] : len
            if a < b { for p in a..<b { ofPos[p] = i } }
        }
        localWordOfPos = ofPos
        startLocal = max(0, corpus.wordStart[startWordIndex] - surahStart)

        column = [Float](repeating: .infinity, count: len + 1)
        cursorCell = startLocal
        cursorLocalWord = -1
        cursorCost = 0
        let jump = Float(config.jumpCost)
        for m in starts {
            column[m] = m == startLocal ? 0 : jump
        }
        if len >= 1 {
            for m in 1...len {
                column[m] = min(column[m], column[m - 1] + 1)
            }
        }
    }

    var cursorWordIndex: Int { firstWord + max(0, cursorLocalWord) }

    var reachedEnd: Bool { cursorCell >= len - 1 }

    func feed(_ chars: [TilawaHeardChar]) {
        for h in chars { feedOne(h) }
    }

    func costRate(window: Int? = nil) -> Double? {
        let n = costs.count
        if n < Self.rateMinN { return nil }
        let w = min(window ?? cfg.lostWindow, n)
        let before: Double = n - w > 0 ? Double(costs[n - w - 1]) : 0
        return (Double(costs[n - 1]) - before) / Double(w)
    }

    private func feedOne(_ h: TilawaHeardChar) {
        let prev = column
        var next = [Float](repeating: 0, count: len + 1)
        var colMin = prev[0]
        for m in 1..<(len + 1) where prev[m] < colMin { colMin = prev[m] }
        let jump = Double(colMin) + cfg.jumpCost
        let repeatCost = Double(colMin) + cfg.repeatCost
        let cursorAyah = cursorLocalWord < 0 ? -1 : corpus.wordAyah[firstWord + cursorLocalWord]
        let cursorPos = cursorCell
        let hid = table.id(h.ch)
        let size = table.size
        let hrow = Int(hid) * size

        next[0] = prev[0] + 1
        if wordStarts.first == 0 {
            let r = ayahAtStart[0] == cursorAyah ? repeatCost : jump
            if r < Double(next[0]) { next[0] = Float(r) }
        }
        table.matrix.withUnsafeBufferPointer { mat in
            prev.withUnsafeBufferPointer { p in
                ref.withUnsafeBufferPointer { r in
                    next.withUnsafeMutableBufferPointer { nx in
                        for m in stride(from: 1, through: len, by: 1) {
                            var v = p[m - 1] + mat[hrow + Int(r[m - 1])]
                            let ins = Double(p[m]) + 1
                            let del = Double(nx[m - 1]) + 1
                            if ins < Double(v) { v = Float(ins) }
                            if del < Double(v) { v = Float(del) }
                            nx[m] = v
                        }
                    }
                }
            }
        }
        for i in 0..<wordStarts.count {
            let m = wordStarts[i]
            let restart = m <= cursorPos && ayahAtStart[i] == cursorAyah ? repeatCost : jump
            if restart < Double(next[m]) {
                next[m] = Float(restart)
                var j = m + 1
                while j <= len && Double(next[j - 1]) + 1 < Double(next[j]) {
                    next[j] = next[j - 1] + 1
                    j += 1
                }
            }
        }

        var bestCell = 0
        var bestCost = next[0]
        var bestDist = abs(0 - cursorPos)
        for m in stride(from: 1, through: len, by: 1) {
            let c = next[m]
            let d = abs(m - cursorPos)
            if c < bestCost || (c == bestCost && d < bestDist) {
                bestCost = c
                bestCell = m
                bestDist = d
            }
        }
        column = next
        cursorCell = bestCell
        cursorLocalWord = bestCell == 0 ? 0 : localWordOfPos[min(bestCell, len) - 1]
        cursorCost = bestCost
        trail.append(bestCell)
        costs.append(bestCost)
        heard.append(h)
        if let rate = costRate(window: cfg.lostWindow) {
            lost = rate >= cfg.lostRate
        } else {
            lost = false
        }
    }
}

nonisolated enum TilawaVerdictState: String {
    case ok, unsure, wrong, skipped, pending
}

nonisolated struct TilawaWordVerdict: Equatable {
    let surah: Int
    let ayah: Int
    let word: Int
    let wordIndex: Int
    let state: TilawaVerdictState
    let distance: Double
    let heardRatio: Double
    let margin: Double
}

nonisolated enum TilawaWaqf {
    private static let tanween: [UInt16] = [0x64B, 0x64C, 0x64D]
    private static let cluster: Set<UInt16> = [0x646, 0x6BA, 0x645, 0x6FE, 0x648, 0x6E5, 0x64A, 0x6E6, 0x644, 0x631]
    private static let tanweenVowel: [UInt16: UInt16] = [0x64B: 0x64E, 0x64C: 0x64F, 0x64D: 0x650]
    private static let taaMarbuta: UInt16 = 0x629
    private static let alifAlif: PhonemeUnits = [0x627, 0x627]

    /// The phonemes of a word when the reciter stops on it mid-ayah, or nil if unchanged.
    static func pausalPhonemes(_ phonemes: PhonemeUnits, plain: PhonemeUnits, atAyahEnd: Bool) -> PhonemeUnits? {
        if atAyahEnd { return nil }
        if phonemes.count < 2 { return nil }
        var result: PhonemeUnits?
        if let t = tanween.first(where: { plain.contains($0) }) {
            var stem = phonemes
            if let last = stem.last, cluster.contains(last) {
                var i = stem.count - 1
                while i >= 0 && stem[i] == last { i -= 1 }
                stem = Array(stem[0..<(i + 1)])
            }
            guard let vowel = tanweenVowel[t], stem.last == vowel else { return nil }
            if t == 0x64B && !plain.contains(taaMarbuta) {
                result = stem + alifAlif
            } else {
                result = Array(stem.dropLast())
            }
        } else if let last = phonemes.last, TilawaPhoneme.shortVowels.contains(last) {
            result = Array(phonemes.dropLast())
        }
        guard let result, !result.isEmpty, result != phonemes else { return nil }
        return result
    }
}

/// Turns the tracker's trail into per-word verdicts (ok / unsure / wrong / skipped / pending).
nonisolated final class TilawaVerdictTracer {
    private static let segmentCut = 300
    private static let contextChars = 6

    private struct Segment {
        let heardFrom: Int
        let heardTo: Int
        let refFrom: Int
        let refTo: Int
        let run: Int
        let contextFrom: Int
    }

    private struct Span {
        let from: Int
        let to: Int
        let run: Int
    }

    private struct SegmentKey: Hashable {
        let contextFrom: Int
        let heardTo: Int
        let refFrom: Int
        let refTo: Int
    }

    private let tracker: TilawaTracker
    private let table: TilawaCostTable
    private let cfg: TilawaEngineConfig
    private var cache: [SegmentKey: [Int: Span]] = [:]

    init(tracker: TilawaTracker, table: TilawaCostTable, config: TilawaEngineConfig) {
        self.tracker = tracker
        self.table = table
        self.cfg = config
    }

    func verdicts(settled: Bool = false) -> [TilawaWordVerdict] {
        let segs = segment(tracker.trail)
        var spans: [Int: Span] = [:]
        for (s, seg) in segs.enumerated() {
            let open = s == segs.count - 1
            let got: [Int: Span]
            if open {
                got = alignSegment(seg)
            } else {
                let key = SegmentKey(contextFrom: seg.contextFrom, heardTo: seg.heardTo, refFrom: seg.refFrom, refTo: seg.refTo)
                if let cached = cache[key] {
                    got = cached
                } else {
                    got = alignSegment(seg)
                    cache[key] = got
                }
            }
            for (w, sp) in got { spans[w] = sp }
        }
        return judge(spans, settled: settled)
    }

    private func segment(_ trail: [Int]) -> [Segment] {
        let n = trail.count
        if n == 0 { return [] }
        var segs: [Segment] = []
        var run = 0
        var runStart = 0
        var segStart = 0
        var prevSegStart = 0
        func push(_ to: Int) {
            if to <= segStart { return }
            let cell = trail[segStart]
            let refFrom = cell <= 0 ? 0 : tracker.wordStarts[tracker.localWordOfPos[cell - 1]]
            let firstOfRun = segStart == runStart
            let contextFrom = firstOfRun && run == 0
                ? segStart
                : max(prevSegStart, segStart - Self.contextChars)
            segs.append(Segment(
                heardFrom: segStart,
                heardTo: to,
                refFrom: refFrom,
                refTo: trail[to - 1],
                run: run,
                contextFrom: contextFrom
            ))
            prevSegStart = segStart
        }
        for g in 1...n {
            let newRun = g < n && trail[g] < trail[g - 1]
            let cut = g - segStart >= Self.segmentCut
            if newRun || cut || g == n {
                push(g)
                if newRun {
                    run += 1
                    runStart = g
                }
                segStart = g
            }
        }
        return segs
    }

    private func alignSegment(_ seg: Segment) -> [Int: Span] {
        let heard = tracker.heard
        let ids = (seg.contextFrom..<seg.heardTo).map { table.id(heard[$0].ch) }
        let assign = TilawaAlignment.alignGlobal(heard: ids, ref: tracker.ref, from: seg.refFrom, to: seg.refTo, table: table)
        var first: [Int: Int] = [:]
        var last: [Int: Int] = [:]
        for (i, refIndex) in assign.enumerated() where refIndex >= 0 {
            let localWord = tracker.localWordOfPos[refIndex]
            let gi = seg.contextFrom + i
            if first[localWord] == nil { first[localWord] = gi }
            last[localWord] = gi
        }
        var spans: [Int: Span] = [:]
        for (w, f) in first {
            spans[w] = Span(from: f, to: last[w]! + 1, run: seg.run)
        }
        return spans
    }

    private func judge(_ spans: [Int: Span], settled: Bool) -> [TilawaWordVerdict] {
        guard let minWord = spans.keys.min(), let maxWord = spans.keys.max() else { return [] }
        let t = tracker
        let lastRun = lastRunIndex(t.trail)
        let cursorWord = max(0, t.cursorLocalWord)
        let cursorPending = !t.reachedEnd && !settled
        let dwell = settled ? 0 : cfg.commitDwell
        let heardLen = t.heard.count
        var out: [TilawaWordVerdict] = []
        for w in minWord...maxWord {
            let span = spans[w]
            let globalWord = t.firstWord + w
            let exp = Array(t.corpus.wordPhonemes(globalWord))
            let expLen = exp.count
            var pending = w == cursorWord && cursorPending
            if let span {
                pending = pending || span.to > heardLen - dwell || (span.run < lastRun && w >= cursorWord)
            }
            let heardCount = span.map { $0.to - $0.from } ?? 0
            if !pending && Double(heardCount) < cfg.minHeardFraction * Double(expLen) {
                if minWord < w && w < maxWord {
                    let ratio = expLen > 0 ? Double(heardCount) / Double(expLen) : 0
                    out.append(makeVerdict(globalWord, .skipped, distance: 1, heardRatio: ratio, margin: 0))
                }
                continue
            }
            guard let span else { continue }
            let from = span.from
            var to = span.to
            var heardSlice = sliceHeard(from, to)
            var distance = TilawaAlignment.normalizedDistance(table.encode(heardSlice), table.encode(exp), table)
            let atAyahEnd = t.corpus.wordInAyah[globalWord]
                == t.corpus.ayahWordCount(t.corpus.wordSurah[globalWord], t.corpus.wordAyah[globalWord]) - 1
            if distance > cfg.okDistance,
               let pausal = TilawaWaqf.pausalPhonemes(exp, plain: t.corpus.plain[globalWord], atAyahEnd: atAyahEnd) {
                let stop = stopBoundary(from: from, to: to)
                if stop >= 0 {
                    if stop != to {
                        to = stop
                        heardSlice = sliceHeard(from, to)
                    }
                    let d2 = TilawaAlignment.normalizedDistance(table.encode(heardSlice), table.encode(pausal), table)
                    if d2 < distance { distance = d2 }
                }
            }
            var margin = 0.0
            let spanHeard = span.to - span.from
            if spanHeard > 0 {
                for i in span.from..<span.to { margin += t.heard[i].margin }
                margin /= Double(spanHeard)
            }
            let heardRatio = expLen > 0 ? Double(spanHeard) / Double(expLen) : 0
            let state: TilawaVerdictState
            if pending {
                state = .pending
            } else if distance <= cfg.okDistance {
                state = .ok
            } else if distance <= cfg.unsureDistance || margin < cfg.minMargin {
                state = .unsure
            } else {
                state = .wrong
            }
            out.append(makeVerdict(globalWord, state, distance: distance, heardRatio: heardRatio, margin: margin))
        }
        return out
    }

    private func stopBoundary(from: Int, to: Int) -> Int {
        let heard = tracker.heard
        let end = min(heard.count, to + 4)
        if from + 1 > end { return -1 }
        for i in (from + 1)...end {
            if i == heard.count { return i }
            if heard[i].frame - heard[i - 1].frame >= cfg.settleFrames { return i }
        }
        return -1
    }

    private func lastRunIndex(_ trail: [Int]) -> Int {
        var run = 0
        if trail.count > 1 {
            for g in 1..<trail.count where trail[g] < trail[g - 1] { run += 1 }
        }
        return run
    }

    private func sliceHeard(_ from: Int, _ to: Int) -> PhonemeUnits {
        let heard = tracker.heard
        let end = min(to, heard.count)
        guard from < end else { return [] }
        return heard[from..<end].map(\.ch)
    }

    private func makeVerdict(
        _ globalWord: Int,
        _ state: TilawaVerdictState,
        distance: Double,
        heardRatio: Double,
        margin: Double
    ) -> TilawaWordVerdict {
        let c = tracker.corpus
        return TilawaWordVerdict(
            surah: c.wordSurah[globalWord],
            ayah: c.wordAyah[globalWord],
            word: c.wordInAyah[globalWord],
            wordIndex: globalWord,
            state: state,
            distance: distance,
            heardRatio: heardRatio,
            margin: margin
        )
    }
}
