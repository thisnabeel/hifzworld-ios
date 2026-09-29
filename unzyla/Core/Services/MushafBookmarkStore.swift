import Foundation
import Observation

@MainActor
@Observable
final class MushafBookmarkStore {
    static let shared = MushafBookmarkStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "mushafBookmarks."

    /// Cached pages for the active mushaf (sorted ascending).
    private(set) var pages: [Int] = []
    private(set) var mushafID: Int = PreferencesStore.shared.mushafID

    private init() {
        reload(mushafID: PreferencesStore.shared.mushafID)
    }

    func reload(mushafID: Int) {
        self.mushafID = mushafID
        pages = load(mushafID: mushafID).sorted()
    }

    func isBookmarked(_ page: Int, mushafID: Int? = nil) -> Bool {
        let id = mushafID ?? self.mushafID
        if id == self.mushafID {
            return pages.contains(page)
        }
        return load(mushafID: id).contains(page)
    }

    @discardableResult
    func toggle(page: Int, mushafID: Int? = nil) -> Bool {
        let id = mushafID ?? self.mushafID
        var set = load(mushafID: id)
        if set.contains(page) {
            set.remove(page)
        } else {
            set.insert(page)
        }
        persist(set, mushafID: id)
        if id == self.mushafID {
            pages = set.sorted()
        } else if id != self.mushafID {
            // no-op for other mushaf cache
        }
        return set.contains(page)
    }

    func remove(page: Int, mushafID: Int? = nil) {
        let id = mushafID ?? self.mushafID
        var set = load(mushafID: id)
        set.remove(page)
        persist(set, mushafID: id)
        if id == self.mushafID {
            pages = set.sorted()
        }
    }

    private func storageKey(mushafID: Int) -> String {
        keyPrefix + String(mushafID)
    }

    private func load(mushafID: Int) -> Set<Int> {
        let key = storageKey(mushafID: mushafID)
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Int].self, from: data)
        else {
            return []
        }
        return Set(decoded.filter { $0 > 0 })
    }

    private func persist(_ pages: Set<Int>, mushafID: Int) {
        let sorted = pages.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: storageKey(mushafID: mushafID))
        }
    }
}
