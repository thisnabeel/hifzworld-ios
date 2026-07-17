import SwiftUI

struct ReviewSessionBanner: View {
    let partnerName: String
    let role: ReviewSessionContext.Role
    let isMarkingMode: Bool
    let activeMarkType: MistakeMarkType
    let pageHidden: Bool
    let onToggleMarking: () -> Void
    let onSelectMarkType: (MistakeMarkType) -> Void
    let onTogglePageHidden: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    Button(pageHidden ? "Show page" : "Hide page") {
                        onTogglePageHidden()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("End", role: .destructive, action: onEnd)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("Talk on FaceTime/Zoom — this app syncs the Mushaf page.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if role == .listener {
                Text(isMarkingMode ? "Mark: \(activeMarkType.title)" : "Tap highlighter to mark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if pageHidden {
                Text("Page hidden by listener")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}
