import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Bindable var auth: AuthService

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Sign in to share bundles and review recitation")
                .font(.headline)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in
                Task { await auth.signInWithApple() }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)

            Button("Sign in with Apple") {
                Task { await auth.signInWithApple() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isSigningIn)

            if auth.isSigningIn {
                ProgressView()
            }

            if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
