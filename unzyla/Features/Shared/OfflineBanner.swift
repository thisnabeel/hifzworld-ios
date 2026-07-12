import SwiftUI

struct OfflineBanner: View {
    let isConnected: Bool

    var body: some View {
        if !isConnected {
            Text("You're offline. Some features may not work.")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.orange)
        }
    }
}
