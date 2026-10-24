import SwiftUI
import UIKit

struct MarkdownTextViewRepresentable: UIViewRepresentable {
    let attributedText: NSAttributedString
    let source: RenderedSource?
    let styleConfig: MarkdownStyleConfig
    let onLinkPress: ((URL) -> Void)?
    let onLinkLongPress: ((URL) -> Void)?
    let selectionMenuConfig: MarkdownSelectionMenuConfig
    let selectionAction: MarkdownSelectionAction?
    let isSelectionEnabled: Bool
    let selectionColor: Color?
    let onTaskListItemTap: ((TaskListInteraction.Hit) -> Void)?
    let spoilerOverlay: any SpoilerOverlayProvider
    let onSpoilerTap: ((NSRange) -> Void)?
    let accessibilityLabels: MarkdownAccessibilityLabels
    let onSelectionChanged: (Bool) -> Void
    var messageMenuStyle = MarkdownMessageMenuStyle.contextMenu
    var messageActions: MarkdownMessageActions? = nil
    var messageHandle: MarkdownMessageHandle? = nil
    var onCustomLinkPress: ((URL, String) -> Void)? = nil
    var onBlockquoteFrames: (([CGRect]) -> Void)? = nil
    var readableSuffix: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = ResponseMarkdownTextView()
        textView.delegate = context.coordinator
        textView.styleConfig = styleConfig
        return textView
    }

    func updateUIView(_ textView: MarkdownTextView, context: Context) {
        context.coordinator.onSelectionChanged = onSelectionChanged
        if let response = textView as? ResponseMarkdownTextView {
            response.onInteractionChanged = { [weak coordinator = context.coordinator] active in coordinator?.selectionChanged(active) }
            response.messageMenu.source = source
            response.messageMenu.style = messageMenuStyle
            response.messageMenu.actions = messageActions
            response.messageMenu.readableSuffix = readableSuffix
            messageHandle?.menu = response.messageMenu
        }
        context.coordinator.onLinkPress = onLinkPress
        context.coordinator.onLinkLongPress = onLinkLongPress
        context.coordinator.source = source
        context.coordinator.selectionMenuConfig = selectionMenuConfig
        context.coordinator.selectionAction = selectionAction
        textView.onLinkPress = onLinkPress
        context.coordinator.onCustomLinkPress = onCustomLinkPress
        textView.onCustomLinkPress = onCustomLinkPress
        textView.onBlockquoteFrames = onBlockquoteFrames
        textView.styleConfig = styleConfig
        textView.isSelectionEnabled = isSelectionEnabled
        textView.tintColor = selectionColor.map { UIColor($0) }
        textView.onTaskListItemTap = onTaskListItemTap
        textView.spoilerOverlays.provider = spoilerOverlay
        textView.onSpoilerTap = onSpoilerTap
        textView.accessibilityLabels = accessibilityLabels
        ImageDecoder.refreshScreenMetrics()
        textView.setMarkdownAttributedText(attributedText)
    }

    static func dismantleUIView(_ uiView: MarkdownTextView, coordinator: Coordinator) {
        coordinator.selectionChanged(false)
        (uiView as? ResponseMarkdownTextView)?.stopEdgeScrolling()
        (uiView as? ResponseMarkdownTextView)?.messageMenu.finish()
        uiView.delegate = nil
        uiView.onTaskListItemTap = nil
        uiView.onSpoilerTap = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownTextView, context: Context) -> CGSize? {
        // Fall back to the view's own window, not UIScreen.main: on iPhone Duo
        // the main screen can be the other display.
        let width = proposal.width
            ?? uiView.window?.bounds.width
            ?? ImageDecoder.largestScreenSide()
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var selecting = false
        var onSelectionChanged: ((Bool) -> Void)?
        func selectionChanged(_ active: Bool) {
            guard active != selecting else { return }
            selecting = active
            onSelectionChanged?(active)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            selectionChanged((textView as? ResponseMarkdownTextView)?.messageMenu.isInteracting
                ?? (textView.isFirstResponder && textView.selectedRange.length > 0))
            #if DEBUG
            (textView as? ResponseMarkdownTextView)?.publishSelectionDiagnostic()
            #endif
        }
        var onLinkPress: ((URL) -> Void)?
        var onLinkLongPress: ((URL) -> Void)?
        var onCustomLinkPress: ((URL, String) -> Void)?
        var source: RenderedSource?
        var selectionMenuConfig = MarkdownSelectionMenuConfig()
        var selectionAction: MarkdownSelectionAction?

        /// Routes a link tap; returns true when a handler consumed it.
        func handleLinkPress(_ url: URL) -> Bool {
            guard let onLinkPress else { return false }
            onLinkPress(url)
            return true
        }

        /// Routes a link long-press; returns true when a handler consumed it.
        /// Without a long-press handler, a press handler consumes every link
        /// interaction (pre-existing behavior: suppresses the system
        /// menu/preview and fires the press).
        func handleLinkLongPress(_ url: URL) -> Bool {
            if let onLinkLongPress {
                onLinkLongPress(url)
                return true
            }
            return handleLinkPress(url)
        }

        /// See `MarkdownTextView.isTouchOnSelectionHandle`: a selection knob
        /// parked over a link would otherwise fire it on drag start.
        private func isGrabbingSelectionHandle(_ textView: UITextView) -> Bool {
            (textView as? SelectionHandleTouchReporting)?.isTouchOnSelectionHandle ?? false
        }

        // iOS 16 (and 17+ fallback when the UITextItem methods are
        // unavailable): tap arrives as .invokeDefaultAction, long-press as
        // .presentActions or .preview.
        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            // `false` suppresses the system preview, as `nil` does for the two
            // UITextItem callbacks below.
            guard !isGrabbingSelectionHandle(textView) else { return false }

            switch interaction {
            case .invokeDefaultAction:
                if let onCustomLinkPress, !LinkRenderer.isWeb(URL) {
                    onCustomLinkPress(URL, MarkdownTextView.linkText(in: textView.attributedText, at: characterRange))
                    return false
                }
                return !handleLinkPress(URL)
            case .presentActions, .preview:
                if textView is ResponseMarkdownTextView { return false }
                return !handleLinkLongPress(URL)
            @unknown default:
                return true
            }
        }

        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard !isGrabbingSelectionHandle(textView) else { return nil }
            if case .link(let url) = textItem.content, let onCustomLinkPress, !LinkRenderer.isWeb(url) {
                let text = MarkdownTextView.linkText(in: textView.attributedText, at: textItem.range)
                return UIAction { _ in onCustomLinkPress(url, text) }
            }
            guard case .link(let url) = textItem.content, let onLinkPress else {
                return defaultAction
            }
            return UIAction { _ in onLinkPress(url) }
        }

        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView,
            menuConfigurationFor textItem: UITextItem,
            defaultMenu: UIMenu
        ) -> UITextItem.MenuConfiguration? {
            guard !isGrabbingSelectionHandle(textView) else { return nil }
            if textView is ResponseMarkdownTextView { return nil }
            guard case .link(let url) = textItem.content else {
                return UITextItem.MenuConfiguration(menu: defaultMenu)
            }
            return handleLinkLongPress(url) ? nil : UITextItem.MenuConfiguration(menu: defaultMenu)
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let specs = SelectionMenuItems.build(
                config: selectionMenuConfig,
                selectedRange: range,
                attributedText: textView.attributedText ?? NSAttributedString(),
                source: source
            )
            var actions: [UIMenuElement] = []
            if let selectionAction,
               let text = Self.selectedText(in: textView, range: range) {
                actions.append(UIAction(title: selectionAction.title,
                    image: UIImage(systemName: selectionAction.systemImage),
                    identifier: .init("response.text.selectionAction")) { [weak textView] _ in
                    // Capture before releasing the frozen streaming snapshot.
                    (textView as? ResponseMarkdownTextView)?.messageMenu.finish()
                    selectionAction.perform(text)
                })
            }
            actions.append(UIAction(title: "Copy", image: MarkdownMenuIcons.image("doc.on.doc")) { [weak textView] _ in
                textView?.copy(nil)
                (textView as? ResponseMarkdownTextView)?.messageMenu.finish()
            })
            let textLength = textView.attributedText?.length ?? 0
            if range.length < textLength { actions.append(Self.makeSelectAllAction(for: textView)) }
            if !specs.isEmpty {
                actions.append(UIMenu(title: "More", image: MarkdownMenuIcons.image("ellipsis"),
                    children: specs.map { Self.makeAction(for: $0, in: textView) }))
            }
            return UIMenu(children: actions)
        }

        static func selectedText(in textView: UITextView, range: NSRange) -> String? {
            guard let attributedText = textView.attributedText,
                  range.location != NSNotFound, range.location >= 0,
                  range.location < attributedText.length, range.length > 0 else { return nil }
            let clamped = NSRange(location: range.location,
                length: min(range.length, attributedText.length - range.location))
            let text = MarkdownTextView.plainText(of: attributedText, in: clamped)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }

        static func makeAction(for spec: MenuItemSpec, in textView: UITextView) -> UIAction {
            UIAction(
                title: spec.title,
                image: MarkdownMenuIcons.image(spec.systemImageName),
                identifier: UIAction.Identifier(spec.identifier)
            ) { [weak textView] _ in
                UIPasteboard.general.string = spec.pasteboardString
                (textView as? ResponseMarkdownTextView)?.messageMenu.finish()
            }
        }

        static func makeSelectAllAction(for textView: UITextView) -> UIAction {
            UIAction(
                title: "Select All",
                image: MarkdownMenuIcons.image("text.badge.checkmark"),
                identifier: UIAction.Identifier("com.swmansion.enriched.markdown.selectAll")
            ) { [weak textView] _ in
                guard let textView else { return }
                Self.selectEntireDocument(in: textView)
            }
        }

        static func selectEntireDocument(in textView: UITextView) {
            textView.selectedRange = NSRange(location: 0, length: textView.attributedText?.length ?? 0)
            (textView as? ResponseMarkdownTextView)?.messageMenu.refreshSelectionMenu()
        }

    }
}
