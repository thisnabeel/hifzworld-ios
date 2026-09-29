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

    /// Weekly recitation portion (Hamzah az-Zaiyyat): 1=1–4, 2=5–9, 3=10–16, 4=17–25, 5=26–36, 6=37–49, 7=50–114.
    static func manzil(forSurah number: Int) -> Int? {
        switch number {
        case 1...4: return 1
        case 5...9: return 2
        case 10...16: return 3
        case 17...25: return 4
        case 26...36: return 5
        case 37...49: return 6
        case 50...114: return 7
        default: return nil
        }
    }
}
