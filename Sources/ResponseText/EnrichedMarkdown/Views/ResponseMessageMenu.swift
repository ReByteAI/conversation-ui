import UIKit

/// Message actions precede native text selection. Both stages hold the same
/// rendered snapshot so streaming cannot move the content under a user's hand.
/// The host picks how a long press shows them (`MarkdownMessageMenuStyle`).
final class ResponseMessageMenu: NSObject, UIContextMenuInteractionDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    enum Phase { case idle, messageMenu, selection }
    private(set) var phase: Phase = .idle
    private static weak var selectionOwner: ResponseMessageMenu?
    private weak var textView: ResponseMarkdownTextView?
    var source: RenderedSource?
    var actions: MarkdownMessageActions?
    /// The host's text after the document; whole-response Copy and Share end with it.
    var readableSuffix: String?
    private var overlay: ResponseActionsOverlay?
    private var feedbackRequests: [String: String] = [:]
    /// The context menu's Select Text, started once the menu has closed.
    private var pendingSelection: NSRange?
    var style: MarkdownMessageMenuStyle = .contextMenu {
        didSet { if style != oldValue { installTrigger() } }
    }
    private var trigger: AnyObject?
    private var menuPoint = CGPoint.zero
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    private lazy var dismissalTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissSelectionAfterTap(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    init(textView: ResponseMarkdownTextView) {
        self.textView = textView
        super.init()
        installTrigger()
        textView.addInteraction(editMenu)
    }

    private func installTrigger() {
        guard let textView else { return }
        if let press = trigger as? UILongPressGestureRecognizer { textView.removeGestureRecognizer(press) }
        if let interaction = trigger as? UIContextMenuInteraction { textView.removeInteraction(interaction) }
        switch style {
        case .contextMenu:
            let interaction = UIContextMenuInteraction(delegate: self)
            textView.addInteraction(interaction)
            trigger = interaction
        case .actionsOverlay:
            let press = UILongPressGestureRecognizer(target: self, action: #selector(showActions(_:)))
            press.delegate = self
            textView.addGestureRecognizer(press)
            trigger = press
        }
    }

    var isInteracting: Bool { phase != .idle }

    @objc private func showActions(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let textView else { return }
        presentActions(at: gesture.location(in: textView))
    }

    func presentActions(at point: CGPoint) {
        guard let textView, let window = textView.window, let range = prepareMessage(at: point) else { return }
        var presenter = window.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter, !presenter.isBeingDismissed else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let menu = ResponseActionsOverlay(textView: textView, actions: actions ?? MarkdownMessageActions(),
            sourceRect: textView.convert(textView.bounds, to: window))
        menu.view.tintColor = textView.tintColor
        menu.overrideUserInterfaceStyle = textView.traitCollection.userInterfaceStyle
        menu.onClose = { [weak self] selecting in
            self?.overlay = nil
            if !selecting { self?.finish() }
        }
        menu.onCopy = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.copyResponse() }
        menu.onSelect = { [weak self] in self?.beginSelection(in: range) }
        let frozenText = readableResponse()
        menu.onShare = { [weak self, weak presenter] in
            guard let self, let presenter else { return }
            self.share(frozenText, from: presenter, at: self.menuPoint)
        }
        menu.requestID = { [weak self] rating in
            if let id = self?.feedbackRequests[rating] { return id }
            let id = UUID().uuidString; self?.feedbackRequests[rating] = id; return id
        }
        // A confirmed assessment supersedes uncertain earlier attempts of either rating.
        menu.completedRequest = { [weak self] _ in self?.feedbackRequests.removeAll() }
        beginMessageInteraction()
        overlay = menu
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presenter.present(menu, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func prepareMessage(at point: CGPoint) -> NSRange? {
        guard let textView, textView.isSelectionEnabled, phase != .messageMenu,
              textView.attributedText.length > 0, !textView.isPointOnSelectionHandle(point) else { return nil }
        Self.selectionOwner?.finish()
        menuPoint = point
        return paragraphRange(at: point)
    }

    /// The `.contextMenu` style's menu: Copy, Copy as Markdown and Select Text.
    func configuration(at point: CGPoint) -> UIContextMenuConfiguration? {
        guard let range = prepareMessage(at: point) else { return nil }
        return UIContextMenuConfiguration(identifier: "response.text.message" as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                UIAction(title: "Copy", image: MarkdownMenuIcons.image("doc.on.doc"), identifier: .init("response.text.message.copy")) { [weak self] _ in
                    self?.copyResponse()
                },
                UIAction(title: "Copy as Markdown", image: MarkdownMenuIcons.image("doc.text"), identifier: .init("response.text.message.copyMarkdown")) { [weak self] _ in
                    self?.copyMarkdown()
                },
                UIMenu(options: .displayInline, children: [
                    UIAction(title: "Select Text", image: MarkdownMenuIcons.image("text.cursor"), identifier: .init("response.text.message.selectText")) { [weak self] _ in
                        self?.pendingSelection = range
                    }
                ])
            ])
        }
    }

    func beginMessageInteraction() {
        Self.selectionOwner = self
        phase = .messageMenu
        textView?.onInteractionChanged?(true)
    }

    func paragraphRange(at point: CGPoint) -> NSRange {
        guard let textView, let position = textView.closestPosition(to: point) else { return NSRange(location: 0, length: 0) }
        let text = textView.attributedText.string as NSString
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let index = min(text.length - 1, max(0, textView.offset(from: textView.beginningOfDocument, to: position)))
        var range = text.paragraphRange(for: NSRange(location: index, length: 0))
        while range.length > 0, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(text.character(at: NSMaxRange(range) - 1)) ?? "\0") {
            range.length -= 1
        }
        return range
    }

    func copyResponse() {
        guard let textView else { return }
        textView.copyText(in: NSRange(location: 0, length: textView.attributedText.length), suffix: readableSuffix)
    }

    /// The whole response as plain text, with the host's suffix.
    func readableResponse() -> String {
        guard let textView else { return "" }
        let text = MarkdownTextView.plainText(of: textView.attributedText, in: NSRange(location: 0, length: textView.attributedText.length))
        return MarkdownTextView.joined(text, readableSuffix)
    }

    /// The visible row's Share: the whole rendered response, from the top of the text.
    func shareResponse() {
        guard let textView, let window = textView.window, !readableResponse().isEmpty else { return }
        var presenter = window.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter, !presenter.isBeingDismissed else { return }
        share(readableResponse(), from: presenter, at: CGPoint(x: textView.bounds.midX, y: textView.bounds.maxY))
    }

    private func share(_ text: String, from presenter: UIViewController, at point: CGPoint) {
        guard let textView else { return }
        let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = textView
        share.popoverPresentationController?.sourceRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        presenter.present(share, animated: true)
    }

    /// The visible row's Select text: native selection of the whole response.
    func selectResponse() {
        guard let textView, textView.isSelectionEnabled, textView.attributedText.length > 0 else { return }
        Self.selectionOwner?.finish()
        beginSelection(in: NSRange(location: 0, length: textView.attributedText.length))
    }

    func copyMarkdown() {
        guard let textView else { return }
        let text = textView.attributedText ?? NSAttributedString()
        textView.pasteboard.string = MarkdownExtractor.markdown(for: NSRange(location: 0, length: text.length),
            in: text, sourceMarkdown: source?.markdown, flags: source?.flags ?? .commonMark)
    }

    func beginSelection(in range: NSRange) {
        guard let textView, textView.isSelectionEnabled, textView.attributedText.length > 0 else { finish(); return }
        if Self.selectionOwner !== self { Self.selectionOwner?.finish() }
        Self.selectionOwner = self
        phase = .selection
        textView.onInteractionChanged?(true)
        guard textView.becomeFirstResponder() else { finish(); return }
        let length = textView.attributedText.length
        let start = min(max(0, range.location), length - 1)
        textView.selectedRange = NSRange(location: start, length: min(max(1, range.length), length - start))
        textView.layoutIfNeeded()
        // Observe taps in the app's content, not UIKit's menu overlay. This
        // dismisses abandoned selections without swallowing buttons or links.
        textView.window?.rootViewController?.view.addGestureRecognizer(dismissalTap)
        // Wait until the message menu has left the hierarchy and UIKit has
        // installed native selection handles before anchoring the edit menu.
        refreshSelectionMenu()
    }

    func refreshSelectionMenu() {
        DispatchQueue.main.async { [weak self] in self?.presentSelectionMenu() }
    }

    private func presentSelectionMenu() {
        guard phase == .selection, let textView, textView.isFirstResponder,
              let range = textView.selectedTextRange else { return }
        let caret = textView.caretRect(for: range.start)
        let configuration = UIEditMenuConfiguration(identifier: nil,
            sourcePoint: CGPoint(x: caret.midX, y: caret.minY))
        configuration.preferredArrowDirection = .down
        editMenu.presentEditMenu(with: configuration)
    }

    func finish() {
        guard isInteracting || pendingSelection != nil else { return }
        pendingSelection = nil
        if let menu = overlay { overlay = nil; menu.dismiss(animated: false) }
        phase = .idle
        if Self.selectionOwner === self { Self.selectionOwner = nil }
        editMenu.dismissMenu()
        dismissalTap.view?.removeGestureRecognizer(dismissalTap)
        textView?.stopEdgeScrolling()
        textView?.resignFirstResponder()
        textView?.selectedTextRange = nil
        textView?.onInteractionChanged?(false)
    }

    @objc private func dismissSelectionAfterTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended, phase == .selection { finish() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer !== dismissalTap {
            guard let textView else { return false }
            return textView.isSelectionEnabled && !textView.isPointOnSelectionHandle(touch.location(in: textView))
        }
        guard phase == .selection, let textView else { return false }
        return !textView.isPointOnSelectionHandle(touch.location(in: textView))
    }

    /// UIKit must avoid the selected lines, rather than anchor to a zero-size
    /// point that lets the menu cover the paragraph the user is selecting.
    func selectionMenuTargetRect() -> CGRect {
        guard let textView, let range = textView.selectedTextRange, let window = textView.window else { return .null }
        var visible = textView.convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
        var ancestor = textView.superview
        while let view = ancestor {
            if view.clipsToBounds { visible = visible.intersection(textView.convert(view.bounds, from: view)) }
            ancestor = view.superview
        }
        let selected = textView.selectionRects(for: range).reduce(CGRect.null) { result, selection in
            let rect = selection.rect.intersection(visible)
            return rect.isEmpty || rect.isNull ? result : result.union(rect)
        }
        return selected.isNull ? textView.caretRect(for: range.start) : selected.insetBy(dx: 0, dy: -6)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration) -> CGRect { selectionMenuTargetRect() }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        configuration(at: location)
    }

    /// An anchored, transparent preview keeps a long response in its original
    /// layout instead of lifting its entire text view over the navigation bar.
    func stationaryPreview() -> UITargetedPreview? {
        guard let textView else { return nil }
        let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.shadowPath = UIBezierPath()
        return UITargetedPreview(view: anchor, parameters: parameters,
            target: UIPreviewTarget(container: textView, center: menuPoint))
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? { stationaryPreview() }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? { stationaryPreview() }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        beginMessageInteraction()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        let completion = { [weak self] in
            guard let self else { return }
            if let range = self.pendingSelection {
                self.pendingSelection = nil
                self.beginSelection(in: range)
            } else { self.finish() }
        }
        if let animator { animator.addCompletion(completion) } else { completion() }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard phase == .selection, let textView else { return nil }
        return textView.delegate?.textView?(textView, editMenuForTextIn: textView.selectedRange,
            suggestedActions: suggestedActions)
    }
}

extension UIView {
    var enclosingResponseTextView: ResponseMarkdownTextView? {
        var ancestor: UIView? = self
        while let view = ancestor {
            if let response = view as? ResponseMarkdownTextView { return response }
            ancestor = view.superview
        }
        return nil
    }
}
