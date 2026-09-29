import SwiftUI

/// Blue strip used while marking / browsing another user’s Mushaf, decks, or feedback.
struct ViewingAsBanner: View {
    let label: String
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Marking for \(label)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Exit", action: onExit)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.18, green: 0.32, blue: 0.55))
    }
}
