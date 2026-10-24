import XCTest
import UIKit
@testable import ResponseText

@MainActor final class RenderedResponseTests: XCTestCase {
    private func render(_ source: String) -> NSAttributedString {
        MarkdownRenderer.renderLaTeX(ResponseMath(source).renderedMarkdown, config: .baseline())
    }

    func testWholeDocumentSelectionIncludesAtomicTableAndMathAndCopiesTheirContent() {
        let text = render(#"""
        ## First heading

        Before \(x^2\) and after.

        \[\frac{1}{2}\]

        | Item | Formula |
        | --- | --- |
        | Tea | $nx^{n-1}$ |

        Last paragraph.
        """#)
        let view = ResponseMarkdownTextView()
        view.setMarkdownAttributedText(text)
        MarkdownTextViewRepresentable.Coordinator.selectEntireDocument(in: view)
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: text.length))
        var formulas = 0, tables = 0
        text.enumerateAttribute(.attachment, in: view.selectedRange) { value, range, _ in
            if value is MathAttachment { formulas += 1; XCTAssertEqual(range.length, 1) }
            if value is TableAttachment { tables += 1; XCTAssertEqual(range.length, 1) }
        }
        XCTAssertEqual(formulas, 2)
        XCTAssertEqual(tables, 1)
        let plain = MarkdownTextView.plainText(of: text, in: view.selectedRange)
        XCTAssertTrue(plain.contains("Before $x^2$ and after."), plain)
        XCTAssertTrue(plain.contains(#"\frac{1}{2}"#), plain)
        XCTAssertTrue(plain.contains("Item\tFormula\nTea\t$nx^{n-1}$"), plain)
        XCTAssertTrue(plain.contains("Last paragraph."))
        XCTAssertFalse(plain.contains("\u{FFFC}"))
        let html = MarkdownHTMLGenerator.generateHTML(from: text, in: view.selectedRange, config: .baseline())
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains(#"\frac{1}{2}"#))
        XCTAssertTrue(html.contains("nx^{n-1}"))
    }

    func testCurrencyEscapedDollarsAndCodeStayLiteralWhileMathRenders() {
        let text = render(#"""
        Pay $5 and $10. Escaped \$x\$. Formula \(x^2\).

        ```text
        $ignored$ and \[literal\]
        ```
        """#)
        let plain = MarkdownTextView.plainText(of: text, in: NSRange(location: 0, length: text.length))
        XCTAssertTrue(plain.contains("Pay $5 and $10. Escaped $x$. Formula $x^2$."), plain)
        XCTAssertTrue(plain.contains(#"$ignored$ and \[literal\]"#), plain)
        let partial = render(#"Before \[\frac{1}{2}"#)
        XCTAssertTrue(partial.string.contains(#"\[\frac{1}{2}"#), partial.string)
    }

    func testStreamingKeepsRenderedSnapshotAndSourceTogetherUntilSelectionEnds() async throws {
        let store = MarkdownRenderStore()
        store.schedule(markdown: "First **paragraph**.", config: .baseline())
        try await wait { store.source != nil }
        let initial = store.attributedText
        store.setSelecting(true)
        store.schedule(markdown: "First **paragraph**.\n\nSecond paragraph.", config: .baseline())
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.source?.markdown, "First **paragraph**.")
        XCTAssertTrue(store.attributedText === initial)
        store.setSelecting(false)
        try await wait { store.source?.markdown.contains("Second") == true }
        XCTAssertTrue(store.attributedText.string.contains("Second paragraph."))
    }

    func testUnsafeDestinationsStayReadableWithoutInteractiveLinksOrFileAttachments() {
        let text = render("[local](file:///tmp/test) [app](impo://settings) ![Private image](file:///tmp/private.png) [safe](https://impo.ai)")
        var links: [String] = [], attachments = 0
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, _, _ in
            if let url = attrs[.link] as? URL { links.append(url.absoluteString) }
            if attrs[.attachment] != nil { attachments += 1 }
        }
        XCTAssertEqual(links, ["https://impo.ai"])
        XCTAssertEqual(attachments, 0)
        XCTAssertTrue(text.string.contains("Private image"))
    }

    func testShortReplyHasNoTrailingEmptyLineAndCodeCopyKeepsIndentation() {
        let text = render("A short reply.")
        XCTAssertEqual(text.string, "A short reply.")
        let view = ResponseMarkdownTextView()
        view.setMarkdownAttributedText(text)
        XCTAssertLessThan(view.sizeThatFits(CGSize(width: 300, height: 1000)).height, 40)
        let code = render("```swift\n  let answer = 42\n  print(answer)\n```")
        let selected = (code.string as NSString).range(of: "answer")
        let menu = SelectionMenuItems.build(config: .init(), selectedRange: selected, attributedText: code, source: nil)
        XCTAssertEqual(menu.first(where: { $0.kind == .copyCode })?.pasteboardString, "  let answer = 42\n  print(answer)")
    }

    func testTableDirectlyUnderParagraphTextIsATable() {
        // Models often write a label line and the table with no blank line between, as GitHub accepts.
        let document = Parser.shared.parseMarkdown("**七个环节**\n| 环节 | 要点 |\n|---|---|\n| 看清现状 | 公司砸了钱 |", flags: .commonMark)
        XCTAssertEqual(document.children.map(\.type), [.paragraph, .table])
        let plain = Parser.shared.parseMarkdown("line one\nline two\n|---|---|", flags: .commonMark)
        XCTAssertEqual(plain.children.map(\.type), [.paragraph])
    }

    func testClearingStreamWhileSelectingDoesNotRepublishStaleContent() async throws {
        let store = MarkdownRenderStore()
        store.schedule(markdown: "Old reply", config: .baseline())
        try await wait { store.source != nil }
        store.setSelecting(true)
        store.schedule(markdown: "Updated reply", config: .baseline())
        store.schedule(markdown: "", config: .baseline())
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.source?.markdown, "Old reply")
        store.setSelecting(false)
        XCTAssertNil(store.source)
        XCTAssertEqual(store.attributedText.length, 0)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Renderer did not publish the expected document")
    }
}
