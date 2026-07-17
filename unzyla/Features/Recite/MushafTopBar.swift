import SwiftUI

struct MushafTopBar: View {
    let currentPage: Int
    var pageLabel: String?
    let selectedNarratorIDs: [String]
    let parentNarrators: [ParentNarrator]
    let onMenu: () -> Void
    let onSearch: () -> Void
    let onAddToBundle: () -> Void

    private var displayedPageLabel: String {
        pageLabel ?? "\(currentPage)"
    }

    private var narratorPills: [NarratorChild] {
        selectedNarratorIDs
            .filter { $0 != NarratorCatalog.hafsID }
            .compactMap { id in
                for parent in parentNarrators {
                    if let child = parent.children.first(where: { $0.id == id }) {
                        return child
                    }
                }
                return nil
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(narratorPills) { narrator in
                        Button(action: onMenu) {
                            Text(narrator.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: narrator.highlightColor) ?? AppTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: narrator.highlightColor) ?? AppTheme.accent, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 12)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)

            HStack(spacing: 6) {
                Text("Pg. \(displayedPageLabel)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Button(action: onAddToBundle) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.accent)
                .frame(height: 2)
        }
    }
}
