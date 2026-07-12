import SwiftUI

struct ReviewSessionBanner: View {
    let partnerName: String
    let role: ReviewSessionContext.Role
    let isMarkingMode: Bool
    let activeMarkType: MistakeMarkType
    let onToggleMarking: () -> Void
    let onSelectMarkType: (MistakeMarkType) -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(role == .listener ? "Reviewing" : "Reciting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(partnerName)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            if role == .listener {
                Text(isMarkingMode ? "Mark: \(activeMarkType.title)" : "Tap highlighter to mark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("End", role: .destructive, action: onEnd)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}
