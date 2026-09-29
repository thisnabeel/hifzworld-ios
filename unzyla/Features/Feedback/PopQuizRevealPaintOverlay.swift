import SwiftUI
import UIKit

/// Finger-paint overlay for Pop Quiz blackout reveal.
/// Hits pass through so buttons stay tappable; a zero-delay press tracks the finger.
struct PopQuizRevealPaintOverlay: UIViewRepresentable {
    var onRevealWord: (MushafWord) -> Void

    func makeUIView(context: Context) -> PopQuizRevealPaintView {
        let view = PopQuizRevealPaintView()
        view.onRevealWord = onRevealWord
        return view
    }

    func updateUIView(_ uiView: PopQuizRevealPaintView, context: Context) {
        uiView.onRevealWord = onRevealWord
        uiView.reattachGesturesIfNeeded()
    }
}

final class PopQuizRevealPaintView: UIView, UIGestureRecognizerDelegate {
    var onRevealWord: ((MushafWord) -> Void)?

    private var gesturesAttached = false
    private weak var gestureHost: UIView?
    private var lastRevealedWordID: Int?

    private lazy var paintGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePaint(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attachGesturesIfNeeded()
        } else {
            detachGestures()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil {
            attachGesturesIfNeeded()
        }
    }

    func reattachGesturesIfNeeded() {
        if window != nil {
            attachGesturesIfNeeded()
        }
    }

    @objc private func handlePaint(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastRevealedWordID = nil
            revealWord(at: gesture.location(in: self))
        case .changed:
            revealWord(at: gesture.location(in: self))
        case .ended, .cancelled, .failed:
            lastRevealedWordID = nil
        default:
            break
        }
    }

    private func revealWord(at localPoint: CGPoint) {
        guard let word = wordAt(localPoint) else { return }
        if lastRevealedWordID == word.id { return }
        lastRevealedWordID = word.id
        onRevealWord?(word)
    }

    private func wordAt(_ localPoint: CGPoint) -> MushafWord? {
        let windowPoint = convert(localPoint, to: nil)
        var lines: [MushafLineUIView] = []
        var searchRoot: UIView? = superview
        while let root = searchRoot, lines.isEmpty {
            collectLineViews(from: root, into: &lines)
            searchRoot = root.superview
        }
        for line in lines {
            let pointInLine = line.convert(windowPoint, from: nil)
            if let word = line.wordAtLocalPoint(pointInLine) {
                return word
            }
        }
        return nil
    }

    private func collectLineViews(from root: UIView, into lines: inout [MushafLineUIView]) {
        if let line = root as? MushafLineUIView {
            lines.append(line)
            return
        }
        for sub in root.subviews {
            collectLineViews(from: sub, into: &lines)
        }
    }

    private func attachGesturesIfNeeded() {
        // Attach to an ancestor that contains mushaf lines. The overlay's immediate
        // superview is a sibling PlatformViewHost (allowsHitTesting false), so
        // touches on lines never reach a gesture on that host.
        guard let host = findLineContainingAncestor() ?? superview else { return }
        if gesturesAttached, gestureHost === host { return }
        detachGestures()
        gestureHost = host
        host.addGestureRecognizer(paintGesture)
        gesturesAttached = true
    }

    /// Nearest ancestor whose subtree includes mushaf line views (so paint touches hit this host).
    private func findLineContainingAncestor() -> UIView? {
        var node: UIView? = superview?.superview
        while let current = node {
            var lines: [MushafLineUIView] = []
            collectLineViews(from: current, into: &lines)
            if !lines.isEmpty {
                return current
            }
            node = current.superview
        }
        return nil
    }

    private func detachGestures() {
        paintGesture.view?.removeGestureRecognizer(paintGesture)
        gestureHost = nil
        gesturesAttached = false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        wordAt(gestureRecognizer.location(in: self)) != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Only arm paint when the touch starts on a mushaf line, so buttons stay responsive.
        var node: UIView? = touch.view
        while let current = node {
            if current is MushafLineUIView { return true }
            if current is UIControl { return false }
            node = current.superview
        }
        return false
    }
}
