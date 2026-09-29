import SwiftUI
import UIKit

struct SurahHeaderLineView: View {
    let surahHeaderPosition: Int
    let lineHeight: CGFloat
    let isDarkMode: Bool

    var body: some View {
        let isBismillah = surahHeaderPosition == -1
        let glyph = isBismillah
            ? MushafTypography.bismillahLigature
            : (MushafTypography.surahHeaderGlyph(position: surahHeaderPosition) ?? "")
        let fontName = isBismillah ? MushafTypography.FontName.bismillah : MushafTypography.FontName.surahNameV2
        let fontSize = isBismillah ? lineHeight * 0.5 : lineHeight * 0.88

        Text(glyph)
            .font(.custom(fontName, size: fontSize))
            .foregroundStyle(isDarkMode ? .white : Color(red: 0.1, green: 0.1, blue: 0.1))
            .frame(maxWidth: .infinity, minHeight: lineHeight, maxHeight: lineHeight)
            .multilineTextAlignment(.center)
            .offset(y: isBismillah ? -lineHeight * 0.13 : 0)
    }
}

struct PageLineMeta: Identifiable {
    let id: String
    let line: MushafLine
    let suppress: Bool
}

struct MushafPageHeaderInfo: Equatable {
    let surahName: String
    let surahNumber: Int
    let pageNumber: Int
    let juzNumber: Int
}

struct PageView: View {
    let page: MushafPage
    let mushafID: Int
    let isDarkMode: Bool
    let isJuzFirstLine: (Int) -> Bool
    let variationLookup: (Int) -> (Variation?, String?)
    let activeWordID: Int?
    let paintedWords: [Int: WordPaintStyle]
    let arePaintedWordsVisible: Bool
    let isPaintInverted: Bool
    var isAyahPromptMode = false
    var ayahPromptVisibleWordIDs: Set<Int> = []
    let sessionMarks: [Int: MistakeMarkType]
    var areSessionMarksVisible = true
    var isSessionMarksInverted = false
    var sessionMarkColors: [MistakeMarkType: UIColor] = [:]
    var sessionMarkHeatCounts: [Int: Int] = [:]
    var isFireMode = false
    let contentPushOffset: CGFloat
    var fillsHalfSpread = false
    /// When set in landscape, adds extra padding on the book-spine side of this page.
    var gutterEdge: HorizontalEdge? = nil
    /// IndoPak 13-line header (surah / Arabic page / juz). Nil hides the bar.
    var pageHeader: MushafPageHeaderInfo? = nil
    var allowsRangeHighlight = false
    var verseSearchHighlightWordIDs: Set<Int> = []
    let onWordTap: (MushafWord) -> Void
    var onActiveWordFrameChange: ((CGRect?) -> Void)?

    private var lineMetas: [PageLineMeta] {
        let sorted = page.lines.sorted { $0.position < $1.position }
        return sorted.enumerated().map { index, line in
            let hasText = line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let headerPos = line.surahHeaderPosition ?? 0

            var suppress = line.suppressLine == true
            if mushafID == MushafID.indoPak.rawValue, index > 0, !hasText {
                let prev = sorted[index - 1]
                let prevHasText = prev.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let prevHeader = prev.surahHeaderPosition ?? 0
                if !prevHasText {
                    if prevHeader > 0 && headerPos != -1 { suppress = true }
                    if prevHeader == -1 && headerPos == -1 { suppress = true }
                }
            }

            return PageLineMeta(id: "\(page.position)-\(line.id)", line: line, suppress: suppress)
        }
    }

    private var juzHighlightIndex: Int {
        lineMetas.firstIndex { meta in
            !meta.suppress && meta.line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } ?? 0
    }

    private var naturalLineHeight: CGFloat { MushafTypography.lineHeight(mushafID: mushafID) }

    /// Odd pages sit on the right leaf; even on the left (RTL open book).
    private var isRightPage: Bool { !page.position.isMultiple(of: 2) }

    private var notesGutterWidth: CGFloat { fillsHalfSpread ? 0 : 4 }
    /// Breathing room between text / line rules and the outer border.
    private var contentToBorderGap: CGFloat { fillsHalfSpread ? 12 : 14 }
    private var innerEdgePadding: CGFloat { fillsHalfSpread ? 12 : 10 }
    private var spinePadding: CGFloat { fillsHalfSpread ? 22 : innerEdgePadding }

    /// Portrait-only micro shift toward the spine so left/right leaves read clearly.
    private var portraitLeafOffset: CGFloat {
        guard !fillsHalfSpread else { return 0 }
        return isRightPage ? -1 : 1
    }

    private var outerBorderEdge: HorizontalEdge { isRightPage ? .trailing : .leading }

