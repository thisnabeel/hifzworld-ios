import SwiftUI

struct MushafTopBar: View {
    let currentPage: Int
    var pageLabel: String?
    let selectedNarratorIDs: [String]
    let parentNarrators: [ParentNarrator]
    var showsCoachPicker = false
    var coachLabel: String?
    var unreadMailCount = 0
    var isCurrentPageBookmarked = false
    let onMenu: () -> Void
    var onCoachPick: (() -> Void)?
    var onCoachMail: (() -> Void)?
    var onInbox: (() -> Void)?
    var onExitCoach: (() -> Void)?
    let onSearch: () -> Void
    let onAddToBundle: () -> Void
    var onToggleBookmark: (() -> Void)?
    /// Juz containing the current page; shows the "Juz N" button when set.
    var juz: NavigationSegment?
    /// Every juz of the mushaf, for switching juz from the popover.
    var allJuz: [NavigationSegment] = []
    /// Printed quarter start pages of `juz`; the popover splits the juz evenly when nil.
    var juzQuarterStartPages: [Int]?
    var mushafID: Int = PreferencesStore.shared.mushafID
    var onGoToPage: ((Int) -> Void)?
    /// iPad: the app's tab switcher sits in this row (centered) instead of the system tab bar's own row.
    var selectedTab: Binding<Int>?

    @State private var showsJuzPopover = false

    private var displayedPageLabel: String {
        pageLabel ?? "\(PrintedPage.display(currentPage))"
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)

                if showsCoachPicker {
                    Button {
                        onCoachPick?()
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark for friend")
                    .padding(.trailing, 4)

                    if unreadMailCount > 0 {
                        Button {
                            onInbox?()
                        } label: {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .overlay(alignment: .topTrailing) {
                                    unreadBadge(unreadMailCount)
                                        .offset(x: 6, y: -4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inbox, \(unreadMailCount) unread")
                        .padding(.trailing, 4)
                    }

                    if coachLabel != nil {
                        Button {
                            onCoachMail?()
                        } label: {
                            Image(systemName: "envelope")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send mail to friend")
                        .padding(.trailing, 4)
                    }
                }

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
                    if let juz, let number = juz.categoryPosition {
                        Button {
                            showsJuzPopover = true
                        } label: {
                            Text("Juz \(number)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Juz \(number), pages in this juz")
                        .popover(isPresented: $showsJuzPopover, arrowEdge: .top) {
                            JuzRangePopover(
                                juz: juz,
                                allJuz: allJuz,
                                currentPage: currentPage,
                                mushafID: mushafID,
                                printedQuarterStartPages: juzQuarterStartPages,
                                onGoToPage: { onGoToPage?($0) }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    }

                    Text("Pg. \(displayedPageLabel)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)

                    Button {
                        onToggleBookmark?()
                    } label: {
                        Image(systemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isCurrentPageBookmarked ? AppTheme.accent : .white)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrentPageBookmarked ? "Remove bookmark" : "Bookmark page")

                    Button(action: onAddToBundle) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to Deck")

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
            .overlay {
                if let selectedTab {
                    InlineTabSwitcher(selection: selectedTab)
                }
            }

            if let coachLabel {
                ViewingAsBanner(label: coachLabel, onExit: { onExitCoach?() })
            }
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.accent)
                .frame(height: 2)
        }
    }

    private func unreadBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 4 : 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
            .accessibilityHidden(true)
    }
}

/// Mushaf / Decks / Marks / Journal pill, styled like the iPad floating tab bar, for the top bar row.
private struct InlineTabSwitcher: View {
    @Binding var selection: Int

    private static let tabs: [(title: String, tag: Int)] = [
        ("Mushaf", 0), ("Decks", 1), ("Marks", 2), ("Journal", 3)
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.tabs, id: \.tag) { tab in
                let isSelected = selection == tab.tag
                Button {
                    selection = tab.tag
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.accent : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white.opacity(0.14))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}
