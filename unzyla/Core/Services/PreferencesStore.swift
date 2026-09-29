import Foundation

@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private let mushafKey = "mushafId"
    private let narratorsKey = "selectedNarrators"
    private let darkModeKey = "isMushafDarkMode"
    private let hasChosenMushafKey = "hasChosenMushaf"
    private let ayahPromptCueCountKey = "ayahPromptCueCount"
    private let translationLanguageKey = "translationLanguage"
    private let markTypeOrderKey = "markTypeOrder"
    private let markTypeColorsKey = "markTypeColors"
    private let tajweedMarkingEnabledKey = "isTajweedMarkingEnabled"
    private let lastPageKeyPrefix = "lastMushafPage."

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

    /// Last free-reading page for a mushaf (1-based). `nil` if never saved.
    func lastPage(forMushaf id: Int) -> Int? {
        let key = lastPageKeyPrefix + String(id)
        guard defaults.object(forKey: key) != nil else { return nil }
        let page = defaults.integer(forKey: key)
        return page > 0 ? page : nil
    }

    func setLastPage(_ page: Int, forMushaf id: Int) {
        guard page > 0 else { return }
        defaults.set(page, forKey: lastPageKeyPrefix + String(id))
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

    /// How many cue word blocks to show after verse endings in helper mode (0…2).
    var ayahPromptCueCount: Int {
        get {
            guard defaults.object(forKey: ayahPromptCueCountKey) != nil else { return 2 }
            return min(2, max(0, defaults.integer(forKey: ayahPromptCueCountKey)))
        }
        set {
            defaults.set(min(2, max(0, newValue)), forKey: ayahPromptCueCountKey)
        }
    }

    var translationLanguage: TranslationLanguage {
        get { TranslationLanguage(rawValue: defaults.string(forKey: translationLanguageKey) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: translationLanguageKey) }
    }

    /// When false, marking uses Mistake only and type pills are hidden.
    var isTajweedMarkingEnabled: Bool {
        get { defaults.bool(forKey: tajweedMarkingEnabledKey) }
        set { defaults.set(newValue, forKey: tajweedMarkingEnabledKey) }
    }

    /// Preferred toolbar order for mark types (raw values).
    var markTypeOrder: [String] {
        get {
            guard let data = defaults.data(forKey: markTypeOrderKey),
                  let order = try? JSONDecoder().decode([String].self, from: data),
                  !order.isEmpty
            else {
                return MistakeMarkType.allCases.map(\.rawValue)
            }
            return order
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: markTypeOrderKey)
            }
        }
    }

    /// Per-type highlight colors as `#RRGGBB` hex strings.
    var markTypeColors: [String: String] {
        get {
            guard let data = defaults.data(forKey: markTypeColorsKey),
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return MarkTypeAppearance.defaultColors
            }
            var merged = MarkTypeAppearance.defaultColors
            for (key, value) in map {
                merged[key] = value
            }
            return merged
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: markTypeColorsKey)
            }
        }
    }
}
