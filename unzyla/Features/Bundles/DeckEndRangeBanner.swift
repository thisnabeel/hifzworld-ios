import SwiftUI

struct DeckEndRangeBanner: View {
    let startPage: Int
    let currentPage: Int
    let surahTitle: String?
    let onCancel: () -> Void
    let onDone: () -> Void

    private var low: Int { min(startPage, currentPage) }
    private var high: Int { max(startPage, currentPage) }
    private var pageCount: Int { high - low + 1 }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(surahTitle.map { "Deck range · \($0)" } ?? "Deck range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("p. \(PrintedPage.display(low))–\(PrintedPage.display(high)) · \(pageCount) page\(pageCount == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 0)

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
