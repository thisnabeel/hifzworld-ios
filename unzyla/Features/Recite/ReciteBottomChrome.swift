import SwiftUI

struct ReciteBottomChrome: View {
    let isPaintMode: Bool
    var isMarkingMode = false
    var isReviewListener = false
    var pageHidden = false
    var isCompactLandscape = false
    var isDarkMode = false
    /// When false, paint swatches/options are hidden (landscape may still show tabs + brush entry).
    var showsPaintTools = true
    /// When false, hide the paintbrush but keep yellow / black / invert viewing tools.
    var allowsPainting = true
    var selectedTab: Binding<Int>?
    var activeMarkType: MistakeMarkType = .tajweed
    var onToggleMarkingMode: (() -> Void)?
    var onSelectMarkType: ((MistakeMarkType) -> Void)?
    var onTogglePageHidden: (() -> Void)?
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

    private var toolSize: CGFloat { isCompactLandscape ? 30 : 44 }
    private var barPaddingV: CGFloat { isCompactLandscape ? 6 : 10 }
    private var barPaddingH: CGFloat { isCompactLandscape ? 12 : 16 }
    private var toolSpacing: CGFloat { isCompactLandscape ? 6 : 10 }
    private var corner: CGFloat { isCompactLandscape ? 8 : 10 }

    private var barBackground: Color {
        if isCompactLandscape {
            return isDarkMode
                ? Color(red: 0.14, green: 0.14, blue: 0.15)
                : Color(red: 0.97, green: 0.97, blue: 0.98)
        }
        return isDarkMode ? AppTheme.mushafDarkBackground : .white
    }

