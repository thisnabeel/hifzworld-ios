import SwiftUI

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
    let sessionMarks: [Int: MistakeMarkType]
    let contentPushOffset: CGFloat
    var fillsHalfSpread = false
    /// When set in landscape, adds extra padding on the book-spine side of this page.
    var gutterEdge: HorizontalEdge? = nil
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

    private var lineHeight: CGFloat { MushafTypography.lineHeight(mushafID: mushafID) }

    private var outerPadding: CGFloat { fillsHalfSpread ? 10 : 2 }
    private var spinePadding: CGFloat { fillsHalfSpread ? 22 : outerPadding }

    private var leadingPadding: CGFloat {
        gutterEdge == .leading ? spinePadding : outerPadding
    }

    private var trailingPadding: CGFloat {
        gutterEdge == .trailing ? spinePadding : outerPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lineMetas.enumerated()), id: \.element.id) { index, meta in
                if !meta.suppress {
                    lineView(meta: meta, index: index)
                }
            }
        }
        .frame(maxWidth: fillsHalfSpread ? .infinity : 600)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsHalfSpread ? nil : .infinity,
            alignment: .top
        )
        .padding(.top, fillsHalfSpread ? 4 : 8)
        .padding(.bottom, fillsHalfSpread ? 12 : 32)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .offset(y: -contentPushOffset)
        .animation(.easeInOut(duration: 0.22), value: contentPushOffset)
        .background(AppTheme.pageBackground(dark: isDarkMode))
    }

    @ViewBuilder
    private func lineView(meta: PageLineMeta, index: Int) -> some View {
        let hasRenderableWords = meta.line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let isGlyphHeader = mushafID == MushafID.indoPak.rawValue && !hasRenderableWords

        if isGlyphHeader {
            SurahHeaderLineView(
                surahHeaderPosition: meta.line.surahHeaderPosition ?? 0,
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
                sessionMarks: sessionMarks,
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
