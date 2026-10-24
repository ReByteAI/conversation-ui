import UIKit

/// Renders math nodes as baseline-aligned image attachments: inline math at
/// the surrounding font size, root-level display math as a `MathBlock`
/// panel; unset style values inherit from the surrounding text. Typeset
/// failures fall back to the delimited source text.
final class MathRenderer: NodeRenderer {
    typealias Typeset = (
        _ latex: String,
        _ displayMode: Bool,
        _ fontSize: CGFloat,
        _ color: UIColor
    ) -> MathTypesetResult?

    private let typeset: Typeset
    private let blockStyle: MathBlockStyle
    private let inlineStyle: InlineMathStyle
    private let panel: MathPanelStyle
    /// Produces the attachment's VoiceOver label from the source.
    private let accessibilityLabel: (String) -> String

    init(
        typeset: @escaping Typeset,
        blockStyle: MathBlockStyle,
        inlineStyle: InlineMathStyle,
        accessibilityLabel: @escaping (String) -> String
    ) {
        self.typeset = typeset
        self.blockStyle = blockStyle
        self.inlineStyle = inlineStyle
        self.panel = MathPanelStyle(
            backgroundColor: blockStyle.backgroundColor,
            padding: blockStyle.padding ?? 0,
            textAlignment: blockStyle.textAlignment ?? .natural
        )
        self.accessibilityLabel = accessibilityLabel
    }

    func render(node: MarkdownASTNode, into output: NSMutableAttributedString, context: RenderContext) {
        let latex = node.flattenedText()
        guard !latex.isEmpty else { return }

        let isDisplay = node.type == .latexMathDisplay
        let isBlock = context.rendersPluginBlock
        var attributes = context.getTextAttributes()
        let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let fontSize = (isBlock ? blockStyle.fontSize : nil) ?? font.pointSize
        let color = (isBlock ? blockStyle.foregroundColor : inlineStyle.foregroundColor)
            ?? attributes[.foregroundColor] as? UIColor ?? UIColor.label

        guard let result = typeset(latex, isDisplay, fontSize, color) else {
            let delimiter = MathAttachment.delimiter(isDisplay: isDisplay)
            attributes[.font] = font.withSize(fontSize)
            attributes[.foregroundColor] = color
            output.append(NSAttributedString(string: delimiter + latex + delimiter, attributes: attributes))
            return
        }

        attributes[.attachment] = MathAttachment(
            latex: latex,
            isDisplay: isDisplay,
            result: result,
            panel: isBlock ? panel : nil,
            accessibilityLabel: accessibilityLabel(latex)
        )
        SourceOffsetAnnotator.tagSourceRange(in: &attributes, of: node)
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
    }

    /// MathJax typesets formulas offline, independently of the host application.
    static func offlineTypeset(_ latex: String, displayMode: Bool, fontSize: CGFloat, color: UIColor) -> MathTypesetResult? {
        guard let rendered = NativeMathAttachmentRenderer.render(latex, display: displayMode, fontSize: fontSize, color: color) else { return nil }
        return MathTypesetResult(width: rendered.image.size.width,
            ascent: rendered.image.size.height - rendered.descent,
            descent: rendered.descent, image: rendered.image) { _ in }
    }
}
