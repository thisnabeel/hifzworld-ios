import SwiftUI

struct ReciteBottomChrome: View {
    let isPaintMode: Bool
    var isMarkingMode = false
    var isReviewListener = false
    /// Friend Mushaf coach mode — same mark tools as listener, without page-hide.
    var isCoachMarking = false
    /// Own Mushaf marking — show hide/invert for persisted marks.
    var showsOwnMarkViewTools = false
    var areSessionMarksVisible = true
    var isSessionMarksInverted = false
    var hasSessionMarks = false
    var onToggleSessionMarksVisible: (() -> Void)?
    var onToggleSessionMarksInverted: (() -> Void)?
    var pageHidden = false
    var isCompactLandscape = false
    var isDarkMode = false
    var translationLanguage: TranslationLanguage = .english
    /// When false, paint swatches/options are hidden (landscape may still show tabs + brush entry).
    var showsPaintTools = true
    /// When false, hide the paintbrush but keep yellow / black / invert viewing tools.
    var allowsPainting = true
    var isAyahPromptMode = false
    var ayahPromptCueCount = 2
    var isJournalRecording = false
    var journalRecordingElapsed: TimeInterval = 0
    var onToggleAyahPromptMode: (() -> Void)?
    var onToggleJournalRecording: (() -> Void)?
    var onSelectAyahPromptCueCount: ((Int) -> Void)?
    var selectedTab: Binding<Int>?
    var activeMarkType: MistakeMarkType = .mistake
    var orderedMarkTypes: [MistakeMarkType] = Array(MistakeMarkType.allCases)
    var showsMarkTypePills = false
    var markTypeColors: [MistakeMarkType: Color] = [:]
    var onToggleMarkingMode: (() -> Void)?
    var onSelectMarkType: ((MistakeMarkType) -> Void)?
    var isFireMode = false
    var onToggleFireMode: (() -> Void)?
    var onTogglePageHidden: (() -> Void)?
    let selectedVerse: SelectedVerseDetail?
    let activePaintStyle: WordPaintStyle
    let arePaintedWordsVisible: Bool
    let isPaintInverted: Bool
    let hasPaintedWords: Bool
    let onTogglePaintMode: () -> Void
    let onTogglePaintedWordsVisible: () -> Void
    let onSelectPaintStyle: (WordPaintStyle) -> Void
    var onTogglePaintInverted: () -> Void
    var onDismissVerseRef: () -> Void
    var showsBlockPageNavigation = false
    var canGoToPreviousBlockPage = false
    var canGoToNextBlockPage = false
    var onGoToPreviousBlockPage: (() -> Void)?
    var onGoToNextBlockPage: (() -> Void)?

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

    private var showsBlockNavRow: Bool {
        !isPaintMode && !isAyahPromptMode && showsBlockPageNavigation && !isCompactLandscape
    }

    @ViewBuilder
    private var blockNavigationRow: some View {
        BlockPageNavigationButtons(
            canGoPrevious: canGoToPreviousBlockPage,
            canGoNext: canGoToNextBlockPage,
            size: toolSize,
            corner: corner,
            fill: idleToolFill,
            stroke: idleToolStroke,
            foreground: idleToolForeground,
            showsShadow: false,
            fillsWidth: true,
            onPrevious: { onGoToPreviousBlockPage?() },
            onNext: { onGoToNextBlockPage?() }
        )
        .padding(.horizontal, barPaddingH)
        .padding(.top, barPaddingV)
    }

    private var inlineBlockNavigation: some View {
        BlockPageNavigationButtons(
            canGoPrevious: canGoToPreviousBlockPage,
            canGoNext: canGoToNextBlockPage,
            size: toolSize,
            corner: corner,
            fill: idleToolFill,
            stroke: idleToolStroke,
            foreground: idleToolForeground,
            showsShadow: false,
            fillsWidth: false,
            onPrevious: { onGoToPreviousBlockPage?() },
            onNext: { onGoToNextBlockPage?() }
        )
    }

    var body: some View {
        Group {
            if isAyahPromptMode {
                ayahPromptToolbar
            } else if !isPaintMode, let selectedVerse {
                verseRefPanel(detail: selectedVerse)
            } else if isReviewListener || isCoachMarking {
                VStack(spacing: 0) {
                    if showsBlockNavRow { blockNavigationRow }
                    reviewMarkingToolbar
                }
            } else {
                VStack(spacing: 0) {
                    if showsBlockNavRow { blockNavigationRow }
                    paintToolbar
                }
            }
        }
        .background(barBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(hairline)
                .frame(height: 1 / UIScreen.main.scale)
        }
    }

    private var ayahPromptToolbar: some View {
        HStack(spacing: toolSpacing) {
            Spacer(minLength: 0)
            ayahPromptCueCountPicker
            mushafRecordButton
            ayahPromptButton
            if isCompactLandscape, selectedTab != nil {
                landscapeTabCluster
            }
        }
        .padding(.horizontal, barPaddingH)
        .padding(.vertical, barPaddingV)
    }

