import Foundation

struct ShubahWordTiming: Codable {
    let word: String
    let start: Double
    let end: Double
}

struct ShubahTimestampFile: Codable {
    let wordSegments: [ShubahWordTiming]?

    enum CodingKeys: String, CodingKey {
        case wordSegments = "word_segments"
    }
}

enum ShubahTimestamps {
    private static var cache: [Int: [ShubahWordTiming]] = [:]

    static func audioURL(surah: Int) -> URL? {
        let padded = String(format: "%03d", surah)
        return URL(string: "https://download.quranicaudio.com/quran/abdurrashid_sufi_shu3ba/\(padded).mp3")
    }

    static func timings(surah: Int) -> [ShubahWordTiming] {
        if let cached = cache[surah] { return cached }
        let name = String(format: "%03d", surah)
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/shubah-timestamps"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ShubahTimestampFile.self, from: data)
        else { return [] }
        let segments = file.wordSegments ?? []
        cache[surah] = segments
        return segments
    }

    static func segment(surah: Int, wordText: String) -> ShubahWordTiming? {
        let normalized = normalize(wordText)
        return timings(surah: surah).first { normalize($0.word) == normalized }
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0640}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
