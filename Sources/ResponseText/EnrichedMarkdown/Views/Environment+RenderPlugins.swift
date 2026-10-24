import SwiftUI

private struct MarkdownRenderPluginsKey: EnvironmentKey {
    static let defaultValue: [any MarkdownRenderPlugin] = []
}

internal extension EnvironmentValues {
    /// Populated by optional modules' public modifiers (`.markdownLaTeX()`).
    var markdownRenderPlugins: [any MarkdownRenderPlugin] {
        get { self[MarkdownRenderPluginsKey.self] }
        set { self[MarkdownRenderPluginsKey.self] = newValue }
    }
}
