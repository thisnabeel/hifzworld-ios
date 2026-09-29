import SwiftUI
import UIKit

/// Hold-drag overlay hosted above the mushaf pager (not inside page content),
/// so SwiftUI paint/preview refreshes do not tear down the active gesture.
///
/// Hits pass through to the pager so the page can still swipe. Tap and long-press
/// live on the paging scroll view. After a real hold, paging freezes and a ripple
/// shows that you can drag a range and release.
struct MushafHighlightInteractionOverlay: UIViewRepresentable {
    var isEnabled: Bool
    var onRangeHighlightBegan: (MushafWord) -> Void
    var onRangeHighlightChanged: (MushafWord) -> Void
    var onRangeHighlightEnded: () -> Void

    func makeUIView(context: Context) -> MushafHighlightInteractionView {
        let view = MushafHighlightInteractionView()
        view.onRangeHighlightBegan = onRangeHighlightBegan
        view.onRangeHighlightChanged = onRangeHighlightChanged
        view.onRangeHighlightEnded = onRangeHighlightEnded
        return view
    }

    func updateUIView(_ uiView: MushafHighlightInteractionView, context: Context) {
        uiView.onRangeHighlightBegan = onRangeHighlightBegan
        uiView.onRangeHighlightChanged = onRangeHighlightChanged
        uiView.onRangeHighlightEnded = onRangeHighlightEnded
        uiView.setInteractionEnabled(isEnabled)
    }
}

final class MushafHighlightInteractionView: UIView, UIGestureRecognizerDelegate {
    var onRangeHighlightBegan: ((MushafWord) -> Void)?
    var onRangeHighlightChanged: ((MushafWord) -> Void)?
    var onRangeHighlightEnded: (() -> Void)?

    private var rangeActive = false
    private var wantsGestures = false
    private var gesturesAttached = false
    private weak var gestureHost: UIView?
    private var frozenPagingScrolls: [UIScrollView] = []

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.minimumPressDuration = 0.42
        gesture.allowableMovement = 14
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

    func setInteractionEnabled(_ enabled: Bool) {
        wantsGestures = enabled
        if enabled {
            attachGesturesIfNeeded()
        } else {
            detachGestures()
            unfreezePagingScrolls()
            if rangeActive {
                rangeActive = false
                onRangeHighlightEnded?()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, wantsGestures {
            attachGesturesIfNeeded()
        } else if window == nil {
            detachGestures()
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let word = wordAt(gesture.location(in: self)) else { return }
            rangeActive = true
            freezePagingScrolls()
            playRipple(at: gesture.location(in: self))
            onRangeHighlightBegan?(word)
        case .changed:
            guard rangeActive, let word = wordAt(gesture.location(in: self)) else { return }
            onRangeHighlightChanged?(word)
        case .ended, .cancelled, .failed:
            finishRangeIfNeeded()
        default:
            break
        }
    }

    private func finishRangeIfNeeded() {
        guard rangeActive else { return }
        rangeActive = false
        unfreezePagingScrolls()
        onRangeHighlightEnded?()
    }

    /// Resolve a word under the finger by walking mushaf line views (cross-line safe).
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
        let host = findPagingScrollView() ?? superview
        guard let host else { return }
        if gesturesAttached, gestureHost === host { return }
        detachGestures()
        gestureHost = host
        host.addGestureRecognizer(longPressGesture)
        gesturesAttached = true
    }

    private func detachGestures() {
        longPressGesture.view?.removeGestureRecognizer(longPressGesture)
        gestureHost = nil
        gesturesAttached = false
    }

    private func findPagingScrollView() -> UIScrollView? {
        var node: UIView? = superview
        var fallback: UIScrollView?
        while let current = node {
            if let paging = firstScrollView(in: current, pagingOnly: true) {
                return paging
            }
            if fallback == nil {
                fallback = firstScrollView(in: current, pagingOnly: false)
            }
            node = current.superview
        }
        return fallback
    }

    private func firstScrollView(in view: UIView, pagingOnly: Bool) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !pagingOnly || scroll.isPagingEnabled {
            return scroll
        }
        for sub in view.subviews {
            if let scroll = firstScrollView(in: sub, pagingOnly: pagingOnly) {
                return scroll
            }
        }
        return nil
    }

