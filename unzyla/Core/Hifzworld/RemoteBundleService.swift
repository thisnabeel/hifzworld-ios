import Foundation

@MainActor
struct RemoteBundleService {
    private let api = HifzworldAPIClient.shared

    func sync(into store: BundleStore, mushafID: Int) async throws {
        try await pushDirtyBundles(from: store, mushafID: mushafID)
        try await uploadLocalBundles(from: store, mushafID: mushafID)
        let response: BundleMineResponse = try await api.get("/api/bundles/mine")
        store.mergeRemoteBundles(owned: response.owned, shared: response.shared, defaultMushafID: mushafID)
    }

    func uploadLocalBundles(from store: BundleStore, mushafID: Int) async throws {
        for bundle in store.bundles where bundle.serverID == nil {
            let body = CreateBundleBody(
                title: bundle.title,
                description: bundle.description,
                pageNumbers: bundle.pageNumbers,
                mushafID: mushafID
            )
            let remote: RemoteMushafBundle = try await api.post("/api/bundles", body: body)
            store.attachServerID(remote.id, to: bundle.id)
        }
    }

    func pushDirtyBundles(from store: BundleStore, mushafID: Int) async throws {
        for bundle in store.bundles {
            guard let serverID = bundle.serverID, !bundle.isShared else { continue }
            let body = UpdateBundleBody(
                title: bundle.title,
                description: bundle.description,
                pageNumbers: bundle.pageNumbers,
                mushafID: mushafID
            )
            let _: RemoteMushafBundle = try await api.patch(
                "/api/bundles/\(serverID.uuidString.lowercased())",
                body: body
            )
        }
    }

    func updateBundle(_ bundle: MushafBundle, mushafID: Int) async throws {
        guard let serverID = bundle.serverID, !bundle.isShared else { return }
        let body = UpdateBundleBody(
            title: bundle.title,
            description: bundle.description,
            pageNumbers: bundle.pageNumbers,
            mushafID: mushafID
        )
        let _: RemoteMushafBundle = try await api.patch(
            "/api/bundles/\(serverID.uuidString.lowercased())",
            body: body
        )
    }

    func deleteBundle(serverID: UUID) async throws {
        try await api.delete("/api/bundles/\(serverID.uuidString.lowercased())")
    }

    func share(bundleServerID: UUID, email: String?) async throws -> BundleShareDTO {
        let body = ShareBundleBody(email: email, handle: nil)
        return try await api.post("/api/bundles/\(bundleServerID.uuidString.lowercased())/share", body: body)
    }

    func pendingShares() async throws -> [BundleShareDTO] {
        try await api.get("/api/bundle_shares")
    }

    func acceptShare(id: UUID) async throws -> BundleShareDTO {
        try await api.post("/api/bundle_shares/\(id.uuidString.lowercased())/accept")
    }
}

private struct CreateBundleBody: Encodable {
    let title: String
    let description: String
    let pageNumbers: [Int]
    let mushafID: Int

    enum CodingKeys: String, CodingKey {
        case title, description
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
    }
}

private struct UpdateBundleBody: Encodable {
    let title: String
    let description: String
    let pageNumbers: [Int]
    let mushafID: Int

    enum CodingKeys: String, CodingKey {
        case title, description
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
    }
}

private struct ShareBundleBody: Encodable {
    let email: String?
    let handle: String?
}
