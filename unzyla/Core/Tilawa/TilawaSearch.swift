import Foundation

// Ported from `@tilawa/core` `recitation/search.ts` + `recitation/fallback.ts` (MIT).

nonisolated struct TilawaSearchHint: Equatable, Sendable {
    let surah: Int
    let ayah: Int
}

nonisolated struct TilawaSearchHit: Equatable {
    var surah: Int
    var ayah: Int
    var word: Int
    var wordIndex: Int
    var refOffset: Int
    var refEnd: Int
    var queryStart: Int
    var distance: Double
}

nonisolated struct TilawaSearchResult {
    var hits: [TilawaSearchHit]
    var decisive: Bool

    static let empty = TilawaSearchResult(hits: [], decisive: false)
}

nonisolated struct TilawaStripResult: Equatable {
    let offset: Int
    let basmala: Bool
    let basmalaOffset: Int
}

nonisolated struct TilawaFallbackHit: Equatable, Sendable {
    let surah: Int
    let ayah: Int
    let distance: Double
    let isBasmala: Bool
}

nonisolated enum TilawaPreamble {
    static let istiadha: PhonemeUnits = "\u{621}\u{64E}\u{639}\u{64F}\u{6E5}\u{6E5}\u{630}\u{64F}\u{628}\u{650}\u{644}\u{644}\u{64E}\u{627}\u{627}\u{647}\u{650}\u{645}\u{650}\u{646}\u{64E}\u{634}\u{634}\u{64E}\u{64A}\u{64A}\u{637}\u{64E}\u{627}\u{627}\u{646}\u{650}\u{631}\u{631}\u{64E}\u{62C}\u{650}\u{6E6}\u{6E6}\u{645}".phonemeUnits
    static let basmala: PhonemeUnits = "\u{628}\u{650}\u{633}\u{645}\u{650}\u{644}\u{644}\u{64E}\u{627}\u{627}\u{647}\u{650}\u{631}\u{631}\u{64E}\u{62D}\u{645}\u{64E}\u{627}\u{627}\u{646}\u{650}\u{631}\u{631}\u{64E}\u{62D}\u{650}\u{6E6}\u{6E6}\u{6E6}\u{6E6}\u{645}".phonemeUnits

    private static let maxDistance = 0.3
    private static let growingDistance = 0.35

    /// Skip a leading isti'adha and/or basmala so the search sees the ayah itself.
    static func strip(_ query: PhonemeUnits, table: TilawaCostTable) -> TilawaStripResult {
        var offset = 0
        var sawBasmala = false
        var basmalaOffset = 0
        for (index, phrase) in [Self.istiadha, Self.basmala].enumerated() {
            let rest = query.count - offset
            if rest <= 0 { break }
            let l = phrase.count
            var bestLen = -1
            var bestDist = Double.infinity
            var bestTie = Int.max
            let lo = max(1, l - 4)
            let hi = min(rest, l + 4)
            if lo <= hi {
                for len in lo...hi {
                    let slice = table.encode(query[offset..<(offset + len)])
                    let target = table.encode(phrase[0..<min(phrase.count, len)])
                    let d = TilawaAlignment.normalizedDistance(slice, target, table)
                    let tie = abs(len - l)
                    if d < bestDist || (d == bestDist && tie < bestTie) {
                        bestDist = d
                        bestLen = len
                        bestTie = tie
                    }
                }
            }
            if bestLen >= 0 && bestDist <= maxDistance {
                if index == 1 {
                    sawBasmala = true
                    basmalaOffset = offset
                }
                offset += bestLen
            }
        }
        return TilawaStripResult(offset: offset, basmala: sawBasmala, basmalaOffset: basmalaOffset)
    }

    static func isGrowingIstiadha(_ query: PhonemeUnits, table: TilawaCostTable) -> Bool {
        if query.count > istiadha.count + 4 { return false }
        let target = istiadha[0..<min(istiadha.count, query.count)]
        return TilawaAlignment.normalizedDistance(table.encode(query), table.encode(target), table) <= growingDistance
    }
}

