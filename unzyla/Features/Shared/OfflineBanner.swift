import SwiftUI

struct OfflineBanner: View {
    let isConnected: Bool

    var body: some View {
        if !isConnected {
            Text("You're offline. Cached pages stay readable. Marks save on this device and sync when you're back online.")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.orange)
        }
    }
}
