import SwiftUI

struct BundleMushafSegmentBar: View {
    let session: BundleMushafSession
    let onSelect: (Int) -> Void
    let onExit: () -> Void
    var showsExit: Bool = true

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
                                ForEach(Array(group.pages.enumerated()), id: \.element) { offset, page in
                                    let flatIndex = group.startIndex + offset
                                    pageChip(
                                        page: page,
                                        flatIndex: flatIndex,
                                        surahTitle: group.surahTitle,
                                        isGroupLead: offset == 0
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 6)
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
        .frame(height: 44)
        .background(Color(.secondarySystemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.title) deck navigation")
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
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

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(flatIndex)
        } label: {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color.orange : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(flatIndex)
        .accessibilityLabel(showsSurah ? "Page \(page), \(surahTitle)" : "Page \(page)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
