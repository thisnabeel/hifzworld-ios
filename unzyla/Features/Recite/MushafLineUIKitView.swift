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
    let sessionMarks: [Int: MistakeMarkType]
    let onWordTap: (MushafWord) -> Void
    var onActiveWordFrameChange: ((CGRect?) -> Void)?

    func makeUIView(context: Context) -> MushafLineUIView {
        let view = MushafLineUIView()
        view.onWordTap = onWordTap
        view.onActiveWordFrameChange = onActiveWordFrameChange
        return view
    }

    func updateUIView(_ uiView: MushafLineUIView, context: Context) {
        uiView.onWordTap = onWordTap
        uiView.onActiveWordFrameChange = onActiveWordFrameChange
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
            sessionMarks: sessionMarks
        )
    }
}

final class MushafLineUIView: UIView {
    var onWordTap: ((MushafWord) -> Void)?
    var onActiveWordFrameChange: ((CGRect?) -> Void)?

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
    private var sessionMarks: [Int: MistakeMarkType] = [:]
    private var variationByWordID: [Int: (Variation?, String?)] = [:]
    private var defaultLineTextColor: UIColor = .black

    private static let highlightYellow = UIColor(red: 1, green: 0.94, blue: 0.35, alpha: 1)
    private static let mistakeRed = UIColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)

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
        sessionMarks: [Int: MistakeMarkType]
    ) {
        self.mushafID = mushafID
        self.isDarkMode = isDarkMode
        self.isJuzFirstLine = isJuzFirstLine
        self.activeWordID = activeWordID
        self.paintedWords = paintedWords
        self.arePaintedWordsVisible = arePaintedWordsVisible
        self.isPaintInverted = isPaintInverted
        self.sessionMarks = sessionMarks
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
            label.textColor = resolvedTextColor(
                wordTextColor: wordTextColor,
                paintStyle: paintStyle,
                arePaintedWordsVisible: arePaintedWordsVisible,
                isPaintInverted: isPaintInverted
            )

            if arePaintedWordsVisible, !isPaintInverted, paintStyle == .highlight {
                label.backgroundColor = Self.highlightYellow
                label.layer.cornerRadius = 3
                label.clipsToBounds = true
            } else if arePaintedWordsVisible,
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
        if arePaintedWordsVisible && isPaintInverted {
            return UIColor(white: 1, alpha: 0.35)
        }
        return isDarkMode ? UIColor(white: 0.27, alpha: 1) : .black
    }

    private func resolvedTextColor(
        wordTextColor: UIColor,
        paintStyle: WordPaintStyle?,
        arePaintedWordsVisible: Bool,
        isPaintInverted: Bool
    ) -> UIColor {
        guard arePaintedWordsVisible else { return wordTextColor }

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
        guard arePaintedWordsVisible else { return }

        let labels = stackView.arrangedSubviews.compactMap { $0 as? UILabel }
        guard labels.count == words.count else { return }

        if isPaintInverted {
            let unpaintedIndices = words.indices.filter { paintedWords[words[$0].id] == nil }
            addOverlayRuns(
                indices: unpaintedIndices,
                labels: labels,
                into: blackoutOverlayContainer,
                color: defaultLineTextColor,
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
            alpha: 1,
            labelsHaveBackground: true
        )
    }

    private func addStyledOverlayRuns(
        style: WordPaintStyle,
        labels: [UILabel],
        into container: UIView,
        color: (Int) -> UIColor,
        alpha: CGFloat,
        labelsHaveBackground: Bool = false
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
            guard run.count > 1 || !labelsHaveBackground else { continue }
            addOverlay(
                for: run,
                labels: labels,
                into: container,
                color: color(run[0]),
                alpha: alpha
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
            addOverlay(for: run, labels: labels, into: container, color: color, alpha: alpha)
        }
    }

    private func addOverlay(
        for run: [Int],
        labels: [UILabel],
        into container: UIView,
        color: UIColor,
        alpha: CGFloat
    ) {
        guard let firstIndex = run.first, let lastIndex = run.last else { return }
        let firstLabel = labels[firstIndex]
        let lastLabel = labels[lastIndex]

        let firstFrame = stackView.convert(firstLabel.frame, to: container)
        let lastFrame = stackView.convert(lastLabel.frame, to: container)

        let rect = CGRect(
            x: min(firstFrame.minX, lastFrame.minX),
            y: min(firstFrame.minY, lastFrame.minY),
            width: max(firstFrame.maxX, lastFrame.maxX) - min(firstFrame.minX, lastFrame.minX),
            height: max(firstFrame.height, lastFrame.height)
        )
        guard rect.width > 0, rect.height > 0 else { return }

        let overlay = UIView(frame: rect)
        overlay.backgroundColor = color.withAlphaComponent(alpha)
        overlay.layer.cornerRadius = 3
        overlay.clipsToBounds = true
        container.addSubview(overlay)
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

private extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
