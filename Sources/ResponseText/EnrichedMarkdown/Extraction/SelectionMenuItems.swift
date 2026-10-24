import UIKit

struct MenuItemSpec: Equatable {
    enum Kind {
        case copyCode
        case copyMarkdown
        case copyImageURLs
    }

    let kind: Kind
    let title: String
    let systemImageName: String
    let identifier: String
    let pasteboardString: String
}

/// Pure builder for the custom selection-menu items; UIKit menu construction
/// stays in the coordinator so this logic is unit-testable.
enum SelectionMenuItems {
    static let copyMarkdownIdentifier = "com.swmansion.enriched.markdown.copyMarkdown"
    static let copyImageURLIdentifier = "com.swmansion.enriched.markdown.copyImageURL"

    static func build(
        config: MarkdownSelectionMenuConfig,
        selectedRange: NSRange,
        attributedText: NSAttributedString,
        source: RenderedSource?
    ) -> [MenuItemSpec] {
        var specs: [MenuItemSpec] = []
        if selectedRange.location < attributedText.length {
            var range = NSRange()
            let code = attributedText.attribute(MarkdownAttribute.codeBlock, at: selectedRange.location, effectiveRange: &range)
            if MarkdownAttributeValue.boolValue(from: code), NSMaxRange(selectedRange) <= NSMaxRange(range) {
                specs.append(MenuItemSpec(kind: .copyCode, title: "Copy Code", systemImageName: "chevron.left.forwardslash.chevron.right",
                    identifier: "response.text.copyCode", pasteboardString: (attributedText.string as NSString).substring(with: range)
                        .trimmingCharacters(in: .newlines)))
            }
        }

        if config.copyAsMarkdown,
           let markdown = MarkdownExtractor.markdown(
               for: selectedRange,
               in: attributedText,
               sourceMarkdown: source?.markdown,
               flags: source?.flags ?? .commonMark
           ),
           !markdown.isEmpty {
            specs.append(
                MenuItemSpec(
                    kind: .copyMarkdown,
                    title: config.copyAsMarkdownLabel,
                    systemImageName: "doc.text",
                    identifier: copyMarkdownIdentifier,
                    pasteboardString: markdown
                )
            )
        }

        if config.copyImageUrl {
            let urls = MarkdownExtractor.imageURLs(in: attributedText, range: selectedRange)
            if !urls.isEmpty {
                specs.append(
                    MenuItemSpec(
                        kind: .copyImageURLs,
                        title: imageURLsTitle(count: urls.count),
                        systemImageName: "link",
                        identifier: copyImageURLIdentifier,
                        pasteboardString: urls.joined(separator: "\n")
                    )
                )
            }
        }

        return specs
    }

    static func imageURLsTitle(count: Int) -> String {
        count == 1 ? "Copy Image URL" : "Copy \(count) Image URLs"
    }
}
