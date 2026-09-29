import SwiftUI
import UIKit

struct MushafLineUIKitView: UIViewRepresentable {
    let line: MushafLine
    let mushafID: Int
    let isDarkMode: Bool
    let isJuzFirstLine: Bool
    let variationLookup: (Int) -> (Variation?, String?)
    let activeWordID: Int?
    let paintedWords: [Int: WordPaintStyle]
    let arePaintedWordsVisible: Bool
    let isPaintInverted: Bool
    let isAyahPromptMode: Bool
    let ayahPromptVisibleWordIDs: Set<Int>
    let sessionMarks: [Int: MistakeMarkType]
    var areSessionMarksVisible = true
    var isSessionMarksInverted = false
    var sessionMarkColors: [MistakeMarkType: UIColor] = [:]
    var sessionMarkHeatCounts: [Int: Int] = [:]
    var isFireMode = false
    var verseSearchHighlightWordIDs: Set<Int> = []
    /// When false, page overlay owns taps (paint / marking mode).
    var allowsWordTap = true
    let onWordTap: (MushafWord) -> Void
    var onActiveWordFrameChange: ((CGRect?) -> Void)?

    func makeUIView(context: Context) -> MushafLineUIView {
        let view = MushafLineUIView()
        view.onWordTap = onWordTap
        view.onActiveWordFrameChange = onActiveWordFrameChange
        view.allowsWordTap = allowsWordTap
        return view
    }

    func updateUIView(_ uiView: MushafLineUIView, context: Context) {
        uiView.onWordTap = onWordTap
        uiView.onActiveWordFrameChange = onActiveWordFrameChange
        uiView.allowsWordTap = allowsWordTap
        uiView.configure(
            line: line,
            mushafID: mushafID,
            isDarkMode: isDarkMode,
            isJuzFirstLine: isJuzFirstLine,
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
            verseSearchHighlightWordIDs: verseSearchHighlightWordIDs
        )
    }
}

final class MushafLineUIView: UIView {
    var onWordTap: ((MushafWord) -> Void)?
    var onActiveWordFrameChange: ((CGRect?) -> Void)?
    /// When false, word taps are ignored (page overlay owns interaction).
    var allowsWordTap = true

    private var mushafID: Int = 2
    private var lastFitWidth: CGFloat = 0
    private var words: [MushafWord] = []
    private var currentLine: MushafLine?
    private var isDarkMode = false
    private var isJuzFirstLine = false
    private var activeWordID: Int?
    private var paintedWords: [Int: WordPaintStyle] = [:]
    private var arePaintedWordsVisible = true
    private var isPaintInverted = false
    private var isAyahPromptMode = false
    private var ayahPromptVisibleWordIDs: Set<Int> = []
    private var sessionMarks: [Int: MistakeMarkType] = [:]
    private var areSessionMarksVisible = true
    private var isSessionMarksInverted = false
    private var sessionMarkColors: [MistakeMarkType: UIColor] = [:]
    private var sessionMarkHeatCounts: [Int: Int] = [:]
    private var isFireMode = false
    private var verseSearchHighlightWordIDs: Set<Int> = []
    private var variationByWordID: [Int: (Variation?, String?)] = [:]
    private var defaultLineTextColor: UIColor = .black