    private func freezePagingScrolls() {
        unfreezePagingScrolls()
        var seen = Set<ObjectIdentifier>()
        var node: UIView? = superview
        while let current = node {
            freezeScrolls(from: current, seen: &seen)
            node = current.superview
        }
    }

    private func freezeScrolls(from root: UIView, seen: inout Set<ObjectIdentifier>) {
        if let scroll = root as? UIScrollView {
            let id = ObjectIdentifier(scroll)
            if !seen.contains(id) {
                seen.insert(id)
                if scroll.isScrollEnabled {
                    scroll.isScrollEnabled = false
                    frozenPagingScrolls.append(scroll)
                }
            }
        }
        for sub in root.subviews {
            freezeScrolls(from: sub, seen: &seen)
        }
    }

    private func unfreezePagingScrolls() {
        for scroll in frozenPagingScrolls {
            scroll.isScrollEnabled = true
        }
        frozenPagingScrolls.removeAll()
    }

    private func playRipple(at localPoint: CGPoint) {
        let ripple = RangeHighlightRippleView(center: localPoint)
        addSubview(ripple)
        ripple.play { [weak ripple] in
            ripple?.removeFromSuperview()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        wordAt(gestureRecognizer.location(in: self)) != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if rangeActive { return false }
        if otherGestureRecognizer is UIPanGestureRecognizer { return true }
        if otherGestureRecognizer.view is UIScrollView { return true }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

/// Expanding rings at the long-press point: hold is armed, drag to select, release to apply.
private final class RangeHighlightRippleView: UIView {
    private let rings: [CAShapeLayer]

    init(center: CGPoint) {
        let ringA = CAShapeLayer()
        let ringB = CAShapeLayer()
        rings = [ringA, ringB]
        super.init(frame: CGRect(x: center.x - 90, y: center.y - 90, width: 180, height: 180))
        isUserInteractionEnabled = false
        backgroundColor = .clear

        let ink = UIColor(red: 0.0, green: 0.83, blue: 1.0, alpha: 1)
        for (index, ring) in rings.enumerated() {
            let inset: CGFloat = index == 0 ? 70 : 62
            ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = ink.withAlphaComponent(index == 0 ? 0.85 : 0.45).cgColor
            ring.lineWidth = index == 0 ? 2.5 : 1.5
            ring.opacity = 0
            layer.addSublayer(ring)
        }

        let core = CAShapeLayer()
        core.path = UIBezierPath(ovalIn: CGRect(x: 84, y: 84, width: 12, height: 12)).cgPath
        core.fillColor = ink.withAlphaComponent(0.55).cgColor
        core.opacity = 0
        core.name = "core"
        layer.addSublayer(core)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func play(completion: @escaping () -> Void) {
        let core = layer.sublayers?.first(where: { $0.name == "core" })

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        for (index, ring) in rings.enumerated() {
            let delay = Double(index) * 0.08
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.35
            scale.toValue = 2.35
            scale.duration = 0.55
            scale.beginTime = CACurrentMediaTime() + delay
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scale.fillMode = .forwards
            scale.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            fade.duration = 0.55
            fade.beginTime = CACurrentMediaTime() + delay
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false

            ring.add(scale, forKey: "ripple.scale")
            ring.add(fade, forKey: "ripple.fade")
        }

        if let core {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.4, 1.15, 1.0]
            pop.keyTimes = [0, 0.45, 1]
            pop.duration = 0.28
            pop.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            fade.beginTime = CACurrentMediaTime() + 0.18
            fade.duration = 0.32
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false

            core.add(pop, forKey: "core.scale")
            core.add(fade, forKey: "core.fade")
        }

        CATransaction.commit()
    }
}
