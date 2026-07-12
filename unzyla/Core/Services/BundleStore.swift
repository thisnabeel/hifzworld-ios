import Foundation
import Observation

@MainActor
@Observable
final class BundleStore {
    static let shared = BundleStore()

    private let storageKey = "mushafBundles"
    private let defaults = UserDefaults.standard

    private(set) var bundles: [MushafBundle] = []

    init() {
        load()
    }

    func createBundle(title: String, description: String) -> MushafBundle {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundle = MushafBundle(
            title: trimmedTitle.isEmpty ? "Untitled Bundle" : trimmedTitle,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        bundles.insert(bundle, at: 0)
        save()
        return bundle
    }

    func deleteBundle(id: UUID) {
        bundles.removeAll { $0.id == id }
        save()
    }

    func updateBundle(id: UUID, title: String, description: String) {
        guard let index = bundles.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        bundles[index].title = trimmedTitle.isEmpty ? "Untitled Bundle" : trimmedTitle
        bundles[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        bundles[index].updatedAt = Date()
        save()
    }

    func bundle(id: UUID) -> MushafBundle? {
        bundles.first { $0.id == id }
    }

    func containsPage(_ page: Int, in bundleID: UUID) -> Bool {
        bundle(id: bundleID)?.pageNumbers.contains(page) ?? false
    }

    @discardableResult
    func addPage(_ page: Int, to bundleID: UUID) -> Bool {
        guard let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return false }
        guard !bundles[index].pageNumbers.contains(page) else { return false }

        var pages = bundles[index].pageNumbers
        if let insertIndex = pages.firstIndex(where: { $0 > page }) {
            pages.insert(page, at: insertIndex)
        } else {
            pages.append(page)
        }
        bundles[index].pageNumbers = pages
        bundles[index].updatedAt = Date()
        save()
        return true
    }

    @discardableResult
    func removePage(_ page: Int, from bundleID: UUID) -> Bool {
        guard let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return false }
        guard let pageIndex = bundles[index].pageNumbers.firstIndex(of: page) else { return false }
        bundles[index].pageNumbers.remove(at: pageIndex)
        bundles[index].updatedAt = Date()
        save()
        return true
    }

    func togglePage(_ page: Int, in bundleID: UUID) {
        if containsPage(page, in: bundleID) {
            removePage(page, from: bundleID)
        } else {
            addPage(page, to: bundleID)
        }
    }

    @discardableResult
    func addPageRange(from start: Int, through end: Int, to bundleID: UUID, maxPage: Int = 604) -> Int {
        guard let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return 0 }
        let low = max(1, min(start, end))
        let high = min(maxPage, max(start, end))
        guard low <= high else { return 0 }

        var pages = Set(bundles[index].pageNumbers)
        let beforeCount = pages.count
        for page in low...high {
            pages.insert(page)
        }
        guard pages.count > beforeCount else { return 0 }

        bundles[index].pageNumbers = pages.sorted()
        bundles[index].updatedAt = Date()
        save()
        return pages.count - beforeCount
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MushafBundle].self, from: data)
        else {
            bundles = []
            return
        }
        bundles = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        bundles.sort { $0.updatedAt > $1.updatedAt }
        if let data = try? JSONEncoder().encode(bundles) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func bundle(serverID: UUID) -> MushafBundle? {
        bundles.first { $0.serverID == serverID }
    }

    func attachServerID(_ serverID: UUID, to localID: UUID) {
        guard let index = bundles.firstIndex(where: { $0.id == localID }) else { return }
        bundles[index].serverID = serverID
        save()
    }

    func mergeRemoteBundles(owned: [RemoteMushafBundle], shared: [RemoteMushafBundle], defaultMushafID: Int) {
        var merged: [MushafBundle] = []

        for remote in owned + shared {
            let isShared = shared.contains(where: { $0.id == remote.id })
            if let index = bundles.firstIndex(where: { $0.serverID == remote.id }) {
                var bundle = bundles[index]
                bundle.title = remote.title
                bundle.description = remote.description
                bundle.pageNumbers = remote.pageNumbers
                bundle.mushafID = remote.mushafID
                bundle.isShared = isShared
                bundle.updatedAt = remote.updatedAt ?? Date()
                merged.append(bundle)
            } else {
                merged.append(
                    MushafBundle(
                        serverID: remote.id,
                        title: remote.title,
                        description: remote.description,
                        pageNumbers: remote.pageNumbers,
                        mushafID: remote.mushafID,
                        isShared: isShared,
                        createdAt: remote.createdAt ?? Date(),
                        updatedAt: remote.updatedAt ?? Date()
                    )
                )
            }
        }

        let unsynced = bundles.filter { $0.serverID == nil }
        bundles = (merged + unsynced).sorted { $0.updatedAt > $1.updatedAt }
        save()
    }

    func upsertAcceptedShare(_ remote: RemoteMushafBundle) {
        if let index = bundles.firstIndex(where: { $0.serverID == remote.id }) {
            bundles[index].isShared = true
            bundles[index].title = remote.title
            bundles[index].description = remote.description
            bundles[index].pageNumbers = remote.pageNumbers
            bundles[index].updatedAt = Date()
        } else {
            bundles.insert(
                MushafBundle(
                    serverID: remote.id,
                    title: remote.title,
                    description: remote.description,
                    pageNumbers: remote.pageNumbers,
                    mushafID: remote.mushafID,
                    isShared: true
                ),
                at: 0
            )
        }
        save()
    }

    func setCollaborator(userID: UUID, name: String?, for bundleID: UUID) {
        guard let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return }
        bundles[index].collaboratorUserID = userID
        bundles[index].collaboratorName = name
        save()
    }
}
