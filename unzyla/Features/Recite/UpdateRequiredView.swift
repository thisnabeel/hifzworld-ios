import SwiftUI

struct UpdateRequiredView: View {
    let installed: String
    let required: String
    let appStoreId: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)

            Text("Update Required")
                .font(.title.bold())

            Text("A newer version of Hifzworld is required to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Text("Installed \(installed) · Required \(required)")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            if let url = appStoreURL {
                Link(destination: url) {
                    Text("Update")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    private var appStoreURL: URL? {
        guard let appStoreId, !appStoreId.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreId)")
    }
}
