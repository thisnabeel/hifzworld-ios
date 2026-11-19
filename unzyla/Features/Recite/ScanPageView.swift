import SwiftUI
import UIKit

/// Draws a scanned mushaf page with the app's word states (paint, marks, highlights) filled into
/// its word tiles, and turns taps on a tile into the same word taps the rendered page sends.
struct ScanPageView: View {
    let store: ScanStore
    let scan: ScanPage
    let page: MushafPage
    let isDarkMode: Bool
    let activeWordID: Int?
    let paintedWords: [Int: WordPaintStyle]
    let arePaintedWordsVisible: Bool
    let isPaintInverted: Bool
    /// Handhold mode: words outside `ayahPromptVisibleWordIDs` are covered with solid blocks.
    var isAyahPromptMode = false
    var ayahPromptVisibleWordIDs: Set<Int> = []
    let sessionMarks: [Int: MistakeMarkType]
    let areSessionMarksVisible: Bool
    let isSessionMarksInverted: Bool
    let sessionMarkColors: [MistakeMarkType: UIColor]
    let verseSearchHighlightWordIDs: Set<Int>
    var highlightedSurah: Int? = nil
    let onWordTap: (MushafWord) -> Void
    /// Taps on a word the scan prints across a page break: the word and its own digital page.
    var onWordTapOnPage: ((MushafWord, Int) -> Void)?

    private static let highlightYellow = Color(red: 1, green: 0.9, blue: 0.2)
    private static let verseSearchBlue = Color(red: 0.4, green: 0.68, blue: 0.98)
    private static let activeBlue = Color(red: 0.2, green: 0.45, blue: 0.95)

    private var inkColor: Color {
        isDarkMode ? Color(white: 0.88) : Color(white: 0.08)
    }

    private var wordsByID: [Int: MushafWord] {
        var map: [Int: MushafWord] = [:]
        for line in page.lines {
            for word in line.words { map[word.id] = word }
        }
        return map
    }

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(in: geo.size)
            ZStack(alignment: .topLeading) {
                scanImage
                    .frame(width: size.width, height: size.height)
                Canvas { context, canvasSize in
                    drawTiles(in: &context, size: canvasSize)
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                handleTap(at: value.location, size: size)
            })
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .task(id: page.position) {
            await store.loadSavedLayout(for: page.position)
            await store.prefetch(around: page.position)
        }
    }

    @ViewBuilder
    private var scanImage: some View {
        let image = Image(uiImage: scan.image).resizable()
        if isDarkMode {
            image.colorInvert()
        } else {
            image
        }
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let aspect = scan.image.size.width / max(scan.image.size.height, 1)
        let width = min(container.width, container.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    /// Tiles are stored relative to the mushaf frame; place them via the frame's spot in the image.
    private func rect(for tile: ScanTile, size: CGSize) -> CGRect {
        let f = scan.frame
        return CGRect(
            x: (f.x + tile.x * f.width) * size.width,
            y: (f.y + tile.y * f.height) * size.height,
            width: tile.width * f.width * size.width,
            height: tile.height * f.height * size.height
        )
    }

    private func drawTiles(in context: inout GraphicsContext, size: CGSize) {
        let highlightBlend: GraphicsContext.BlendMode = isDarkMode ? .normal : .multiply
        let words = isAyahPromptMode ? wordsByID : [:]
        for tile in scan.tiles {
            let r = rect(for: tile, size: size)
            if let surah = tile.surah {
                // Surah header box (title + bismillah): lit up after jumping to that surah.
                if surah == highlightedSurah {
                    var c = context
                    c.blendMode = highlightBlend
                    c.fill(Path(r), with: .color(Self.verseSearchBlue.opacity(isDarkMode ? 0.35 : 0.5)))
                }
                continue
            }
            let ids = tile.ids
            let wordID = ids.first ?? -1
            let paint = paintedWords[wordID]

            if isAyahPromptMode, isPromptHidden(tile, words: words) {
                context.fill(Path(r), with: .color(inkColor))
                continue
            }

            if areSessionMarksVisible && isSessionMarksInverted && !sessionMarks.isEmpty {
                if sessionMarks[wordID] == nil && paint == nil {
                    context.fill(Path(r), with: .color(inkColor))
                }
            } else if arePaintedWordsVisible && isPaintInverted {
                if paint == nil {
                    context.fill(Path(r), with: .color(inkColor))
                }
            } else {
                if areSessionMarksVisible, let mark = sessionMarks[wordID], let uiColor = sessionMarkColors[mark] {
                    var c = context
                    c.blendMode = highlightBlend
                    c.fill(Path(r), with: .color(Color(uiColor).opacity(0.45)))
                }
                if arePaintedWordsVisible, let paint {
                    switch paint {
                    case .blackout:
                        context.fill(Path(r), with: .color(inkColor))
                    case .highlight:
                        var c = context
                        c.blendMode = highlightBlend
                        c.fill(Path(r), with: .color(Self.highlightYellow.opacity(isDarkMode ? 0.4 : 0.75)))
                    }
                }
            }

            if ids.contains(where: verseSearchHighlightWordIDs.contains) {
                var c = context
                c.blendMode = highlightBlend
                c.fill(Path(r), with: .color(Self.verseSearchBlue.opacity(isDarkMode ? 0.35 : 0.5)))
            }
            if let activeWordID, ids.contains(activeWordID) {
                context.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(Self.activeBlue), lineWidth: 2)
            }
        }
    }

    /// Same rule as the rendered page: verse circles stay visible, everything else needs a cue or reveal.
    private func isPromptHidden(_ tile: ScanTile, words: [Int: MushafWord]) -> Bool {
        guard let wordID = tile.ids.first else { return false }
        if ayahPromptVisibleWordIDs.contains(wordID) { return false }
        let word = words[wordID] ?? tile.words?.first?.mushafWord
        if let word, MushafWordVerse.isAyahEndingToken(word, mushafID: store.edition.mushafID) {
            return false
        }
        return true
    }

    /// The tile under the finger, or else the nearest tile on the same printed line,
    /// so taps in the gaps between words still land on the intended word.
    private func tile(at point: CGPoint, size: CGSize) -> ScanTile? {
        let candidates = scan.tiles.filter { $0.surah == nil }
        if let hit = scan.tiles.first(where: { rect(for: $0, size: size).contains(point) }) {
            return hit
        }
        let sameRow = candidates.filter {
            let r = rect(for: $0, size: size)
            return point.y >= r.minY && point.y <= r.maxY
        }
        return sameRow.min { a, b in
            horizontalDistance(from: point.x, to: rect(for: a, size: size))
                < horizontalDistance(from: point.x, to: rect(for: b, size: size))
        }
    }

    private func horizontalDistance(from x: CGFloat, to rect: CGRect) -> CGFloat {
        if x < rect.minX { return rect.minX - x }
        if x > rect.maxX { return x - rect.maxX }
        return 0
    }

    private func handleTap(at point: CGPoint, size: CGSize) {
        guard let tile = tile(at: point, size: size) else { return }
        if let otherPage = tile.page, let word = tile.words?.first?.mushafWord {
            if let onWordTapOnPage { onWordTapOnPage(word, otherPage) } else { onWordTap(word) }
            return
        }
        let words = wordsByID
        guard let word = tile.ids.lazy.compactMap({ words[$0] }).first else { return }
        onWordTap(word)
    }
}
