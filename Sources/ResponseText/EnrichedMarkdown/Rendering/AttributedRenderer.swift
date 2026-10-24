import UIKit

final class AttributedRenderer {
    private let config: MarkdownStyleConfig
    private let factory: RendererFactory
    /// Root-level plugin block node types and the margins each declares.
    private let rootBlockMargins: [NodeType: BlockMargins]

    init(
        config: MarkdownStyleConfig,
        imageRequestHeaders: [String: String] = [:],
        plugins: [any MarkdownRenderPlugin] = []
    ) {
        self.config = config
        self.factory = RendererFactory(
            config: config,
            imageRequestHeaders: imageRequestHeaders,
            plugins: plugins
        )
        self.rootBlockMargins = plugins.reduce(into: [:]) { margins, plugin in
            for type in plugin.rootBlockNodeTypes where margins[type] == nil {
                margins[type] = plugin.blockMargins(for: type, config: config)
            }
        }
    }

    func renderRoot(_ root: MarkdownASTNode) -> NSMutableAttributedString {
        let context = RenderContext()
        let output = NSMutableAttributedString()

        let paragraphFont = config.paragraph.font ?? UIFont.preferredFont(forTextStyle: .body)
        let paragraphColor = config.paragraph.foregroundColor ?? UIColor.label
        context.setBlockStyle(font: paragraphFont, color: paragraphColor)

        for child in root.children {
            // A synthetic paragraph gives bare plugin block nodes their
            // block margins and alignment.
            if let margins = rootBlockMargins[child.type] {
                context.pluginBlockMargins = margins
                let paragraph = MarkdownASTNode(type: .paragraph, children: [child])
                factory.renderer(for: .paragraph).render(node: paragraph, into: output, context: context)
                context.pluginBlockMargins = nil
                continue
            }
            factory.renderer(for: child.type).render(node: child, into: output, context: context)
        }

        // A trailing prose newline creates an extra empty line in UITextView.
        // Keep code-block spacer paragraphs because they carry panel padding.
        while output.length > 0, output.string.hasSuffix("\n"),
              !MarkdownAttributeValue.boolValue(from: output.attribute(MarkdownAttribute.codeBlock, at: output.length - 1, effectiveRange: nil)) {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        if output.length > 0,
           !MarkdownAttributeValue.boolValue(from: output.attribute(MarkdownAttribute.codeBlock, at: output.length - 1, effectiveRange: nil)) {
            let range = (output.string as NSString).paragraphRange(for: NSRange(location: output.length - 1, length: 0))
            let style = ParagraphStyleHelpers.getOrCreateParagraphStyle(in: output, at: range.location)
            style.paragraphSpacing = 0
            output.addAttribute(.paragraphStyle, value: style, range: range)
        }
        context.clearBlockStyle()
        BaselineShiftRenderer.applyShifts(to: output, config: config)
        SpoilerConcealment.conceal(output, in: NSRange(location: 0, length: output.length))
        return output
    }
}
