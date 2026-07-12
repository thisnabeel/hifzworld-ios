import Foundation

enum SurahMeta {
    private static let cache: [String: SurahEntry] = load()

    struct SurahEntry: Codable {
        let ar: String?
        let en: String?
        let arabic: String?
        let english: String?
        let enAlias: String?

        enum CodingKeys: String, CodingKey {
            case ar, en, arabic, english
            case enAlias = "en_alias"
        }

        var arabicName: String {
            (ar ?? arabic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var englishName: String {
            (en ?? enAlias ?? english ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func load() -> [String: SurahEntry] {
        guard let url = Bundle.main.url(forResource: "surah-meta", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: SurahEntry].self, from: data)
        else { return [:] }
        return dict
    }

    static func arabicName(_ number: Int) -> String {
        let entry = cache[String(number)]
        let name = entry?.arabicName ?? ""
        return name.isEmpty ? "سورة \(number)" : name
    }

    static func englishName(_ number: Int) -> String {
        cache[String(number)]?.englishName ?? ""
    }
}
