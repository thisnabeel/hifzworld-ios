import SwiftUI

struct BundleMushafSegmentBar: View {
    let session: BundleMushafSession
    let onSelect: (Int) -> Void
    let onExit: () -> Void
    var showsExit: Bool = true
    /// When false, hide extend/delete affordances (review / recording).
    var allowsEditing: Bool = true
    var totalPages: Int = 604
    var onExtendBefore: ((Int) -> Void)? = nil
    var onExtendAfter: ((Int) -> Void)? = nil
    var onRequestDelete: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(session.groups.enumerated()), id: \.element.id) { groupIndex, group in
                            if groupIndex > 0 {
                                segmentDivider
                            }

                            HStack(spacing: 6) {
                                if allowsEditing, let first = group.pages.first, canExtendBefore(first) {
                                    extendChip(accessibilityPage: first - 1) {
                                        onExtendBefore?(first)
                                    }
                                }

                                ForEach(Array(group.pages.enumerated()), id: \.element) { offset, page in
                                    let flatIndex = group.startIndex + offset
                                    pageChip(
                                        page: page,
                                        flatIndex: flatIndex,
                                        surahTitle: group.surahTitle,
                                        isGroupLead: offset == 0
                                    )
                                }

                                if allowsEditing, let last = group.pages.last, canExtendAfter(last) {
                                    extendChip(accessibilityPage: last + 1) {
                                        onExtendAfter?(last)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 4)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .onAppear {
                    scrollToActive(in: proxy, animated: false)
                }
                .onChange(of: session.currentIndex) { _, _ in
                    scrollToActive(in: proxy, animated: true)
                }
                .onChange(of: session.groups.map(\.id)) { _, _ in
                    scrollToActive(in: proxy, animated: true)
                }
                .onChange(of: session.pages) { _, _ in
                    scrollToActive(in: proxy, animated: true)
                }
            }

            if showsExit {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 24)

                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Exit deck mode")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(height: 36)
        .background(.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.title) deck navigation")
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func canExtendBefore(_ firstPage: Int) -> Bool {
        firstPage > 1 && !session.pages.contains(firstPage - 1)
    }

    private func canExtendAfter(_ lastPage: Int) -> Bool {
        lastPage < totalPages && !session.pages.contains(lastPage + 1)
    }

    private func extendChip(accessibilityPage: Int, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill).opacity(0.55))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add page \(accessibilityPage) to deck")
    }

    private func pageChip(
        page: Int,
        flatIndex: Int,
        surahTitle: String,
        isGroupLead: Bool
    ) -> some View {
        let isActive = flatIndex == session.currentIndex
        let showsSurah = isActive || isGroupLead
        let label = showsSurah ? "\(page) \(surahTitle)" : "\(page)"

        return Text(label)
            .font(.caption.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.orange : Color(.tertiarySystemFill))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelect(flatIndex)
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard allowsEditing, onRequestDelete != nil else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRequestDelete?(page)
            }
            .id(flatIndex)
            .accessibilityLabel(showsSurah ? "Page \(page), \(surahTitle)" : "Page \(page)")
            .accessibilityHint(allowsEditing ? "Long press to remove from deck" : "")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAction {
                onSelect(flatIndex)
            }
    }

    private func scrollToActive(in proxy: ScrollViewProxy, animated: Bool) {
        guard session.pages.indices.contains(session.currentIndex) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(session.currentIndex, anchor: .center)
            }
        } else {
            proxy.scrollTo(session.currentIndex, anchor: .center)
        }
    }
}