    private var innerSidePadding: CGFloat {
        if isRightPage {
            return gutterEdge == .leading ? spinePadding : innerEdgePadding
        }
        return gutterEdge == .trailing ? spinePadding : innerEdgePadding
    }

    private var topPad: CGFloat {
        if pageHeader != nil { return fillsHalfSpread ? 1 : 2 }
        return fillsHalfSpread ? 4 : 8
    }
    private var bottomPad: CGFloat { fillsHalfSpread ? 12 : 20 }
    private var headerBlockHeight: CGFloat { pageHeader == nil ? 0 : 26 }

    private var visibleLineCount: Int {
        lineMetas.reduce(0) { $0 + ($1.suppress ? 0 : 1) }
    }

    var body: some View {
        Group {
            if fillsHalfSpread {
                pageColumn(lineHeight: naturalLineHeight)
                    .frame(maxWidth: .infinity, alignment: .top)
            } else {
                // Scale to the layout height already reduced by top/bottom chrome
                // (friend strip, review banner, deck segment bar, tools via safeAreaInset).
                GeometryReader { geo in
                    let naturalHeight = topPad + bottomPad + headerBlockHeight
                        + CGFloat(visibleLineCount) * naturalLineHeight
                    let available = max(geo.size.height, 1)
                    let scale = min(1, available / max(naturalHeight, 1))
                    pageColumn(lineHeight: naturalLineHeight)
                        .frame(width: geo.size.width, alignment: .top)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
        }
        .offset(x: portraitLeafOffset, y: -contentPushOffset)
        .animation(.easeInOut(duration: 0.22), value: contentPushOffset)
        .animation(.easeInOut(duration: 0.2), value: page.position)
        .background(AppTheme.pageBackground(dark: isDarkMode))
    }

    private func pageColumn(lineHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let pageHeader {
                MushafPageHeaderBar(
                    surahName: pageHeader.surahName,
                    surahNumber: pageHeader.surahNumber,
                    pageNumber: pageHeader.pageNumber,
                    juzNumber: pageHeader.juzNumber,
                    isDarkMode: isDarkMode
                )
                .padding(.bottom, 2)
            }

            VStack(spacing: 0) {
                ForEach(Array(lineMetas.enumerated()), id: \.element.id) { index, meta in
                    if !meta.suppress {
                        lineView(meta: meta, index: index, lineHeight: lineHeight)
                    }
                }
            }
            // Gap between text and the outer rule (border height matches the lines only).
            .padding(.leading, isRightPage ? 0 : contentToBorderGap)
            .padding(.trailing, isRightPage ? contentToBorderGap : 0)
            .overlay(alignment: outerBorderEdge == .trailing ? .trailing : .leading) {
                MushafOuterBorder(edge: outerBorderEdge, isDarkMode: isDarkMode)
            }
        }
        .frame(maxWidth: fillsHalfSpread ? .infinity : 600)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, topPad)
        .padding(.bottom, bottomPad)
        .padding(.leading, isRightPage ? innerSidePadding : notesGutterWidth)
        .padding(.trailing, isRightPage ? notesGutterWidth : innerSidePadding)
    }

    @ViewBuilder
    private func lineView(meta: PageLineMeta, index: Int, lineHeight: CGFloat) -> some View {
        let hasRenderableWords = meta.line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let isGlyphHeader = mushafID == MushafID.indoPak.rawValue && !hasRenderableWords
        let headerPos = meta.line.surahHeaderPosition ?? 0

        if isGlyphHeader {
            SurahHeaderLineView(
                surahHeaderPosition: headerPos,
                lineHeight: lineHeight,
                isDarkMode: isDarkMode
            )
        } else {
            MushafLineUIKitView(
                line: meta.line,
                mushafID: mushafID,
                isDarkMode: isDarkMode,
                isJuzFirstLine: isJuzFirstLine(meta.line.position) && index == juzHighlightIndex,
                variationLookup: variationLookup,
                activeWordID: activeWordID,
                paintedWords: paintedWords,
                arePaintedWordsVisible: arePaintedWordsVisible,
                isPaintInverted: isPaintInverted,
                isAyahPromptMode: isAyahPromptMode,
                ayahPromptVisibleWordIDs: ayahPromptVisibleWordIDs,
                sessionMarks: sessionMarks,
                areSessionMarksVisible: areSessionMarksVisible,
                isSessionMarksInverted: isSessionMarksInverted,
                sessionMarkColors: sessionMarkColors,
                sessionMarkHeatCounts: sessionMarkHeatCounts,
                isFireMode: isFireMode,
                verseSearchHighlightWordIDs: verseSearchHighlightWordIDs,
                allowsWordTap: true,
                onWordTap: onWordTap,
                onActiveWordFrameChange: onActiveWordFrameChange
            )
            .frame(height: lineHeight)
        }
    }
}

extension Color {
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
