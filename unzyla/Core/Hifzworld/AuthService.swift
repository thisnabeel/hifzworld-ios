import UIKit
import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthService: NSObject {
    static let shared = AuthService()

    private(set) var currentUser: HifzworldUser?
    private(set) var isSigningIn = false
    var lastError: String?

    private let api = HifzworldAPIClient.shared
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    var isSignedIn: Bool { currentUser != nil && KeychainTokenStore.load() != nil }

    private override init() {
        super.init()
    }

    func bootstrap() async {
        guard KeychainTokenStore.load() != nil else { return }
        do {
            currentUser = try await api.get("/api/users/me")
        } catch {
            KeychainTokenStore.clear()
            currentUser = nil
        }
    }

    func signOut() {
        KeychainTokenStore.clear()
        currentUser = nil
    }

    /// Permanently deletes the server account and clears local auth state.
    func deleteAccount() async throws {
        try await api.delete("/api/users/me")
        KeychainTokenStore.clear()
        currentUser = nil
        lastError = nil
    }

    func updateHandle(_ handle: String) async throws {
        let body = UpdateUserBody(handle: handle, displayName: nil)
        currentUser = try await api.patch("/api/users/me", body: body)
    }

    func signInWithApple() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let authorization = try await requestAppleAuthorization()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                lastError = "Apple sign in failed"
                return
            }

            let displayName = [
                credential.fullName?.givenName,
                credential.fullName?.familyName
            ].compactMap { $0 }.joined(separator: " ")

            let body = AppleSignInBody(
                identityToken: identityToken,
                displayName: displayName.isEmpty ? nil : displayName
            )
            let response: AuthResponse = try await api.post("/api/auth/apple", body: body, authorized: false)
            KeychainTokenStore.save(response.token)
            currentUser = response.user
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func requestAppleAuthorization() async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

private struct AppleSignInBody: Encodable {
    let identityToken: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case displayName = "display_name"
    }
}

private struct UpdateUserBody: Encodable {
    let handle: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            let window = windowScene?.windows.first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
        }
    }
}