    private static let highlightYellow = UIColor(red: 1, green: 0.94, blue: 0.35, alpha: 1)
    private static let verseSearchBlue = UIColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 0.52)

    private let highlightOverlayContainer: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let blackoutOverlayContainer: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.semanticContentAttribute = .forceRightToLeft
        stack.backgroundColor = .clear
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(highlightOverlayContainer)
        addSubview(stackView)
        addSubview(blackoutOverlayContainer)
        NSLayoutConstraint.activate([
            highlightOverlayContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightOverlayContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightOverlayContainer.topAnchor.constraint(equalTo: topAnchor),
            highlightOverlayContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blackoutOverlayContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            blackoutOverlayContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            blackoutOverlayContainer.topAnchor.constraint(equalTo: topAnchor),
            blackoutOverlayContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func word(withID id: Int) -> MushafWord? {
        words.first { $0.id == id }
    }

    /// Hit-test a word under a point in this view's coordinates (expanded slightly for drag).
    func wordAtLocalPoint(_ point: CGPoint) -> MushafWord? {
        for case let label as UILabel in stackView.arrangedSubviews {
            let frame = label.convert(label.bounds, to: self).insetBy(dx: -4, dy: -6)
            guard frame.contains(point), let word = words.first(where: { $0.id == label.tag }) else {
                continue
            }
            return word
        }
        return nil
    }

    func configure(
        line: MushafLine,
        mushafID: Int,
        isDarkMode: Bool,
        isJuzFirstLine: Bool,
        variationLookup: (Int) -> (Variation?, String?),
        activeWordID: Int?,
        paintedWords: [Int: WordPaintStyle],
        arePaintedWordsVisible: Bool,
        isPaintInverted: Bool,
        isAyahPromptMode: Bool,
        ayahPromptVisibleWordIDs: Set<Int>,
        sessionMarks: [Int: MistakeMarkType],
        areSessionMarksVisible: Bool,
        isSessionMarksInverted: Bool,
        sessionMarkColors: [MistakeMarkType: UIColor],
        sessionMarkHeatCounts: [Int: Int],
        isFireMode: Bool,
        verseSearchHighlightWordIDs: Set<Int>
    ) {
        self.mushafID = mushafID
        self.isDarkMode = isDarkMode
        self.isJuzFirstLine = isJuzFirstLine
        self.activeWordID = activeWordID
        self.paintedWords = paintedWords
        self.arePaintedWordsVisible = arePaintedWordsVisible
        self.isPaintInverted = isPaintInverted
        self.isAyahPromptMode = isAyahPromptMode
        self.ayahPromptVisibleWordIDs = ayahPromptVisibleWordIDs
        self.sessionMarks = sessionMarks
        self.areSessionMarksVisible = areSessionMarksVisible
        self.isSessionMarksInverted = isSessionMarksInverted
        self.sessionMarkColors = sessionMarkColors
        self.sessionMarkHeatCounts = sessionMarkHeatCounts
        self.isFireMode = isFireMode
        self.verseSearchHighlightWordIDs = verseSearchHighlightWordIDs
        variationByWordID = Dictionary(uniqueKeysWithValues: line.words.map { ($0.id, variationLookup($0.id)) })
        words = line.words
        currentLine = line
        renderLine(force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastFitWidth) > 1 {
            renderLine(force: false)
        } else {
            refreshPaintOverlays()
        }
        if let border = layer.sublayers?.first(where: { $0.name == "lineBorder" }) {
            border.backgroundColor = lineBorderColor().cgColor
            border.frame = CGRect(
                x: 0,
                y: bounds.height - (1 / UIScreen.main.scale),
                width: bounds.width,
                height: 1 / UIScreen.main.scale
            )
        }
        reportActiveWordFrameIfNeeded()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: MushafTypography.lineHeight(mushafID: mushafID))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        renderLine(force: true)
    }

    @objc private func wordTapped(_ gesture: UITapGestureRecognizer) {
        guard allowsWordTap else { return }
        guard let label = gesture.view as? UILabel,
              let word = words.first(where: { $0.id == label.tag }) else { return }
        onWordTap?(word)
    }

    private func renderLine(force: Bool) {
        guard let line = currentLine else { return }
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 34
        if !force, abs(width - lastFitWidth) < 1 { return }
        lastFitWidth = width

        let isDarkMode = self.isDarkMode
        let isJuzFirstLine = self.isJuzFirstLine
        let activeWordID = self.activeWordID
        let paintedWords = self.paintedWords
        let arePaintedWordsVisible = self.arePaintedWordsVisible
        let isPaintInverted = self.isPaintInverted
        let isAyahPromptMode = self.isAyahPromptMode
        let areSessionMarksVisible = self.areSessionMarksVisible
        let isSessionMarksInverted = self.isSessionMarksInverted
        let marksInvertActive = areSessionMarksVisible && isSessionMarksInverted && !sessionMarks.isEmpty

        let baseSize = MushafTypography.baseFontSize(mushafID: mushafID)
        let fontName = MushafTypography.quranFontName(mushafID: mushafID)
        let textColor: UIColor = isJuzFirstLine
            ? .white
            : (isDarkMode ? .white : UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        defaultLineTextColor = textColor

        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        highlightOverlayContainer.subviews.forEach { $0.removeFromSuperview() }
        blackoutOverlayContainer.subviews.forEach { $0.removeFromSuperview() }

        let scale = fitScale(words: line.words, fontName: fontName, baseSize: baseSize, width: width)
        let fontSize = baseSize * scale
        let font = UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .medium)

        for word in line.words {
            let label = UILabel()
            label.font = font
            label.text = word.content
            label.textAlignment = .center
            label.numberOfLines = 1
            label.tag = word.id

            let wordTextColor = self.wordTextColor(for: word, default: textColor)
            let paintStyle = paintedWords[word.id]
            let sessionMark = sessionMarks[word.id]
            let promptHidden = isPromptHidden(word)
            let markHiddenByInvert = marksInvertActive
                && sessionMark == nil
                && paintStyle == nil

            label.textColor = resolvedTextColor(
                wordTextColor: wordTextColor,
                paintStyle: paintStyle,
                arePaintedWordsVisible: arePaintedWordsVisible,
                isPaintInverted: isPaintInverted,
                isPromptHidden: promptHidden || markHiddenByInvert
            )

            // Highlights fill the line via overlay runs (full height + inter-word gaps).
            label.backgroundColor = .clear
            if !isAyahPromptMode,
               arePaintedWordsVisible,
               !isPaintInverted,
               paintStyle == nil,
               activeWordID == word.id {
                label.backgroundColor = wordTextColor.withAlphaComponent(0.25)
                label.layer.cornerRadius = 4
                label.clipsToBounds = true
            }

            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:))))
            stackView.addArrangedSubview(label)
        }

        if mushafID == MushafID.indoPak.rawValue {
            let lineHeight = MushafTypography.lineHeight(mushafID: mushafID)
            layer.sublayers?.filter { $0.name == "lineBorder" }.forEach { $0.removeFromSuperlayer() }
            let border = CALayer()
            border.name = "lineBorder"
            border.backgroundColor = lineBorderColor().cgColor
            border.frame = CGRect(
                x: 0,
                y: lineHeight - (1 / UIScreen.main.scale),
                width: bounds.width,
                height: 1 / UIScreen.main.scale
            )
            layer.addSublayer(border)
        }

        backgroundColor = isJuzFirstLine ? .black : .clear
        invalidateIntrinsicContentSize()
        refreshPaintOverlays()
        reportActiveWordFrameIfNeeded()
    }

    private func reportActiveWordFrameIfNeeded() {
        guard let activeWordID,
              words.contains(where: { $0.id == activeWordID }),
              let window
        else { return }

        let labels = stackView.arrangedSubviews.compactMap { $0 as? UILabel }
        guard let label = labels.first(where: { $0.tag == activeWordID }) else { return }
        let frame = label.convert(label.bounds, to: window)
        onActiveWordFrameChange?(frame)
    }

    private func lineBorderColor() -> UIColor {
        if isJuzFirstLine {
            // Keep the juz strip edge readable in prompt / invert modes.
            return UIColor(white: 1, alpha: 0.35)
        }
        if isAyahPromptMode || (arePaintedWordsVisible && isPaintInverted)
            || (areSessionMarksVisible && isSessionMarksInverted && !sessionMarks.isEmpty) {
            return UIColor(white: 1, alpha: 0.35)
        }
        return isDarkMode ? UIColor(white: 0.27, alpha: 1) : .black
    }

    /// Solid blocks that remain visible on both white pages and the black juz strip.
    private var promptBlackoutColor: UIColor {
        if isJuzFirstLine {
            // White overlays wash out the black juz bar — use mid-gray blocks instead.
            return UIColor(white: 0.42, alpha: 1)
        }
        return defaultLineTextColor
    }

    private func isPromptHidden(_ word: MushafWord) -> Bool {
        guard isAyahPromptMode else { return false }
        if MushafWordVerse.isAyahEndingToken(word, mushafID: mushafID) { return false }
        return !ayahPromptVisibleWordIDs.contains(word.id)
    }

    private func resolvedTextColor(
        wordTextColor: UIColor,
        paintStyle: WordPaintStyle?,
        arePaintedWordsVisible: Bool,
        isPaintInverted: Bool,
        isPromptHidden: Bool
    ) -> UIColor {
        if isPromptHidden {
            return .clear
        }

        guard arePaintedWordsVisible else { return wordTextColor }
        if isAyahPromptMode {
            return wordTextColor
        }

        if isPaintInverted {
            return paintStyle == nil ? .clear : wordTextColor
        }

        switch paintStyle {
        case .blackout:
            return .clear
        case .highlight, .none:
            return wordTextColor
        }
    }

    private func refreshPaintOverlays() {
        stackView.layoutIfNeeded()
        updatePaintOverlays()
    }

    private func wordTextColor(for word: MushafWord, default textColor: UIColor) -> UIColor {
        let (_, narratorColorHex) = variationByWordID[word.id] ?? (nil, nil)
        if let hex = narratorColorHex, let color = UIColor(hex: hex) {
            return color
        }
        return textColor
    }

    private func updatePaintOverlays() {
        highlightOverlayContainer.subviews.forEach { $0.removeFromSuperview() }
        blackoutOverlayContainer.subviews.forEach { $0.removeFromSuperview() }

        let labels = stackView.arrangedSubviews.compactMap { $0 as? UILabel }
        guard labels.count == words.count else { return }

        defer { addVerseSearchOverlayRuns(labels: labels) }

        if areSessionMarksVisible, !isSessionMarksInverted {
            addSessionMarkOverlayRuns(labels: labels)
        }

        if isAyahPromptMode {
            let hiddenIndices = words.indices.filter { isPromptHidden(words[$0]) }
            addOverlayRuns(
                indices: hiddenIndices,
                labels: labels,
                into: blackoutOverlayContainer,
                color: promptBlackoutColor,
                alpha: 1
            )
            addStyledOverlayRuns(
                style: .highlight,
                labels: labels,
                into: highlightOverlayContainer,
                color: { _ in Self.highlightYellow },
                alpha: 1
            )
            addStyledOverlayRuns(
                style: .blackout,
                labels: labels,
                into: blackoutOverlayContainer,
                color: { index in wordTextColor(for: words[index], default: defaultLineTextColor) },
                alpha: 1
            )
            return
        }

        if areSessionMarksVisible, isSessionMarksInverted, !sessionMarks.isEmpty {
            // Page-wide: black out everything that isn't a Mushaf mark (same idea as paint invert).
            let unmarkedIndices = words.indices.filter {
                sessionMarks[words[$0].id] == nil && paintedWords[words[$0].id] == nil
            }
            let invertFill = isJuzFirstLine ? UIColor(white: 0.42, alpha: 1) : defaultLineTextColor
            addOverlayRuns(
                indices: unmarkedIndices,
                labels: labels,
                into: blackoutOverlayContainer,
                color: invertFill,
                alpha: 1
            )
            return
        }

        guard arePaintedWordsVisible else { return }

        if isPaintInverted {
            let unpaintedIndices = words.indices.filter { paintedWords[words[$0].id] == nil }
            let invertFill = isJuzFirstLine ? UIColor(white: 0.42, alpha: 1) : defaultLineTextColor
            addOverlayRuns(
                indices: unpaintedIndices,
                labels: labels,
                into: blackoutOverlayContainer,
                color: invertFill,
                alpha: 1
            )
            return
        }

        addStyledOverlayRuns(
            style: .blackout,
            labels: labels,
            into: blackoutOverlayContainer,
            color: { index in wordTextColor(for: words[index], default: defaultLineTextColor) },
            alpha: 1
        )
        addStyledOverlayRuns(
            style: .highlight,
            labels: labels,
            into: highlightOverlayContainer,
            color: { _ in Self.highlightYellow },
            alpha: 1
        )
    }

    private func addVerseSearchOverlayRuns(labels: [UILabel]) {
        let indices = words.indices.filter { verseSearchHighlightWordIDs.contains(words[$0].id) }
        guard !indices.isEmpty else { return }

        var runs: [[Int]] = []
        var currentRun: [Int] = []
        for index in indices {
            if currentRun.last.map({ $0 + 1 == index }) == true {
                currentRun.append(index)
            } else {
                if !currentRun.isEmpty { runs.append(currentRun) }
                currentRun = [index]
            }
        }
        if !currentRun.isEmpty { runs.append(currentRun) }

        for run in runs {
            addOverlay(
                for: run,
                labels: labels,
                into: highlightOverlayContainer,
                color: Self.verseSearchBlue,
                alpha: 1,
                extendToLineEdges: false,
                fadeOutDuration: 2
            )
        }
    }

    private func addSessionMarkOverlayRuns(labels: [UILabel]) {
        var runs: [(indices: [Int], type: MistakeMarkType, heat: Int)] = []
        var currentIndices: [Int] = []
        var currentType: MistakeMarkType?
        var currentHeat: Int?

        for (index, word) in words.enumerated() {
            let mark = paintedWords[word.id] == nil ? sessionMarks[word.id] : nil
            let heat = sessionMarkHeatCounts[word.id] ?? 0
            if let mark {
                if mark == currentType, heat == currentHeat {
                    currentIndices.append(index)
                } else {
                    if let currentType, let currentHeat, !currentIndices.isEmpty {
                        runs.append((currentIndices, currentType, currentHeat))
                    }
                    currentIndices = [index]
                    currentType = mark
                    currentHeat = heat
                }
            } else if let type = currentType, let heatCount = currentHeat, !currentIndices.isEmpty {
                runs.append((currentIndices, type, heatCount))
                currentIndices = []
                currentType = nil
                currentHeat = nil
            }
        }
        if let currentType, let currentHeat, !currentIndices.isEmpty {
            runs.append((currentIndices, currentType, currentHeat))
        }

        for run in runs {
            let base = sessionMarkColors[run.type] ?? Self.highlightYellow
            addOverlay(
                for: run.indices,
                labels: labels,
                into: highlightOverlayContainer,
                color: Self.darkened(base, heats: run.heat),
                alpha: 1,
                extendToLineEdges: true
            )
        }
        applyFirePulseIfNeeded()
    }

    private func applyFirePulseIfNeeded() {
        for view in highlightOverlayContainer.subviews {
            view.layer.removeAnimation(forKey: "firePulse")
            guard isFireMode else { continue }
            let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
            anim.values = [0, -2.5, 2.5, -2.5, 2.5, 0]
            anim.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            anim.duration = 0.4
            anim.repeatCount = .infinity
            view.layer.add(anim, forKey: "firePulse")
        }
    }

    private static func darkened(_ color: UIColor, heats: Int) -> UIColor {
        let steps = min(max(heats, 0), 6)
        guard steps > 0 else { return color }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = 1 - CGFloat(steps) * 0.08
        return UIColor(red: r * t, green: g * t, blue: b * t, alpha: a)
    }

    private func addStyledOverlayRuns(
        style: WordPaintStyle,
        labels: [UILabel],
        into container: UIView,
        color: (Int) -> UIColor,
        alpha: CGFloat
    ) {
        var runs: [[Int]] = []
        var currentRun: [Int] = []

        for (index, word) in words.enumerated() {
            if paintedWords[word.id] == style {
                currentRun.append(index)
            } else if !currentRun.isEmpty {
                runs.append(currentRun)
                currentRun = []
            }
        }
        if !currentRun.isEmpty { runs.append(currentRun) }

        for run in runs {
            addOverlay(
                for: run,
                labels: labels,
                into: container,
                color: color(run[0]),
                alpha: alpha,
                extendToLineEdges: true
            )
        }
    }

    private func addOverlayRuns(
        indices: [Int],
        labels: [UILabel],
        into container: UIView,
        color: UIColor,
        alpha: CGFloat
    ) {
        var runs: [[Int]] = []
        var currentRun: [Int] = []

        for index in indices {
            if currentRun.last.map({ $0 + 1 == index }) == true {
                currentRun.append(index)
            } else {
                if !currentRun.isEmpty { runs.append(currentRun) }
                currentRun = [index]
            }
        }
        if !currentRun.isEmpty { runs.append(currentRun) }

        for run in runs {
            addOverlay(
                for: run,
                labels: labels,
                into: container,
                color: color,
                alpha: alpha,
                extendToLineEdges: true
            )
        }
    }

    private func addOverlay(
        for run: [Int],
        labels: [UILabel],
        into container: UIView,
        color: UIColor,
        alpha: CGFloat,
        extendToLineEdges: Bool,
        fadeOutDuration: TimeInterval? = nil
    ) {
        guard let firstIndex = run.first, let lastIndex = run.last else { return }
        let firstFrame = stackView.convert(labels[firstIndex].frame, to: container)
        let lastFrame = stackView.convert(labels[lastIndex].frame, to: container)

        var minX = min(firstFrame.minX, lastFrame.minX)
        var maxX = max(firstFrame.maxX, lastFrame.maxX)

        if firstIndex > 0 {
            let prevFrame = stackView.convert(labels[firstIndex - 1].frame, to: container)
            let mid = gapMidpoint(firstFrame, prevFrame)
            minX = min(minX, mid)
            maxX = max(maxX, mid)
        } else if extendToLineEdges {
            extendRunToLineEdge(firstFrame, minX: &minX, maxX: &maxX, in: container)
        }

        if lastIndex < labels.count - 1 {
            let nextFrame = stackView.convert(labels[lastIndex + 1].frame, to: container)
            let mid = gapMidpoint(lastFrame, nextFrame)
            minX = min(minX, mid)
            maxX = max(maxX, mid)
        } else if extendToLineEdges {
            extendRunToLineEdge(lastFrame, minX: &minX, maxX: &maxX, in: container)
        }

        let height = container.bounds.height > 0 ? container.bounds.height : bounds.height
        let rect = CGRect(x: minX, y: 0, width: maxX - minX, height: height)
        guard rect.width > 0, rect.height > 0 else { return }

        let overlay = UIView(frame: rect)
        overlay.backgroundColor = color.withAlphaComponent(alpha)
        container.addSubview(overlay)
        if let fadeOutDuration {
            UIView.animate(withDuration: fadeOutDuration, delay: 0, options: [.curveEaseOut]) {
                overlay.alpha = 0
            }
        }
    }

    /// Midpoint of the space between two word frames (works in LTR and RTL).
    private func gapMidpoint(_ a: CGRect, _ b: CGRect) -> CGFloat {
        if a.maxX <= b.minX {
            return (a.maxX + b.minX) / 2
        }
        if b.maxX <= a.minX {
            return (b.maxX + a.minX) / 2
        }
        return (min(a.minX, b.minX) + max(a.maxX, b.maxX)) / 2
    }

    /// When a run includes the first or last word on the line, fill through that edge.
    private func extendRunToLineEdge(
        _ frame: CGRect,
        minX: inout CGFloat,
        maxX: inout CGFloat,
        in container: UIView
    ) {
        let width = container.bounds.width > 0 ? container.bounds.width : bounds.width
        if frame.midX >= width / 2 {
            maxX = width
        } else {
            minX = 0
        }
    }

    private func fitScale(words: [MushafWord], fontName: String, baseSize: CGFloat, width: CGFloat) -> CGFloat {
        guard !words.isEmpty, width > 0 else { return 1 }
        let font = UIFont(name: fontName, size: baseSize) ?? .systemFont(ofSize: baseSize)
        let widths = words.map { word -> CGFloat in
            (word.content as NSString).size(withAttributes: [.font: font]).width + 4
        }
        let sum = widths.reduce(0, +)
        if sum <= width - 1 { return 1 }
        return MushafLineLayout.fontScale(wordWidths: widths, rowWidth: width, baseFontSize: baseSize)
    }
}