/// Whole-Quran 5-gram index over the phoneme corpus, verified by semi-global alignment.
nonisolated final class TilawaQuranIndex: @unchecked Sendable {
    private static let gram = 5
    private static let bucketBits = 18
    private static let buckets = 1 << bucketBits
    private static let bucketMask = UInt32(buckets - 1)
    private static let windowBits = 5
    private static let maxPostings = 400
    private static let candidateWindows = 24
    private static let verifyMarginBefore = 16
    private static let verifyMarginAfter = 32
    private static let minAligned = 20
    private static let surahGap = 8
    private static let shortQuery = 100

    let corpus: TilawaCorpus
    let table: TilawaCostTable
    private let cfg: TilawaEngineConfig
    private let sep: [UInt8]
    private let surahSepStart: [Int]
    private let surahSepLen: [Int]
    private let surahCorpusStart: [Int]
    private let bucketStart: [Int32]
    private let postings: [Int32]

    static func fnv1aBucket(_ ids: UnsafeBufferPointer<UInt8>, at: Int) -> Int {
        var h: UInt32 = 2_166_136_261
        for k in 0..<gram {
            h = (h ^ UInt32(ids[at + k])) &* 16_777_619
        }
        return Int(h & bucketMask)
    }

    init(corpus: TilawaCorpus, config: TilawaEngineConfig = .default, table: TilawaCostTable = .shared) {
        self.corpus = corpus
        self.cfg = config
        self.table = table
        let nSurah = corpus.surahs.count
        var sepStart = [Int](repeating: 0, count: nSurah)
        var sepLenArr = [Int](repeating: 0, count: nSurah)
        var corpusStart = [Int](repeating: 0, count: nSurah)
        var sep: [UInt8] = []
        sep.reserveCapacity(corpus.text.count + nSurah * Self.surahGap)
        for i in 0..<nSurah {
            let s = corpus.surahs[i]
            let cs = corpus.wordStart[s.firstWord]
            let ce = corpus.wordStart[s.endWord]
            corpusStart[i] = cs
            sepLenArr[i] = ce - cs
            sepStart[i] = sep.count
            sep.append(contentsOf: table.encode(corpus.text[cs..<ce]))
            if i < nSurah - 1 {
                sep.append(contentsOf: repeatElement(TilawaPhoneme.unknownID, count: Self.surahGap))
            }
        }
        self.sep = sep
        self.surahSepStart = sepStart
        self.surahSepLen = sepLenArr
        self.surahCorpusStart = corpusStart

        var counts = [Int32](repeating: 0, count: Self.buckets)
        let last = sep.count - Self.gram
        var bucketOf = [Int32](repeating: 0, count: max(0, last + 1))
        sep.withUnsafeBufferPointer { ids in
            if last >= 0 {
                for p in 0...last {
                    let b = Self.fnv1aBucket(ids, at: p)
                    bucketOf[p] = Int32(b)
                    counts[b] += 1
                }
            }
        }
        var starts = [Int32](repeating: 0, count: Self.buckets + 1)
        for b in 0..<Self.buckets { starts[b + 1] = starts[b] + counts[b] }
        var postings = [Int32](repeating: 0, count: Int(starts[Self.buckets]))
        var cursor = starts
        if last >= 0 {
            for p in 0...last {
                let b = Int(bucketOf[p])
                postings[Int(cursor[b])] = Int32(p)
                cursor[b] += 1
            }
        }
        self.bucketStart = starts
        self.postings = postings
    }

    func search(_ query: PhonemeUnits, hint: TilawaSearchHint?, limit: Int = 3) -> TilawaSearchResult {
        if query.count < cfg.searchMinChars { return .empty }
        if TilawaPreamble.isGrowingIstiadha(query, table: table) { return .empty }

        let stripped = TilawaPreamble.strip(query, table: table)
        let rest = Array(query[stripped.offset...])
        if rest.count < cfg.searchMinChars { return .empty }

        if stripped.basmala {
            let fromBasmala = Array(query[stripped.basmalaOffset...])
            var inner = searchSlice(fromBasmala, hint: hint, limit: limit, alignedBonus: 0)
            if inner.decisive, let first = inner.hits.first, first.queryStart <= 2 {
                for i in inner.hits.indices { inner.hits[i].queryStart += stripped.basmalaOffset }
                return inner
            }
        }

        var result = searchSlice(rest, hint: hint, limit: limit, alignedBonus: 0)
        var bonus = 0
        var collapsed = Set<Int>()
        for i in result.hits.indices {
            let h = result.hits[i]
            if stripped.basmala && h.surah == 1 && h.ayah == 2 && h.word <= 3 {
                result.hits[i] = TilawaSearchHit(
                    surah: 1, ayah: 1, word: 0, wordIndex: 0,
                    refOffset: 0, refEnd: 0, queryStart: 0, distance: h.distance
                )
                collapsed.insert(i)
                if i == 0 { bonus = stripped.offset - stripped.basmalaOffset }
            }
        }
        result.decisive = isDecisive(result.hits, queryLength: rest.count, alignedBonus: bonus, hint: hint)
        for i in result.hits.indices {
            if collapsed.contains(i) {
                result.hits[i].queryStart = stripped.basmalaOffset
            } else {
                result.hits[i].queryStart += stripped.offset
            }
        }
        if result.decisive || query.count <= Self.shortQuery { return result }

        var tail = search(Array(query.suffix(Self.shortQuery)), hint: hint, limit: limit)
        if tail.decisive {
            let add = query.count - Self.shortQuery
            for i in tail.hits.indices { tail.hits[i].queryStart += add }
            return tail
        }
        return result
    }

    private func searchSlice(
        _ query: PhonemeUnits,
        hint: TilawaSearchHint?,
        limit: Int,
        alignedBonus: Int
    ) -> TilawaSearchResult {
        if query.count < cfg.searchMinChars { return .empty }
        let qids = table.encode(query)
        var votes: [Int: Int] = [:]
        let last = qids.count - Self.gram
        if last >= 0 {
            qids.withUnsafeBufferPointer { ids in
                for u in 0...last {
                    let b = Self.fnv1aBucket(ids, at: u)
                    let a = Int(bucketStart[b])
                    let z = Int(bucketStart[b + 1])
                    if z - a > Self.maxPostings { continue }
                    for i in a..<z {
                        let w = (Int(postings[i]) - u) >> Self.windowBits
                        votes[w, default: 0] += 1
                    }
                }
            }
        }
        let windows = votes.sorted { x, y in
            x.value != y.value ? x.value > y.value : x.key < y.key
        }
        var verified: [(hit: TilawaSearchHit, order: Int)] = []
        for (w, _) in windows.prefix(Self.candidateWindows) {
            let start = w << Self.windowBits
            let from = max(0, start - Self.verifyMarginBefore)
            let to = min(sep.count, start + qids.count + Self.verifyMarginAfter)
            let al = TilawaAlignment.alignSemiGlobal(query: qids, ref: sep, from: from, to: to, table: table, headSkipCost: 0.5)
            if qids.count - al.queryStart < cfg.searchMinChars { continue }
            let refOffset = mapSep(al.refStart)
            let refEnd = mapSep(al.refEnd)
            if refEnd <= refOffset { continue }
            let wordIndex = corpus.wordAt(refOffset)
            verified.append((TilawaSearchHit(
                surah: corpus.wordSurah[wordIndex],
                ayah: corpus.wordAyah[wordIndex],
                word: corpus.wordInAyah[wordIndex],
                wordIndex: wordIndex,
                refOffset: refOffset,
                refEnd: refEnd,
                queryStart: al.queryStart,
                distance: al.distance
            ), verified.count))
        }
        verified.sort { a, b in
            if a.hit.distance != b.hit.distance { return a.hit.distance < b.hit.distance }
            if a.hit.wordIndex != b.hit.wordIndex { return a.hit.wordIndex < b.hit.wordIndex }
            return a.order < b.order
        }
        var hits: [TilawaSearchHit] = []
        for (h, _) in verified {
            if hits.contains(where: { !(h.refEnd <= $0.refOffset || h.refOffset >= $0.refEnd) }) { continue }
            hits.append(h)
            if hits.count >= max(limit, 8) { break }
        }
        applyHint(&hits, hint: hint)
        let out = Array(hits.prefix(limit))
        return TilawaSearchResult(
            hits: out,
            decisive: isDecisive(out, queryLength: query.count, alignedBonus: alignedBonus, hint: hint)
        )
    }

    private func applyHint(_ hits: inout [TilawaSearchHit], hint: TilawaSearchHint?) {
        guard let hint, let best = hits.first else { return }
        let nearIdx = hits.indices.filter { hits[$0].distance <= best.distance + cfg.searchDecisiveMargin }
        var hinted = nearIdx.filter { hits[$0].surah == hint.surah }
        if hinted.isEmpty { return }
        let target = corpus.hasAyah(hint.surah, hint.ayah) ? corpus.ayahFirstWord(hint.surah, hint.ayah) : 0
        hinted.sort { a, b in
            let da = abs(hits[a].wordIndex - target)
            let db = abs(hits[b].wordIndex - target)
            if da != db { return da < db }
            if hits[a].wordIndex != hits[b].wordIndex { return hits[a].wordIndex < hits[b].wordIndex }
            return a < b
        }
        let chosen = hinted[0]
        let picked = hits[chosen]
        hits.remove(at: chosen)
        hits.insert(picked, at: 0)
    }

    private func isDecisive(
        _ hits: [TilawaSearchHit],
        queryLength: Int,
        alignedBonus: Int,
        hint: TilawaSearchHint?
    ) -> Bool {
        guard let best = hits.first else { return false }
        let aligned = queryLength - best.queryStart + alignedBonus
        if best.distance > cfg.searchDecisiveDistance { return false }
        if aligned < Self.minAligned { return false }
        guard let rival = rival(hits, hint: hint) else { return true }
        return rival.distance - best.distance >= cfg.searchDecisiveMargin
    }

    private func rival(_ hits: [TilawaSearchHit], hint: TilawaSearchHint?) -> TilawaSearchHit? {
        guard let best = hits.first else { return nil }
        if let hint {
            let cap = best.distance + cfg.searchDecisiveMargin
            if hits.contains(where: { $0.distance <= cap && $0.surah == hint.surah }) {
                return hits.dropFirst().first(where: { $0.distance > cap })
            }
        }
        return hits.count > 1 ? hits[1] : nil
    }

    private func mapSep(_ sepOff: Int) -> Int {
        var lo = 0
        var hi = surahSepStart.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if surahSepStart[mid] <= sepOff { lo = mid } else { hi = mid - 1 }
        }
        let local = sepOff - surahSepStart[lo]
        let len = surahSepLen[lo]
        let cs = surahCorpusStart[lo]
        if local >= len { return cs + len }
        if local < 0 { return cs }
        return cs + local
    }
}