    private var ayahPromptCueCountPicker: some View {
        HStack(spacing: 0) {
            ForEach(0...2, id: \.self) { count in
                Button {
                    onSelectAyahPromptCueCount?(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: isCompactLandscape ? 12 : 14, weight: .semibold))
                        .foregroundStyle(
                            ayahPromptCueCount == count
                                ? (isDarkMode ? Color.black : Color.white)
                                : idleToolForeground
                        )
                        .frame(width: isCompactLandscape ? 28 : 34, height: toolSize)
                        .background(
                            ayahPromptCueCount == count
                                ? (isDarkMode ? Color.white : Color.black)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(count) cue \(count == 1 ? "word" : "words")")
            }
        }
        .background(idleToolFill)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(idleToolStroke, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cue words after verse")
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

                            invertButton(isActive: isPaintInverted, action: onTogglePaintInverted)
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

            Spacer(minLength: 0)
            if isCompactLandscape, showsBlockPageNavigation, !isPaintMode {
                inlineBlockNavigation
            }
            mushafRecordButton
            ayahPromptButton

            if isCompactLandscape, selectedTab != nil {
                landscapeTabCluster
            }
        }
        .padding(.horizontal, barPaddingH)
        .padding(.vertical, barPaddingV)
    }

    private var ayahPromptButton: some View {
        Button {
            onToggleAyahPromptMode?()
        } label: {
            Image("HoldingHands")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(isAyahPromptMode ? (isDarkMode ? Color.black : Color.white) : idleToolForeground)
                .frame(width: toolSize, height: toolSize)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(isAyahPromptMode ? (isDarkMode ? Color.white : Color.black) : idleToolFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(isAyahPromptMode ? Color.clear : idleToolStroke, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isJournalRecording)
        .accessibilityLabel(isAyahPromptMode ? "Exit ayah prompt mode" : "Ayah prompt mode")
    }

    private var mushafRecordButton: some View {
        Button {
            onToggleJournalRecording?()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: isCompactLandscape ? 14 : 18, weight: .semibold))
                .foregroundStyle(isJournalRecording ? Color.white : Color.red)
                .frame(width: toolSize, height: toolSize)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(isJournalRecording ? Color.red : idleToolFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(isJournalRecording ? Color.clear : idleToolStroke, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isJournalRecording ? "Stop recording" : "Record")
    }

    private var landscapeTabCluster: some View {
        HStack(spacing: 2) {
            landscapeTabButton(title: "Mushaf", systemImage: "book.fill", tag: 0)
            landscapeTabButton(title: "Decks", systemImage: "square.stack.3d.up", tag: 1)
            landscapeTabButton(title: "Marks", systemImage: "text.badge.checkmark", tag: 2)
            landscapeTabButton(title: "Journal", systemImage: "book.pages", tag: 3)
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
        VStack(alignment: .leading, spacing: isCompactLandscape ? 6 : 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(detail.displayRef)
                    .font(.system(size: isCompactLandscape ? 12 : 13, weight: .semibold))
                    .foregroundStyle(primaryText.opacity(0.55))
                    .monospacedDigit()
                    .tracking(0.4)

                Spacer(minLength: 0)

                if isCompactLandscape, selectedTab != nil {
                    landscapeTabCluster
                }

                Button(action: onDismissVerseRef) {
                    Image(systemName: "xmark")
                        .font(.system(size: isCompactLandscape ? 11 : 12, weight: .semibold))
                        .foregroundStyle(idleToolForeground.opacity(0.72))
                        .frame(width: isCompactLandscape ? 26 : 28, height: isCompactLandscape ? 26 : 28)
                        .background(idleToolFill)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(idleToolStroke.opacity(0.7), lineWidth: 1)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close translation")
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
                    VerseTranslationBlock(
                        translation: TranslationDisplayText.polished(
                            translation,
                            language: translationLanguage
                        ),
                        isDarkMode: isDarkMode,
                        isRightToLeft: translationLanguage.isRightToLeft
                    )
                    .id(detail.verseKey)
                } else if let error = detail.translationError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, isCompactLandscape ? 14 : 16)
        .padding(.top, isCompactLandscape ? 8 : 10)
        .padding(.bottom, isCompactLandscape ? 8 : 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(hairline)
                .frame(height: 1 / UIScreen.main.scale)
        }
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

    private func invertButton(isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("invert")
                .font(.system(size: isCompactLandscape ? 11 : 14, weight: .semibold))
                .foregroundStyle(isActive ? .white : idleToolForeground)
                .padding(.horizontal, isCompactLandscape ? 8 : 12)
                .frame(height: toolSize)
                .background(
                    isActive
                        ? Color(red: 0.2, green: 0.45, blue: 0.95)
                        : idleToolFill
                )
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(isActive ? Color.clear : idleToolStroke, lineWidth: 1.5)
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

    /// Fallback yellow when a type has no custom color yet.
    private var markYellow: Color { Color(red: 1, green: 0.92, blue: 0.23) }

    private func color(for type: MistakeMarkType) -> Color {
        markTypeColors[type] ?? markYellow
    }

    private var reviewMarkingToolbar: some View {
        HStack(spacing: toolSpacing) {
            toolButton(
                systemName: "highlighter",
                isActive: isMarkingMode,
                activeBackground: color(for: activeMarkType),
                activeForeground: .black,
                action: { onToggleMarkingMode?() }
            )

            if isReviewListener {
                toolButton(
                    systemName: pageHidden ? "eye.slash.fill" : "eye.fill",
                    isActive: pageHidden,
                    activeBackground: Color(red: 0.35, green: 0.35, blue: 0.38),
                    action: { onTogglePageHidden?() }
                )
            }

            if showsOwnMarkViewTools, hasSessionMarks || !areSessionMarksVisible || isSessionMarksInverted {
                toolButton(
                    systemName: areSessionMarksVisible ? "eye.fill" : "eye.slash.fill",
                    isActive: !areSessionMarksVisible,
                    activeBackground: Color(red: 0.35, green: 0.35, blue: 0.38),
                    activeForeground: .white,
                    action: { onToggleSessionMarksVisible?() }
                )

                invertButton(
                    isActive: isSessionMarksInverted,
                    action: { onToggleSessionMarksInverted?() }
                )
            }

            if isMarkingMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: toolSpacing) {
                        if showsMarkTypePills {
                            ForEach(orderedMarkTypes) { type in
                                let typeColor = color(for: type)
                                Button {
                                    onSelectMarkType?(type)
                                } label: {
                                    Text(type.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(
                                            !isFireMode && activeMarkType == type
                                                ? .black
                                                : idleToolForeground
                                        )
                                        .padding(.horizontal, isCompactLandscape ? 8 : 10)
                                        .padding(.vertical, isCompactLandscape ? 6 : 8)
                                        .background(
                                            !isFireMode && activeMarkType == type
                                                ? typeColor
                                                : (isDarkMode ? Color.white.opacity(0.10) : Color(.tertiarySystemFill))
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            onToggleFireMode?()
                        } label: {
                            Image(systemName: "flame.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isFireMode ? Color.white : idleToolForeground)
                                .padding(.horizontal, isCompactLandscape ? 8 : 10)
                                .padding(.vertical, isCompactLandscape ? 6 : 8)
                                .background(
                                    isFireMode
                                        ? Color(red: 0.92, green: 0.32, blue: 0.12)
                                        : (isDarkMode ? Color.white.opacity(0.10) : Color(.tertiarySystemFill))
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fire")
                    }
                }
            } else {
                Spacer(minLength: 0)
            }

            if isCompactLandscape, showsBlockPageNavigation, !isPaintMode {
                inlineBlockNavigation
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
    var isRightToLeft = false
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

    private var textAlignment: TextAlignment { .leading }
    private var frameAlignment: Alignment { .leading }

    private var textColor: Color {
        isDarkMode ? .white : .black
    }

    private var translationFont: Font {
        if isRightToLeft {
            return .custom(MushafTypography.FontName.urduNastaliq, size: 20)
        }
        return .system(size: 16, weight: .regular, design: .serif)
    }

    private var translationLineSpacing: CGFloat { isRightToLeft ? 10 : 3 }

    @ViewBuilder
    private func translationText(lineLimit: Int? = nil) -> some View {
        Text(translation)
            .font(translationFont)
            .foregroundStyle(textColor.opacity(0.9))
            .lineSpacing(translationLineSpacing)
            .lineLimit(lineLimit)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            .flipsForRightToLeftLayoutDirection(false)
            .textSelection(.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if !exceedsSixLines {
                    translationText()
                } else if isExpanded {
                    if fullHeight <= maxExpandedHeight {
                        translationText()
                    } else {
                        ScrollView {
                            translationText()
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .frame(maxHeight: maxExpandedHeight)
                    }
                } else {
                    translationText(lineLimit: collapsedLineCount)
                }
            }
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
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
                    .font(translationFont)
                    .lineSpacing(translationLineSpacing)
                    .lineLimit(maxLineCount)
                    .multilineTextAlignment(textAlignment)
                    .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
                    .frame(width: geo.size.width, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TranslationSixLineHeightKey.self, value: proxy.size.height)
                        }
                    )

                Text(translation)
                    .font(translationFont)
                    .lineSpacing(translationLineSpacing)
                    .multilineTextAlignment(textAlignment)
                    .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
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

struct BlockPageNavigationButtons: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    var size: CGFloat = 44
    var corner: CGFloat = 10
    var fill: Color
    var stroke: Color
    var foreground: Color
    var showsShadow = true
    var fillsWidth = true
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            labeledButton(title: "Next mistake", systemName: "chevron.left", chevronLeading: true, enabled: canGoNext, action: onNext)
            labeledButton(title: "Prev mistake", systemName: "chevron.right", chevronLeading: false, enabled: canGoPrevious, action: onPrevious)
        }
    }

    private var rowHeight: CGFloat { min(size, 32) }

    private func labeledButton(
        title: String,
        systemName: String,
        chevronLeading: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if chevronLeading {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !chevronLeading {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(foreground.opacity(enabled ? 1 : 0.35))
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: rowHeight, maxHeight: rowHeight)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(stroke, lineWidth: 1.5)
            )
            .shadow(color: showsShadow ? .black.opacity(0.12) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}
