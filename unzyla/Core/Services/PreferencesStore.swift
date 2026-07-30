import Foundation

@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private let mushafKey = "mushafId"
    private let narratorsKey = "selectedNarrators"
    private let darkModeKey = "isMushafDarkMode"
    private let hasChosenMushafKey = "hasChosenMushaf"

    private init() {
        migrateMushafOnboardingFlagIfNeeded()
    }

    /// Prior installs never set `hasChosenMushaf`; skip the picker if they already have app state.
    private func migrateMushafOnboardingFlagIfNeeded() {
        guard defaults.object(forKey: hasChosenMushafKey) == nil else { return }
        let hasPriorState =
            defaults.object(forKey: mushafKey) != nil ||
            defaults.object(forKey: narratorsKey) != nil ||
            defaults.object(forKey: darkModeKey) != nil ||
            defaults.data(forKey: "mushafBundles") != nil
        if hasPriorState {
            defaults.set(true, forKey: hasChosenMushafKey)
        }
    }

    var mushafID: Int {
        get {
            let saved = defaults.string(forKey: mushafKey) ?? "3"
            return Int(saved) ?? 3
        }
        set {
            defaults.set(String(newValue), forKey: mushafKey)
        }
    }

    /// First-launch mushaf picker; once true, onboarding is not shown again.
    var hasChosenMushaf: Bool {
        get { defaults.bool(forKey: hasChosenMushafKey) }
        set { defaults.set(newValue, forKey: hasChosenMushafKey) }
    }

    var needsMushafOnboarding: Bool { !hasChosenMushaf }

    func chooseMushaf(_ id: Int) {
        mushafID = id
        hasChosenMushaf = true
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
