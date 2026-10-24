import SwiftUI
import UIKit

/// Enables `$…$`/`$$…$$` parsing and claims the math node types with
/// offline MathJax-backed rendering.
internal struct LaTeXRenderPlugin: MarkdownRenderPlugin {
    /// VoiceOver label template for a formula; see `label(template:)`.
    /// The public entry points repeat the literal: a package-level constant
    /// cannot be used as a public default argument.
    internal static let defaultAccessibilityLabel: String = "Math: {speech}"

    private let typeset: MathRenderer.Typeset
    private let accessibilityLabel: (String) -> String

    internal init(accessibilityLabel: String = LaTeXRenderPlugin.defaultAccessibilityLabel) {
        self.init(accessibilityLabel: Self.label(template: accessibilityLabel))
    }

    internal init(accessibilityLabel: @escaping (String) -> String) {
        self.init(typeset: MathRenderer.offlineTypeset, accessibilityLabel: accessibilityLabel)
    }

    /// Tests inject a deterministic typesetter.
    init(
        typeset: @escaping MathRenderer.Typeset,
        accessibilityLabel: @escaping (String) -> String = LaTeXRenderPlugin.label(
            template: LaTeXRenderPlugin.defaultAccessibilityLabel
        )
    ) {
        self.typeset = typeset
        self.accessibilityLabel = accessibilityLabel
    }

    /// Resolves a label template: `{speech}` becomes the spoken form of
    /// the formula (`LaTeXSpeech`), `{latex}` its raw source.
    static func label(template: String) -> (String) -> String {
        let speaks = template.contains("{speech}")
        return { latex in
            let spoken = speaks ? template.replacingOccurrences(of: "{speech}", with: LaTeXSpeech.spokenForm(of: latex)) : template
            return spoken.replacingOccurrences(of: "{latex}", with: latex)
        }
    }

    internal func renderer(for type: NodeType, config: MarkdownStyleConfig) -> NodeRenderer? {
        switch type {
        case .latexMathInline, .latexMathDisplay:
            return MathRenderer(
                typeset: typeset,
                blockStyle: config.mathBlock,
                inlineStyle: config.inlineMath,
                accessibilityLabel: accessibilityLabel
            )
        default:
            return nil
        }
    }

    internal func blockMargins(for type: NodeType, config: MarkdownStyleConfig) -> BlockMargins {
        BlockMargins(marginTop: config.mathBlock.marginTop, marginBottom: config.mathBlock.marginBottom)
    }

    internal var defaultTheme: MarkdownTheme? { .latexDefault }

    internal func adjustFlags(_ flags: inout Md4cFlags) {
        flags.latexMathEnabled = true
    }

    internal var rootBlockNodeTypes: Set<NodeType> {
        [.latexMathDisplay]
    }
}

public extension View {
    /// Parses and renders LaTeX math (`$…$` inline, `$$…$$` display) with
    /// the bundled offline MathJax engine, styled by `MarkdownTheme.latexDefault`
    /// underneath the themes applied around this view.
    ///
    /// `accessibilityLabel` is what VoiceOver speaks for a formula:
    /// `{speech}` is replaced by an English reading of the source
    /// (`LaTeXSpeech`, e.g. "x squared over 2"), `{latex}` by the raw
    /// source. The innermost modifier wins.
    func markdownLaTeX(accessibilityLabel: String = "Math: {speech}") -> some View {
        markdownLaTeX(accessibilityLabel: LaTeXRenderPlugin.label(template: accessibilityLabel))
    }

    /// `markdownLaTeX()` with a custom VoiceOver label per formula, for
    /// apps that bring their own LaTeX-to-speech conversion. The closure
    /// receives the raw source and runs on the render queue.
    func markdownLaTeX(accessibilityLabel: @escaping (String) -> String) -> some View {
        transformEnvironment(\.markdownRenderPlugins) { plugins in
            plugins.removeAll { $0 is LaTeXRenderPlugin }
            plugins.append(LaTeXRenderPlugin(accessibilityLabel: accessibilityLabel))
        }
    }
}

public extension MarkdownRenderer {
    /// `MarkdownRenderer.render` with offline MathJax math typesetting installed;
    /// `accessibilityLabel` as in `.markdownLaTeX`.
    static func renderLaTeX(
        _ markdown: String,
        config: MarkdownStyleConfig,
        flags: Md4cFlags = .commonMark,
        imageRequestHeaders: [String: String] = [:],
        accessibilityLabel: String = "Math: {speech}"
    ) -> NSAttributedString {
        renderLaTeX(
            markdown,
            config: config,
            flags: flags,
            imageRequestHeaders: imageRequestHeaders,
            accessibilityLabel: LaTeXRenderPlugin.label(template: accessibilityLabel)
        )
    }

    static func renderLaTeX(
        _ markdown: String,
        config: MarkdownStyleConfig,
        flags: Md4cFlags = .commonMark,
        imageRequestHeaders: [String: String] = [:],
        accessibilityLabel: @escaping (String) -> String
    ) -> NSAttributedString {
        render(
            markdown,
            config: config,
            flags: flags,
            imageRequestHeaders: imageRequestHeaders,
            plugins: [LaTeXRenderPlugin(accessibilityLabel: accessibilityLabel)]
        )
    }
}
