import SwiftUI

/// A host-provided action on the rendered selection, independent of copying.
public struct MarkdownSelectionAction {
    public let title: String
    public let systemImage: String
    public let perform: (String) -> Void

    public init(title: String, systemImage: String, perform: @escaping (String) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.perform = perform
    }
}

private struct MarkdownSelectionActionKey: EnvironmentKey {
    static let defaultValue: MarkdownSelectionAction? = nil
}

/// Configuration for the custom items added to the text-selection edit menu.
public struct MarkdownSelectionMenuConfig: Equatable, Sendable {
    public var copyAsMarkdown: Bool
    public var copyImageUrl: Bool
    public var copyAsMarkdownLabel: String

    public init(
        copyAsMarkdown: Bool = true,
        copyImageUrl: Bool = true,
        copyAsMarkdownLabel: String = "Copy as Markdown"
    ) {
        self.copyAsMarkdown = copyAsMarkdown
        self.copyImageUrl = copyImageUrl
        self.copyAsMarkdownLabel = copyAsMarkdownLabel
    }
}

private struct MarkdownSelectionMenuKey: EnvironmentKey {
    static let defaultValue = MarkdownSelectionMenuConfig()
}

public extension EnvironmentValues {
    var markdownSelectionAction: MarkdownSelectionAction? {
        get { self[MarkdownSelectionActionKey.self] }
        set { self[MarkdownSelectionActionKey.self] = newValue }
    }

    var markdownSelectionMenu: MarkdownSelectionMenuConfig {
        get { self[MarkdownSelectionMenuKey.self] }
        set { self[MarkdownSelectionMenuKey.self] = newValue }
    }
}

public extension View {
    func markdownSelectionAction(_ action: MarkdownSelectionAction?) -> some View {
        environment(\.markdownSelectionAction, action)
    }

    /// Configures the custom edit-menu items ("Copy as Markdown",
    /// "Copy Image URL") shown when text is selected.
    func markdownSelectionMenu(_ config: MarkdownSelectionMenuConfig) -> some View {
        environment(\.markdownSelectionMenu, config)
    }
}
