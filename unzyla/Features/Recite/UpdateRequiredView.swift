import SwiftUI

struct UpdateRequiredView: View {
    let installed: String
    let required: String
    let appStoreId: String?

    /// Fallback when API omits `app_store_id`.
    private static var fallbackAppStoreID: String { HifzworldAPIConfig.appStoreID }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("AppIconDisplay")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .accessibilityHidden(true)

            Text("Update Required")
                .font(.title.bold())

            Text("A newer version of Hifz.World is required to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Text("Installed \(installed) · Required \(required)")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Button {
                openAppStore()
            } label: {
                Text("Update on the App Store")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .accessibilityHint("Opens Hifz.World in the App Store")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    private var resolvedAppStoreID: String {
        let trimmed = appStoreId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.fallbackAppStoreID : trimmed
    }

    private var appStoreURL: URL {
        URL(string: "https://apps.apple.com/us/app/hifz-world/id\(resolvedAppStoreID)")!
    }

    private func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }
}