/// Whole-ayah nearest match over a finished transcript, for when streaming locked onto nothing.
nonisolated final class TilawaAyahFallback: @unchecked Sendable {
    private struct EncodedAyah {
        let surah: Int
        let ayah: Int
        let ids: [UInt8]
    }

    private let ayahs: [EncodedAyah]
    private let table: TilawaCostTable
    private let minChars: Int

    init(corpus: TilawaCorpus, config: TilawaEngineConfig = .default, table: TilawaCostTable = .shared) {
        self.table = table
        self.minChars = config.searchMinChars
        var ayahs: [EncodedAyah] = []
        for s in corpus.surahs {
            for a in 1...s.ayahCount {
                ayahs.append(EncodedAyah(surah: s.n, ayah: a, ids: table.encode(corpus.ayahPhonemes(s.n, a))))
            }
        }
        self.ayahs = ayahs
    }

    func best(for text: PhonemeUnits, maxDistance: Double = 0.5) -> TilawaFallbackHit? {
        rank(text, maxDistance: maxDistance, limit: 1).first
    }

    /// Nearest ayahs by normalized distance, best first.
    func rank(_ text: PhonemeUnits, maxDistance: Double = 0.5, limit: Int) -> [TilawaFallbackHit] {
        if text.isEmpty { return [] }
        let stripped = TilawaPreamble.strip(text, table: table)
        let rest = Array(text[stripped.offset...])
        if stripped.basmala && rest.count < minChars {
            return [TilawaFallbackHit(surah: 1, ayah: 1, distance: 0, isBasmala: true)]
        }
        let q = table.encode(rest.count >= 3 ? rest : text)
        var scored: [TilawaFallbackHit] = []
        for a in ayahs {
            let qa = Double(q.count)
            let aa = Double(a.ids.count)
            if aa > 2.5 * qa + 8 || qa > 2.5 * aa + 8 { continue }
            let d = TilawaAlignment.normalizedDistance(q, a.ids, table)
            if d <= maxDistance {
                scored.append(TilawaFallbackHit(surah: a.surah, ayah: a.ayah, distance: d, isBasmala: false))
            }
        }
        // Stable on corpus order for ties, matching the original's first-best-wins scan.
        return Array(scored.enumerated()
            .sorted { $0.element.distance != $1.element.distance ? $0.element.distance < $1.element.distance : $0.offset < $1.offset }
            .prefix(limit)
            .map(\.element))
    }
}
