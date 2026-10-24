import UIKit

/// Keeps selection in the rendered response while scrolling the containing chat.
final class ResponseMarkdownTextView: MarkdownTextView {
    var onInteractionChanged: ((Bool) -> Void)?
    lazy var messageMenu = ResponseMessageMenu(textView: self)
    private var displayLink: CADisplayLink?
    private var dragPoint: CGPoint?
    private var anchor: Int?
    private var lastTimestamp: CFTimeInterval = 0
    private lazy var observer = SelectionDragObserver(target: self, action: #selector(observeDrag(_:)))

    override init() {
        super.init()
        _ = messageMenu
        addGestureRecognizer(observer)
        accessibilityIdentifier = "response.rendered.text"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeFirstResponder: Bool {
        messageMenu.phase == .selection && super.canBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let wasActive = isFirstResponder
        let result = super.resignFirstResponder()
        if result && wasActive {
            stopEdgeScrolling()
            selectedTextRange = nil
            messageMenu.finish()
        }
        return result
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopEdgeScrolling()
            messageMenu.finish()
        }
    }

    @objc private func observeDrag(_ gesture: SelectionDragObserver) {
        guard let window else { return }
        switch gesture.state {
        case .began:
            let point = gesture.location(in: self)
            guard isPointOnSelectionHandle(point), let selectedTextRange else {
                // A fresh touch in the response starts a new interaction. Only
                // dragging a native handle continues the existing selection.
                if messageMenu.phase == .selection { messageMenu.finish() }
                return
            }
            let start = caretRect(for: selectedTextRange.start)
            let end = caretRect(for: selectedTextRange.end)
            let nearStart = hypot(point.x - start.midX, point.y - start.minY)
                < hypot(point.x - end.midX, point.y - end.maxY)
            anchor = nearStart ? NSMaxRange(selectedRange) : selectedRange.location
            dragPoint = gesture.location(in: window)
            lastTimestamp = 0
            let link = CADisplayLink(target: self, selector: #selector(scrollSelection(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        case .changed:
            if anchor != nil { dragPoint = gesture.location(in: window) }
        case .ended, .cancelled, .failed:
            stopEdgeScrolling()
        default: break
        }
    }

    #if DEBUG
    func publishSelectionDiagnostic() {
        guard ProcessInfo.processInfo.arguments.contains("--response-render-fixture"),
              let range = selectedTextRange, let window else { return }
        let end = convert(caretRect(for: range.end), to: window)
        let start = convert(caretRect(for: range.start), to: window)
        let value: [String: Any] = [
            "location": selectedRange.location, "length": selectedRange.length,
            "total": attributedText.length,
            "text": Self.plainText(of: attributedText, in: selectedRange),
            "startX": start.midX, "startY": start.minY,
            "endX": end.midX, "endY": end.maxY,
            "scrollY": enclosingScrollView?.contentOffset.y ?? 0
        ]
        if let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) {
            NotificationCenter.default.post(name: Notification.Name("ResponseTextSelectionDiagnostic"), object: json)
        }
    }
    #endif

    func stopEdgeScrolling() {
        displayLink?.invalidate()
        displayLink = nil
        dragPoint = nil
        anchor = nil
    }

    private var enclosingScrollView: UIScrollView? {
        var parent = superview
        while let view = parent {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               scroll.contentSize.height > scroll.bounds.height { return scroll }
            parent = view.superview
        }
        return nil
    }

    @objc private func scrollSelection(_ link: CADisplayLink) {
        guard let point = dragPoint, let anchor, isFirstResponder,
              let window, let scroll = enclosingScrollView else { return }
        let elapsed = lastTimestamp == 0 ? link.duration : min(0.05, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        let visible = scroll.convert(scroll.bounds, to: window).intersection(window.safeAreaLayoutGuide.layoutFrame)
        let threshold: CGFloat = 44
        let distance: CGFloat
        if point.y < visible.minY + threshold { distance = point.y - visible.minY - threshold }
        else if point.y > visible.maxY - threshold { distance = point.y - visible.maxY + threshold }
        else { return }
        let velocity = max(-360, min(360, distance * 7))
        let lower = -scroll.adjustedContentInset.top
        let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let next = max(lower, min(upper, scroll.contentOffset.y + velocity * elapsed))
        guard next != scroll.contentOffset.y else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
        scroll.layoutIfNeeded()
        guard let position = closestPosition(to: convert(point, from: window)) else { return }
        let end = max(0, min(attributedText.length, offset(from: beginningOfDocument, to: position)))
        let fixed = min(anchor, attributedText.length)
        selectedRange = NSRange(location: min(fixed, end), length: abs(end - fixed))
    }
}

/// Observes the native handle drag without cancelling UIKit's selection gesture.
private final class SelectionDragObserver: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { state = .began }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
}
