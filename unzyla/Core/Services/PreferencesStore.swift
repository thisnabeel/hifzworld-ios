import Foundation

@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private let mushafKey = "mushafId"
    private let narratorsKey = "selectedNarrators"
    private let darkModeKey = "isMushafDarkMode"

    var mushafID: Int {
        get {
            let saved = defaults.string(forKey: mushafKey) ?? "3"
            return Int(saved) ?? 3
        }
        set {
            defaults.set(String(newValue), forKey: mushafKey)
        }
    }

    var selectedNarratorIDs: [String] {
        get {
            guard let data = defaults.data(forKey: narratorsKey),
                  let ids = try? JSONDecoder().decode([String].self, from: data),
                  !ids.isEmpty
            else {
                return [NarratorCatalog.hafsID]
            }
            return ids.contains(NarratorCatalog.hafsID) ? ids : [NarratorCatalog.hafsID] + ids
        }
        set {
            let withHafs = newValue.contains(NarratorCatalog.hafsID)
                ? newValue
                : [NarratorCatalog.hafsID] + newValue
            if let data = try? JSONEncoder().encode(withHafs) {
                defaults.set(data, forKey: narratorsKey)
            }
        }
    }

    var isMushafDarkMode: Bool {
        get { defaults.bool(forKey: darkModeKey) }
        set { defaults.set(newValue, forKey: darkModeKey) }
    }
}