    private var hairline: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var idleToolFill: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white
    }

    private var idleToolStroke: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14)
    }

    private var idleToolForeground: Color {
        isDarkMode ? Color.white.opacity(0.92) : .black
    }

    private var primaryText: Color {
        isDarkMode ? .white : .black
    }

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
        .background(barBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(hairline)
                .frame(height: 1 / UIScreen.main.scale)
        }
    }

    private var paintToolbar: some View {
        HStack(spacing: toolSpacing) {
            if showsPaintTools {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: toolSpacing) {
                        if allowsPainting {
                            toolButton(
                                systemName: "paintbrush.fill",
                                isActive: isPaintMode,
                                activeBackground: isDarkMode ? Color.white : .black,
                                activeForeground: isDarkMode ? .black : .white,
                                action: onTogglePaintMode
                            )
                        }

                        if hasPaintedWords {
                            toolButton(
                                systemName: arePaintedWordsVisible ? "eye.fill" : "eye.slash.fill",
                                isActive: !arePaintedWordsVisible,
                                activeBackground: Color(red: 0.35, green: 0.35, blue: 0.38),
                                activeForeground: .white,
                                action: onTogglePaintedWordsVisible
                            )

                            colorCircleButton(
                                color: isDarkMode ? .white : .black,
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
                }
            } else if isCompactLandscape {
                if allowsPainting {
                    toolButton(
                        systemName: "paintbrush.fill",
                        isActive: false,
                        activeBackground: isDarkMode ? Color.white : .black,
                        activeForeground: isDarkMode ? .black : .white,
                        action: onTogglePaintMode
                    )
                }
                Spacer(minLength: 0)
            }

            if isCompactLandscape, selectedTab != nil {
                landscapeTabCluster
            }
        }
        .padding(.horizontal, barPaddingH)
        .padding(.vertical, barPaddingV)
    }

    private var landscapeTabCluster: some View {
        HStack(spacing: 2) {
            landscapeTabButton(title: "Mushaf", systemImage: "book.fill", tag: 0)
            landscapeTabButton(title: "Decks", systemImage: "square.stack.3d.up", tag: 1)
            landscapeTabButton(title: "Feedback", systemImage: "text.badge.checkmark", tag: 2)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func landscapeTabButton(title: String, systemImage: String, tag: Int) -> some View {
        let isSelected = selectedTab?.wrappedValue == tag
        return Button {
            selectedTab?.wrappedValue = tag
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? Color(red: 0.2, green: 0.45, blue: 0.95)
                        : (isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.45))
                )
                .frame(width: 34, height: 26)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? (isDarkMode ? Color.white.opacity(0.95) : Color.white)
                                : Color.clear
                        )
                )
                .shadow(color: isSelected ? .black.opacity(isDarkMode ? 0.35 : 0.08) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func verseRefPanel(detail: SelectedVerseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onDismissVerseRef) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isCompactLandscape ? 15 : 18, weight: .semibold))
                        .foregroundStyle(idleToolForeground)
                        .frame(width: toolSize, height: toolSize)
                        .background(idleToolFill)
                        .clipShape(RoundedRectangle(cornerRadius: corner))
                        .overlay(
                            RoundedRectangle(cornerRadius: corner)
                                .stroke(idleToolStroke, lineWidth: 1.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: corner))
                }
                .buttonStyle(.plain)

                Text(detail.displayRef)
                    .font(.system(size: isCompactLandscape ? 15 : 17, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()

                Spacer(minLength: 0)

                if isCompactLandscape, selectedTab != nil {
                    landscapeTabCluster
                }
            }

            Group {
                if detail.isLoadingTranslation {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(primaryText)
                        Text("Loading translation…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let translation = detail.translation {
                    VerseTranslationBlock(translation: translation, isDarkMode: isDarkMode)
                        .id(detail.verseKey)
                } else if let error = detail.translationError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, isCompactLandscape ? 0 : 56)
        }
        .padding(.horizontal, barPaddingH)
        .padding(.vertical, barPaddingV)
    }

    private func toolButton(
        systemName: String,
        isActive: Bool,
        activeBackground: Color,
        activeForeground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isCompactLandscape ? 14 : 18, weight: .medium))
                .foregroundStyle(isActive ? activeForeground : idleToolForeground)
                .frame(width: toolSize, height: toolSize)
                .background(isActive ? activeBackground : idleToolFill)
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(isActive ? Color.clear : idleToolStroke, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: corner))
        }
        .buttonStyle(.plain)
    }

    private func invertButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("invert")
                .font(.system(size: isCompactLandscape ? 11 : 14, weight: .semibold))
                .foregroundStyle(isPaintInverted ? .white : idleToolForeground)
                .padding(.horizontal, isCompactLandscape ? 8 : 12)
                .frame(height: toolSize)
                .background(
                    isPaintInverted
                        ? Color(red: 0.2, green: 0.45, blue: 0.95)
                        : idleToolFill
                )
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(isPaintInverted ? Color.clear : idleToolStroke, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: corner))
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
                .frame(width: isCompactLandscape ? 16 : 28, height: isCompactLandscape ? 16 : 28)
                .padding(isCompactLandscape ? 7 : 8)
                .background(idleToolFill)
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(
                            isActive ? Color(red: 0.2, green: 0.45, blue: 0.95) : idleToolStroke,
                            lineWidth: isActive ? 2 : 1.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: corner))
        }
        .buttonStyle(.plain)
    }

    private var reviewMarkingToolbar: some View {
        HStack(spacing: toolSpacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: toolSpacing) {
                    toolButton(
                        systemName: "highlighter",
                        isActive: isMarkingMode,
                        activeBackground: Color(red: 1, green: 0.45, blue: 0.42),
                        action: { onToggleMarkingMode?() }
                    )

                    toolButton(
                        systemName: pageHidden ? "eye.slash.fill" : "eye.fill",
                        isActive: pageHidden,
                        activeBackground: Color(red: 0.35, green: 0.35, blue: 0.38),
                        action: { onTogglePageHidden?() }
                    )

                    if isMarkingMode {
                        ForEach(MistakeMarkType.allCases) { type in
                            Button {
                                onSelectMarkType?(type)
                            } label: {
                                Text(type.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        activeMarkType == type
                                            ? .white
                                            : idleToolForeground
                                    )
                                    .padding(.horizontal, isCompactLandscape ? 8 : 10)
                                    .padding(.vertical, isCompactLandscape ? 6 : 8)
                                    .background(
                                        activeMarkType == type
                                            ? Color(red: 1, green: 0.45, blue: 0.42)
                                            : (isDarkMode ? Color.white.opacity(0.10) : Color(.tertiarySystemFill))
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if isCompactLandscape, selectedTab != nil {
                landscapeTabCluster
            }
        }
        .padding(.horizontal, barPaddingH)
        .padding(.vertical, barPaddingV)
    }
}

private struct VerseTranslationBlock: View {
    let translation: String
    var isDarkMode = false
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

    private var textColor: Color {
        isDarkMode ? .white : .black
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if !exceedsSixLines {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if isExpanded {
                    if fullHeight <= maxExpandedHeight {
                        Text(translation)
                            .font(.subheadline)
                            .foregroundStyle(textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        ScrollView {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .frame(maxHeight: maxExpandedHeight)
                    }
                } else {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(textColor)
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
