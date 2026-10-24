import SwiftUI

private struct MarkdownLinkPressHandlerKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

private struct MarkdownLinkLongPressHandlerKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

private struct MarkdownCustomLinkPressHandlerKey: EnvironmentKey {
    static let defaultValue: ((URL, String) -> Void)? = nil
}

private struct MarkdownBlockquoteFramesKey: EnvironmentKey {
    static let defaultValue: (([CGRect]) -> Void)? = nil
}

private struct MarkdownReadableSuffixKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var markdownLinkPressHandler: ((URL) -> Void)? {
        get { self[MarkdownLinkPressHandlerKey.self] }
        set { self[MarkdownLinkPressHandlerKey.self] = newValue }
    }

    var markdownLinkLongPressHandler: ((URL) -> Void)? {
        get { self[MarkdownLinkLongPressHandlerKey.self] }
        set { self[MarkdownLinkLongPressHandlerKey.self] = newValue }
    }

    var markdownCustomLinkPressHandler: ((URL, String) -> Void)? {
        get { self[MarkdownCustomLinkPressHandlerKey.self] }
        set { self[MarkdownCustomLinkPressHandlerKey.self] = newValue }
    }

    var markdownBlockquoteFrames: (([CGRect]) -> Void)? {
        get { self[MarkdownBlockquoteFramesKey.self] }
        set { self[MarkdownBlockquoteFramesKey.self] = newValue }
    }

    var markdownReadableSuffix: String? {
        get { self[MarkdownReadableSuffixKey.self] }
        set { self[MarkdownReadableSuffixKey.self] = newValue }
    }
}

public extension View {
    func onLinkPress(_ action: @escaping (URL) -> Void) -> some View {
        environment(\.markdownLinkPressHandler, action)
    }

    /// Called when a link is long-pressed, replacing the system link menu.
    /// Without this handler, a long-press behaves like a press when
    /// `onLinkPress` is set.
    func onLinkLongPress(_ action: @escaping (URL) -> Void) -> some View {
        environment(\.markdownLinkLongPressHandler, action)
    }

    /// Called with the destination and visible text when a link the theme's
    /// `Link().customURLs` allows is tapped. Web links keep their behavior.
    func onCustomLinkPress(_ action: ((URL, String) -> Void)?) -> some View {
        environment(\.markdownCustomLinkPressHandler, action)
    }

    /// Reports the frame of each quote that no other quote encloses, in
    /// document order and in the rendered view's coordinates, full width.
    func onMarkdownBlockquoteFrames(_ action: @escaping ([CGRect]) -> Void) -> some View {
        environment(\.markdownBlockquoteFrames, action)
    }

    /// Plain text the host shows after the document in its own views. Copy
    /// and Share of the whole response end with it.
    func markdownReadableSuffix(_ text: String?) -> some View {
        environment(\.markdownReadableSuffix, text)
    }
}
