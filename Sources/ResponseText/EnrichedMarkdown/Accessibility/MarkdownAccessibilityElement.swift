import UIKit

/// VoiceOver element for one segment of the rendered markdown. The frame is
/// resolved lazily from TextKit 2 layout on every query, so scrolling and
/// Dynamic Type changes never leave stale bounds. Elements with a `url`
/// (links, linked images) activate the text view's press handler.
final class MarkdownAccessibilityElement: UIAccessibilityElement {
    private(set) weak var textView: MarkdownTextView?
    let range: NSRange
    let url: URL?
    /// For table rows: vertical slice of the attachment frame.
    private let rowSlice: (offset: CGFloat, height: CGFloat)?

    init(textView: MarkdownTextView, spec: MarkdownAccessibilityElementSpec) {
        self.textView = textView
        self.range = spec.range
        self.url = spec.linkURL
        if case .tableRow(let offset, let height, _) = spec.kind {
            self.rowSlice = (offset, height)
        } else {
            self.rowSlice = nil
        }
        super.init(accessibilityContainer: textView)

        accessibilityLabel = spec.label
        accessibilityValue = spec.value
        accessibilityTraits = Self.traits(for: spec)

        if let level = spec.headingLevel {
            accessibilityAttributedLabel = NSAttributedString(
                string: spec.label,
                attributes: [.accessibilityTextHeadingLevel: level]
            )
        }

        if case .codeBlock(let copyAction) = spec.kind {
            let code = spec.label
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: copyAction) { [weak textView] _ in
                    guard let textView else { return false }
                    textView.pasteboard.string = code
                    return true
                }
            ]
        }
        // The overlay style offers its message actions only on selectable text.
        if let response = textView as? ResponseMarkdownTextView,
           response.messageMenu.style == .contextMenu || response.isSelectionEnabled {
            let overlay = response.messageMenu.style == .actionsOverlay
            accessibilityCustomActions = (accessibilityCustomActions ?? []) + (overlay ? [
                UIAccessibilityCustomAction(name: "Message actions") { [weak response] _ in
                    guard let response, let position = response.position(from: response.beginningOfDocument, offset: spec.range.location) else { return false }
                    let caret = response.caretRect(for: position)
                    response.messageMenu.presentActions(at: CGPoint(x: caret.midX, y: caret.midY))
                    return true
                }
            ] : []) + [
                UIAccessibilityCustomAction(name: "Copy Response") { [weak response] _ in
                    guard let response else { return false }
                    response.messageMenu.copyResponse()
                    return true
                },
                UIAccessibilityCustomAction(name: "Select Text") { [weak response] _ in
                    guard let response else { return false }
                    response.messageMenu.beginSelection(in: spec.range)
                    return true
                }
            ]
        }
    }

    private static func traits(for spec: MarkdownAccessibilityElementSpec) -> UIAccessibilityTraits {
        var traits: UIAccessibilityTraits = switch spec.kind {
        case .text, .codeBlock: .staticText
        case .link: .link
        case .image(let link): link == nil ? .image : [.image, .link]
        case .tableRow(_, _, let isHeader): isHeader ? [.staticText, .header] : .staticText
        }
        if spec.headingLevel != nil {
            traits.insert(.header)
        }
        return traits
    }

    override var accessibilityFrame: CGRect {
        get {
            guard var frame = textView?.accessibilityScreenFrame(for: range), frame != .zero else {
                return .zero
            }
            if let rowSlice {
                frame.origin.y += rowSlice.offset
                frame.size.height = rowSlice.height
            }
            return frame
        }
        set { super.accessibilityFrame = newValue }
    }

    override func accessibilityActivate() -> Bool {
        if let url, let textView, let onCustomLinkPress = textView.onCustomLinkPress, !LinkRenderer.isWeb(url) {
            onCustomLinkPress(url, MarkdownTextView.linkText(in: textView.attributedText ?? NSAttributedString(), at: range))
            return true
        }
        guard let url, let onLinkPress = textView?.onLinkPress else { return false }
        onLinkPress(url)
        return true
    }
}
