import Foundation
import Observation

struct DeckInviteDTO: Codable {
    let token: String
    let url: String
    let deepLink: String?
    let bundleTitle: String?

    enum CodingKeys: String, CodingKey {
        case token, url
        case deepLink = "deep_link"
        case bundleTitle = "bundle_title"
    }
}

@MainActor
@Observable
final class DeckInviteHandler {
    static let shared = DeckInviteHandler()

    private(set) var pendingToken: String?
    var statusMessage: String?
    var errorMessage: String?

    private let pendingKey = "pending_deck_invite_token"
    private let api = HifzworldAPIClient.shared

    private init() {
        pendingToken = UserDefaults.standard.string(forKey: pendingKey)
    }

    func handle(url: URL) {
        guard let token = inviteToken(from: url) else { return }
        pendingToken = token
        UserDefaults.standard.set(token, forKey: pendingKey)
        statusMessage = nil
        errorMessage = nil
    }

    func claimIfNeeded(
        auth: AuthService,
        bundleStore: BundleStore,
        mushafID: Int,
        onClaimed: (() -> Void)? = nil
    ) async {
        guard let token = pendingToken else { return }
        guard auth.isSignedIn else { return }

        do {
            let share: BundleShareDTO = try await api.post("/api/invites/\(token)/claim")
            clearPending()
            try await RemoteBundleService().sync(into: bundleStore, mushafID: mushafID)
            let title = share.bundle?.title ?? "deck"
            statusMessage = "Joined “\(title)”."
            onClaimed?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearPending() {
        pendingToken = nil
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private func inviteToken(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        if scheme == "hifzworld" {
            // hifzworld://invite/TOKEN
            guard url.host?.lowercased() == "invite" else { return nil }
            let token = url.pathComponents.dropFirst().first ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return token.isEmpty ? nil : token
        }

        // https://host/i/TOKEN
        if scheme == "https" || scheme == "http" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2, parts[0] == "i" else { return nil }
            return parts[1]
        }

        return nil
    }
}
