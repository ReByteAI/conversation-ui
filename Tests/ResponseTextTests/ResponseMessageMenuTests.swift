import XCTest
import UIKit
@testable import ResponseText

@MainActor final class ResponseMessageMenuTests: XCTestCase {
    private func view(_ source: String) -> ResponseMarkdownTextView {
        let textView = ResponseMarkdownTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 340, height: 900)
        textView.setMarkdownAttributedText(MarkdownRenderer.renderLaTeX(ResponseMath(source).renderedMarkdown, config: .baseline()))
        textView.layoutIfNeeded()
        return textView
    }

    func testMessageMenuCannotStartNativeSelectionAndCancelReleasesSnapshot() throws {
        let textView = view("First paragraph.\n\nSecond paragraph.")
        let controller = textView.messageMenu
        var active: [Bool] = []
        textView.onInteractionChanged = { active.append($0) }
        XCTAssertFalse(textView.canBecomeFirstResponder)
        let configuration = try XCTUnwrap(controller.configuration(at: CGPoint(x: 15, y: 12)))
        let interaction = UIContextMenuInteraction(delegate: controller)
        controller.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: nil)
        XCTAssertTrue(controller.isInteracting)
        XCTAssertFalse(textView.canBecomeFirstResponder)
        XCTAssertEqual(textView.selectedRange.length, 0)
        controller.contextMenuInteraction(interaction, willEndFor: configuration, animator: nil)
        XCTAssertFalse(controller.isInteracting)
        XCTAssertEqual(active, [true, false])
    }

    func testMessageCopyIncludesWholeRenderedResponseWithoutChangingSelection() {
        let textView = view(#"""
        ## Heading

        Before $x^2$ and after.

        | Item | Formula |
        | --- | --- |
        | Tea | $nx^{n-1}$ |

        Last paragraph.
        """#)
        textView.pasteboard = .withUniqueName()
        defer { UIPasteboard.remove(withName: textView.pasteboard.name) }
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.messageMenu.copyResponse()
        let copied = textView.pasteboard.string ?? ""
        XCTAssertTrue(copied.contains("Heading"), copied)
        XCTAssertTrue(copied.contains("Before $x^2$ and after."), copied)
        XCTAssertTrue(copied.contains("Item\tFormula\nTea\t$nx^{n-1}$"), copied)
        XCTAssertTrue(copied.contains("Last paragraph."), copied)
        XCTAssertNotNil(textView.pasteboard.value(forPasteboardType: "public.html"))
        XCTAssertEqual(textView.selectedRange.length, 0)
        XCTAssertFalse(textView.messageMenu.isInteracting)
        XCTAssertFalse(textView.canBecomeFirstResponder)
    }

    func testParagraphSelectionStartsAtThePressedParagraphAndTrimsNewlines() throws {
        let textView = view("First paragraph.\n\nSecond paragraph with **bold words**.\n\nLast paragraph.")
        let string = textView.attributedText.string as NSString
        let second = string.range(of: "Second paragraph with bold words.")
        let position = try XCTUnwrap(textView.position(from: textView.beginningOfDocument, offset: second.location + 4))
        let caret = textView.caretRect(for: position)
        let selected = textView.messageMenu.paragraphRange(at: CGPoint(x: caret.midX, y: caret.midY))
        XCTAssertEqual(selected, second)
    }

    func testVoiceOverOffersMessageCopyAndSelectText() throws {
        let textView = view("Readable reply.")
        let element = try XCTUnwrap(textView.accessibilityElements?.first as? UIAccessibilityElement)
        let actions = element.accessibilityCustomActions?.map(\.name) ?? []
        XCTAssertTrue(actions.contains("Copy Response"))
        XCTAssertTrue(actions.contains("Select Text"))
    }

    func testSelectionMenuHasNoDoneAndKeepsFormatActionsInMore() throws {
        let textView = view("First paragraph.\n\nSecond paragraph.")
        let coordinator = MarkdownTextViewRepresentable.Coordinator()
        let menu = try XCTUnwrap(coordinator.textView(textView,
            editMenuForTextIn: NSRange(location: 0, length: 5), suggestedActions: []))
        XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.title }, ["Copy", "Select All"])
        let more = try XCTUnwrap(menu.children.compactMap { $0 as? UIMenu }.first)
        XCTAssertEqual(more.title, "More")
        XCTAssertTrue(more.children.contains { ($0 as? UIAction)?.title == "Copy as Markdown" })
    }

    func testAbandonedSelectionCanReopenMessageMenuAndReleaseResponder() throws {
        let textView = view("First paragraph.\n\nSecond paragraph.")
        // Needs a host app's window scene; hosted app suites (Impo NativeTests) run it.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene without a host app")
        }
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(textView)
        window.makeKeyAndVisible()
        defer { textView.messageMenu.finish(); window.isHidden = true; previousWindow?.makeKey() }

        textView.messageMenu.beginSelection(in: NSRange(location: 0, length: 5))
        XCTAssertEqual(textView.messageMenu.phase, .selection)
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertGreaterThan(textView.selectedRange.length, 0)
        let rect = textView.messageMenu.selectionMenuTargetRect()
        XCTAssertFalse(rect.isNull)
        XCTAssertGreaterThan(rect.height, 0)

        // No Copy or explicit completion action occurs before this long press.
        XCTAssertNotNil(textView.messageMenu.configuration(at: CGPoint(x: 180, y: 60)))
        XCTAssertEqual(textView.messageMenu.phase, .idle)
        XCTAssertFalse(textView.isFirstResponder)
        XCTAssertEqual(textView.selectedRange.length, 0)
        XCTAssertFalse(textView.canBecomeFirstResponder)
    }

    func testHostSelectionActionUsesOnlySelectedRenderedTextAndPreservesRichContent() throws {
        let textView = view("First paragraph.\n\n中文 **selected words** $x^2$.\n\n| A | B |\n| --- | --- |\n| one | two |\n\nLast paragraph.")
        let coordinator = MarkdownTextViewRepresentable.Coordinator()
        coordinator.selectionAction = MarkdownSelectionAction(title: "Ask Rebyte", systemImage: "text.bubble") { _ in }
        let range = (textView.attributedText.string as NSString).range(of: "中文 selected words")
        XCTAssertEqual(MarkdownTextViewRepresentable.Coordinator.selectedText(in: textView, range: range), "中文 selected words")
        let menu = try XCTUnwrap(coordinator.textView(textView, editMenuForTextIn: range, suggestedActions: []))
        XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.title }, ["Ask Rebyte", "Copy", "Select All"])
        let fullText = try XCTUnwrap(MarkdownTextViewRepresentable.Coordinator.selectedText(in: textView,
            range: NSRange(location: 0, length: textView.attributedText.length)))
        XCTAssertTrue(fullText.contains("$x^2$"), fullText)
        XCTAssertTrue(fullText.contains("A\tB\none\ttwo"), fullText)
        XCTAssertFalse(fullText.contains("\u{FFFC}"))
        XCTAssertNil(MarkdownTextViewRepresentable.Coordinator.selectedText(in: textView,
            range: NSRange(location: NSNotFound, length: 1)))
        XCTAssertNil(MarkdownTextViewRepresentable.Coordinator.selectedText(in: textView,
            range: NSRange(location: 0, length: 0)))
    }

    func testHostPicksTheLongPressTrigger() {
        let textView = view("A reply.")
        let menu = textView.messageMenu
        func contextMenu() -> Bool { textView.interactions.contains { ($0 as? UIContextMenuInteraction)?.delegate === menu } }
        func longPress() -> Bool { textView.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer && $0.delegate === menu } ?? false }
        XCTAssertTrue(contextMenu())
        XCTAssertFalse(longPress())
        menu.style = .actionsOverlay
        XCTAssertFalse(contextMenu())
        XCTAssertTrue(longPress())
        XCTAssertNotNil(menu.prepareMessage(at: CGPoint(x: 15, y: 12)))
        menu.style = .contextMenu
        XCTAssertTrue(contextMenu())
        XCTAssertFalse(longPress())
    }
}
