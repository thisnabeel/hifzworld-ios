import SwiftUI

struct UpdateRequiredView: View {
    let installed: String
    let required: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)
            Text("Update Required")
                .font(.title.bold())
            Text("Installed: \(installed)\nRequired: \(required)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Please update unzyla from the App Store to continue.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
