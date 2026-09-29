import Foundation

// Ported from `@tilawa/core` `recitation/config.ts` + `recitation/corpus.ts` (MIT).

nonisolated struct TilawaEngineConfig: Sendable {
    var jumpCost: Double = 12
    var repeatCost: Double = 10
    var commitDwell = 6
    var okDistance = 0.15
    var unsureDistance = 0.4
    var minHeardFraction = 0.34
    var minMargin = 0.35
    var lostWindow = 120
    var lostRate = 0.35
    var holdWindow = 30
    var holdRate = 0.45
    var searchMinChars = 12
    var searchQueryChars = 250
    var searchDecisiveDistance = 0.35
    var searchDecisiveMargin = 0.1
    var searchEveryFrames = 25
    var searchEveryChars = 12
    var locateFailedFrames = 375
    var relocateEveryFrames = 37
    var relocateQueryChars = 100
    var relocateMaxDistance = 0.3
    var relocateRateMargin = 0.12
    var idleFrames = 200
    var maxStruggles = 3
    var settleFrames = 25

    static let `default` = TilawaEngineConfig()
}

nonisolated enum TilawaAudio {
    static let bufferCap = 1000
    static let sampleRate = 16_000
    static let fbankBins = 80
    static let frameLength = 400
    static let frameShift = 160
}

nonisolated struct TilawaSurahRecord: Sendable {
    let n: Int
    let name: String
    let nameEn: String
    let ayahCount: Int
    let firstWord: Int
    let endWord: Int
}

/// The phoneme corpus (`zipformer_quran.json`, v2): every Quran word's phonemes laid end to end.
nonisolated final class TilawaCorpus: @unchecked Sendable {
    let text: PhonemeUnits
    let wordStart: [Int]
    let wordSurah: [Int]
    let wordAyah: [Int]
    let wordInAyah: [Int]
    let plain: [PhonemeUnits]
    let ayahFirst: [[Int]]
    let ayahWords: [[Int]]
    let surahs: [TilawaSurahRecord]
    let wordCount: Int

    private struct RawCorpus: Decodable {
        let v: Int
        let surahs: [RawSurah]
    }

    private struct RawSurah: Decodable {
        let n: Int
        let name: String
        let nameEn: String
        let ayahs: [RawAyah]
    }

    private struct RawAyah: Decodable {
        let n: Int
        /// Each word is `[mushaf glyphs, phonemes, plain text]`.
        let w: [[String]]
    }

    enum LoadError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let message): return "Recitation corpus is invalid: \(message)"
            }
        }
    }

    init(data: Data) throws {
        let raw = try JSONDecoder().decode(RawCorpus.self, from: data)
        guard raw.v == 2 else { throw LoadError.invalid("must be v2") }
        guard raw.surahs.count == 114 else { throw LoadError.invalid("must contain 114 surahs") }

        var text: PhonemeUnits = []
        text.reserveCapacity(700_000)
        var wordStart: [Int] = []
        var wordSurah: [Int] = []
        var wordAyah: [Int] = []
        var wordInAyah: [Int] = []
        var plain: [PhonemeUnits] = []
        var ayahFirst: [[Int]] = []
        var ayahWords: [[Int]] = []
        var surahs: [TilawaSurahRecord] = []
        var w = 0

        for s in raw.surahs {
            let firstWord = w
            var firstArr: [Int] = []
            var countArr: [Int] = []
            for (ai, a) in s.ayahs.enumerated() {
                guard a.n == ai + 1 else { throw LoadError.invalid("surah \(s.n) ayah index \(ai) has n=\(a.n)") }
                firstArr.append(w)
                countArr.append(a.w.count)
                for (wi, triple) in a.w.enumerated() {
                    guard triple.count >= 3 else { throw LoadError.invalid("word \(s.n):\(a.n):\(wi) is malformed") }
                    wordStart.append(text.count)
                    wordSurah.append(s.n)
                    wordAyah.append(a.n)
                    wordInAyah.append(wi)
                    plain.append(triple[2].phonemeUnits)
                    text.append(contentsOf: triple[1].utf16)
                    w += 1
                }
            }
            ayahFirst.append(firstArr)
            ayahWords.append(countArr)
            surahs.append(TilawaSurahRecord(
                n: s.n,
                name: s.name,
                nameEn: s.nameEn,
                ayahCount: s.ayahs.count,
                firstWord: firstWord,
                endWord: w
            ))
        }
        wordStart.append(text.count)

        self.text = text
        self.wordStart = wordStart
        self.wordSurah = wordSurah
        self.wordAyah = wordAyah
        self.wordInAyah = wordInAyah
        self.plain = plain
        self.ayahFirst = ayahFirst
        self.ayahWords = ayahWords
        self.surahs = surahs
        self.wordCount = w
    }

    func wordAt(_ offset: Int) -> Int {
        if offset < 0 { return 0 }
        if offset >= text.count { return wordCount - 1 }
        var lo = 0
        var hi = wordCount
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if wordStart[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func wordIndex(surah: Int, ayah: Int, word: Int) -> Int? {
        guard hasAyah(surah, ayah) else { return nil }
        guard word >= 0, word < ayahWordCount(surah, ayah) else { return nil }
        return ayahFirstWord(surah, ayah) + word
    }

    func hasAyah(_ surah: Int, _ ayah: Int) -> Bool {
        guard surah >= 1, surah <= 114, surah <= surahs.count else { return false }
        return ayah >= 1 && ayah <= surahs[surah - 1].ayahCount
    }

    func ayahFirstWord(_ surah: Int, _ ayah: Int) -> Int {
        ayahFirst[surah - 1][ayah - 1]
    }

    func ayahWordCount(_ surah: Int, _ ayah: Int) -> Int {
        ayahWords[surah - 1][ayah - 1]
    }

    func ayahPhonemes(_ surah: Int, _ ayah: Int) -> ArraySlice<UInt16> {
        let first = ayahFirstWord(surah, ayah)
        let end = first + ayahWordCount(surah, ayah)
        return text[wordStart[first]..<wordStart[end]]
    }

    func wordPhonemes(_ wordIndex: Int) -> ArraySlice<UInt16> {
        text[wordStart[wordIndex]..<wordStart[wordIndex + 1]]
    }
}
