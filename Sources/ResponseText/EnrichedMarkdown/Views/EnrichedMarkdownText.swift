import SwiftUI
import UIKit

public struct EnrichedMarkdownText: View {
    private let markdown: String
    private let flags: Md4cFlags

    @Environment(\.markdownThemeLayers) private var themeLayers
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.markdownLinkPressHandler) private var onLinkPress
    @Environment(\.markdownLinkLongPressHandler) private var onLinkLongPress
    @Environment(\.markdownCustomLinkPressHandler) private var onCustomLinkPress
    @Environment(\.markdownBlockquoteFrames) private var onBlockquoteFrames
    @Environment(\.markdownReadableSuffix) private var readableSuffix
    @Environment(\.markdownSelectionMenu) private var selectionMenuConfig
    @Environment(\.markdownSelectionAction) private var selectionAction
    @Environment(\.markdownSelectable) private var isSelectionEnabled
    @Environment(\.markdownSelectionColor) private var selectionColor
    @Environment(\.markdownImageRequestHeaders) private var imageRequestHeaders
    @Environment(\.markdownRenderPlugins) private var renderPlugins
    @Environment(\.markdownTaskListItemPressHandler) private var onTaskListItemPress
    @Environment(\.markdownTaskListItemToggleEnabled) private var isTaskListToggleEnabled
    @Environment(\.markdownSpoilerOverlay) private var spoilerOverlay
    @Environment(\.markdownAccessibilityLabels) private var accessibilityLabels
    @Environment(\.markdownSelectionChanged) private var onSelectionChanged
    @Environment(\.markdownMessageActions) private var messageActions
    @Environment(\.markdownMessageHandle) private var messageHandle
    @Environment(\.markdownMessageMenuStyle) private var messageMenuStyle

    public init(_ markdown: String, flags: Md4cFlags = .commonMark) {
        self.markdown = markdown
        self.flags = flags
    }

    private var styleConfig: MarkdownStyleConfig {
        let traitCollection = ThemeResolver.traitCollection(
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        )
        // Plugin defaults go above `MarkdownTheme.default` (the environment's
        // first layer) and below the app's themes.
        var layers = themeLayers
        layers.insert(contentsOf: renderPlugins.compactMap(\.defaultTheme), at: min(1, layers.count))
        return MarkdownStyleConfig.resolve(layers: layers, traitCollection: traitCollection)
    }

    public var body: some View {
        // Resolved once: `styleConfig` rebuilds the whole config on each read,
        // and the representable and every `onChange` below read it.
        let config = styleConfig
        return MarkdownRenderHost(markdown: markdown, config: config, flags: flags,
                                  imageRequestHeaders: imageRequestHeaders, plugins: renderPlugins) { renderStore in
            MarkdownTextViewRepresentable(
                attributedText: renderStore.attributedText,
                source: renderStore.source,
                styleConfig: config,
                onLinkPress: onLinkPress,
                onLinkLongPress: onLinkLongPress,
                selectionMenuConfig: selectionMenuConfig,
                selectionAction: selectionAction,
                isSelectionEnabled: isSelectionEnabled,
                selectionColor: selectionColor,
                onTaskListItemTap: isTaskListToggleEnabled ? { hit in
                    let checked = !hit.checked
                    renderStore.applyTaskListToggle(index: hit.index, checked: checked, config: config)
                    onTaskListItemPress?(
                        TaskListItemPressEvent(index: hit.index, checked: checked, text: hit.itemText)
                    )
                } : nil,
                spoilerOverlay: spoilerOverlay,
                onSpoilerTap: { range in
                    renderStore.revealSpoiler(in: range)
                },
                accessibilityLabels: accessibilityLabels,
                onSelectionChanged: { active in
                    renderStore.setSelecting(active)
                    onSelectionChanged?(active)
                }, messageMenuStyle: messageMenuStyle, messageActions: messageActions, messageHandle: messageHandle,
                onCustomLinkPress: onCustomLinkPress, onBlockquoteFrames: onBlockquoteFrames,
                readableSuffix: readableSuffix
            )
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                renderStore.schedule(
                    markdown: markdown,
                    config: config,
                    flags: flags,
                    imageRequestHeaders: imageRequestHeaders,
                    plugins: renderPlugins
                )
            }
            // Schedule the changed value as one render snapshot.
            .onChange(of: markdown) { _, newValue in
                renderStore.schedule(
                    markdown: newValue,
                    config: config,
                    flags: flags,
                    imageRequestHeaders: imageRequestHeaders,
                    plugins: renderPlugins
                )
            }
            .onChange(of: config) { _, newValue in
                renderStore.schedule(
                    markdown: markdown,
                    config: newValue,
                    flags: flags,
                    imageRequestHeaders: imageRequestHeaders,
                    plugins: renderPlugins
                )
            }
            .onChange(of: flags) { _, newValue in
                renderStore.schedule(
                    markdown: markdown,
                    config: config,
                    flags: newValue,
                    imageRequestHeaders: imageRequestHeaders,
                    plugins: renderPlugins
                )
            }
            .onChange(of: imageRequestHeaders) { _, newValue in
                renderStore.schedule(
                    markdown: markdown,
                    config: config,
                    flags: flags,
                    imageRequestHeaders: newValue,
                    plugins: renderPlugins
                )
            }
            .onDisappear {
                renderStore.invalidate()
            }
        }
    }
}

/// StateObject constructs the first document once per row identity, after environment
/// styles are available and before UIKit is asked to measure the text view.
private struct MarkdownRenderHost<Content: View>: View {
    @StateObject private var store: MarkdownRenderStore
    private let content: (MarkdownRenderStore) -> Content

    init(markdown: String, config: MarkdownStyleConfig, flags: Md4cFlags,
         imageRequestHeaders: [String: String], plugins: [any MarkdownRenderPlugin],
         @ViewBuilder content: @escaping (MarkdownRenderStore) -> Content) {
        _store = StateObject(wrappedValue: MarkdownRenderStore(markdown: markdown, config: config,
            flags: flags, imageRequestHeaders: imageRequestHeaders, plugins: plugins))
        self.content = content
    }

    var body: some View { content(store) }
}

#if DEBUG
private let previewMarkdown = """
# Enriched Markdown

Paragraphs support **bold**, *italic*, `inline code`, and [links](https://swmansion.com).

## Lists

- First item
- Second item
  1. Nested ordered item
  2. Another one

> Blockquotes render with a border and background.

```swift
let answer = 42
```

---

Final paragraph after a thematic break.
"""

#Preview("Default theme") {
    ScrollView {
        EnrichedMarkdownText(previewMarkdown)
            .padding()
    }
}

#Preview("Default theme, dark") {
    ScrollView {
        EnrichedMarkdownText(previewMarkdown)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Custom theme") {
    ScrollView {
        EnrichedMarkdownText(previewMarkdown)
            .padding()
    }
    .markdownTheme(
        MarkdownTheme {
            Heading(1)
                .foregroundStyle(.purple)
            Link()
                .foregroundStyle(.teal)
                .underline(true)
            Blockquote()
                .borderColor(.orange)
                .borderWidth(4)
        }
    )
}
#endif
