import SwiftUI

struct ReciteBottomChrome: View {
    let isPaintMode: Bool
    var isMarkingMode = false
    var isReviewListener = false
    var activeMarkType: MistakeMarkType = .tajweed
    var onToggleMarkingMode: (() -> Void)?
    var onSelectMarkType: ((MistakeMarkType) -> Void)?
    let selectedVerse: SelectedVerseDetail?
    let activePaintStyle: WordPaintStyle
    let arePaintedWordsVisible: Bool
    let isPaintInverted: Bool
    let hasPaintedWords: Bool
    let onTogglePaintMode: () -> Void
    let onTogglePaintedWordsVisible: () -> Void
    let onSelectPaintStyle: (WordPaintStyle) -> Void
    let onTogglePaintInverted: () -> Void
    let onDismissVerseRef: () -> Void

    var body: some View {
        Group {
            if !isPaintMode, let selectedVerse {
                verseRefPanel(detail: selectedVerse)
            } else if isReviewListener {
                reviewMarkingToolbar
            } else {
                paintToolbar
            }
        }
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1 / UIScreen.main.scale)
        }
    }

    private var paintToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolButton(
                    systemName: "paintbrush.fill",
                    isActive: isPaintMode,
                    activeBackground: .black,
                    action: onTogglePaintMode
                )

                if hasPaintedWords {
                    toolButton(
                        systemName: arePaintedWordsVisible ? "eye.fill" : "eye.slash.fill",
                        isActive: !arePaintedWordsVisible,
                        activeBackground: Color(red: 0.35, green: 0.35, blue: 0.38),
                        action: onTogglePaintedWordsVisible
                    )

                    colorCircleButton(
                        color: .black,
                        isActive: activePaintStyle == .blackout,
                        action: { onSelectPaintStyle(.blackout) }
                    )

                    colorCircleButton(
                        color: Color(red: 1, green: 0.92, blue: 0.23),
                        isActive: activePaintStyle == .highlight,
                        action: { onSelectPaintStyle(.highlight) }
                    )

                    invertButton(action: onTogglePaintInverted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func verseRefPanel(detail: SelectedVerseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onDismissVerseRef) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.15), lineWidth: 1.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Text(detail.displayRef)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .monospacedDigit()

                Spacer(minLength: 0)
            }

            Group {
                if detail.isLoadingTranslation {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading translation…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let translation = detail.translation {
                    VerseTranslationBlock(translation: translation)
                        .id(detail.verseKey)
                } else if let error = detail.translationError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 56)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toolButton(
        systemName: String,
        isActive: Bool,
        activeBackground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? .white : .black)
                .frame(width: 44, height: 44)
                .background(isActive ? activeBackground : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(isActive ? 0 : 0.15), lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func invertButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("invert")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isPaintInverted ? .white : .black)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(isPaintInverted ? Color(red: 0.2, green: 0.45, blue: 0.95) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(isPaintInverted ? 0 : 0.15), lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func colorCircleButton(
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .padding(8)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color(red: 0.2, green: 0.45, blue: 0.95) : Color.black.opacity(0.15), lineWidth: isActive ? 3 : 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var reviewMarkingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolButton(
                    systemName: "highlighter",
                    isActive: isMarkingMode,
                    activeBackground: Color(red: 1, green: 0.45, blue: 0.42),
                    action: { onToggleMarkingMode?() }
                )

                if isMarkingMode {
                    ForEach(MistakeMarkType.allCases) { type in
                        Button {
                            onSelectMarkType?(type)
                        } label: {
                            Text(type.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(activeMarkType == type ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(activeMarkType == type ? Color(red: 1, green: 0.45, blue: 0.42) : Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct VerseTranslationBlock: View {
    let translation: String
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var sixLineHeight: CGFloat = 0

    private let maxLineCount = 6
    private let collapsedLineCount = 2
    private let maxExpandedHeight: CGFloat = 176

    private var exceedsSixLines: Bool {
        guard fullHeight > 0, sixLineHeight > 0 else { return false }
        return fullHeight > sixLineHeight + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if !exceedsSixLines {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if isExpanded {
                    if fullHeight <= maxExpandedHeight {
                        Text(translation)
                            .font(.subheadline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        ScrollView {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .frame(maxHeight: maxExpandedHeight)
                    }
                } else {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.black)
                        .lineLimit(collapsedLineCount)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
            .animation(.easeInOut(duration: 0.22), value: exceedsSixLines)

            if exceedsSixLines {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Read full translation")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.45, blue: 0.95))
                }
                .buttonStyle(.plain)
            }
        }
        .background(lineMeasurer)
        .onChange(of: translation) { _, _ in
            isExpanded = false
            fullHeight = 0
            sixLineHeight = 0
        }
    }

    private var lineMeasurer: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Text(translation)
                    .font(.subheadline)
                    .lineLimit(maxLineCount)
                    .frame(width: geo.size.width, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TranslationSixLineHeightKey.self, value: proxy.size.height)
                        }
                    )

                Text(translation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geo.size.width, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TranslationFullHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .hidden()
        }
        .frame(height: 0)
        .allowsHitTesting(false)
        .onPreferenceChange(TranslationSixLineHeightKey.self) { height in
            sixLineHeight = height
            if !exceedsSixLines { isExpanded = false }
        }
        .onPreferenceChange(TranslationFullHeightKey.self) { height in
            fullHeight = height
            if !exceedsSixLines { isExpanded = false }
        }
    }
}

private struct TranslationSixLineHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TranslationFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
