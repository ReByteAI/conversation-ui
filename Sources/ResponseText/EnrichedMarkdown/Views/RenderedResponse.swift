import SwiftUI

/// Drop-in response text. The host supplies its theme, link behavior and
/// interaction callback through the regular Markdown environment modifiers.
public struct RenderedResponse: View {
    private let markdown: String

    public init(_ markdown: String) { self.markdown = markdown }

    public var body: some View {
        EnrichedMarkdownText(ResponseMath(markdown).renderedMarkdown)
            .markdownLaTeX()
    }
}
