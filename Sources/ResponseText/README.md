# Copyable native response text

Copy this entire directory into another app's repository. Each app owns its
copy: there is no shared checkout, symlink, remote renderer package or runtime
service. `Package.swift` is optional local build wiring; Impo instead compiles
the same sources with two Xcode targets.

The directory contains the vendored Markdown parser, native text renderer,
offline formula adapter, delimiter normalization, message menu, continuous
selection, attachment copying, edge scrolling and streaming snapshot handling.
The app owns its colors, typography, conversation state and network protocol.

## Integration

Build `core` and `cpp` as `EnrichedMarkdownCppShim` (C++17, `MD4C_USE_UTF8=1`),
and `Sources` as a Swift 5 target. Link MathJaxSwift 3.4+ and SwiftDraw 0.20.1+
for offline equations. A local Swift package consumer can use the included
manifest and its `ResponseText` product, conditional on iOS. No other app's
source tree is referenced.

```swift
import ResponseText

RenderedResponse(markdown)
    .markdownTheme(appResponseTheme)
    .markdownSelectionColor(appAccent)
    .onMarkdownSelectionChanged { active in
        // Pause the containing conversation's automatic scroll-to-bottom.
        isInteractingWithResponse = active
    }
```

Use a single view per response inside the conversation's vertical scroll view.
Do not add a competing long-press/context-menu gesture to the containing row.
Keep the view's identity stable during streaming. Propagate interaction state
from all response rows (for example, an OR-reduced SwiftUI preference), and
follow the tail again only if the user was already at the bottom. The renderer
holds text and its Markdown copy source together while either menu/selection
stage is active; the host should also observe asynchronous height changes.

Long press opens message actions in the style the host picks with
`.markdownMessageMenuStyle`. The default `.contextMenu` is the system menu with
**Copy**, **Copy as Markdown** and **Select Text**. `.actionsOverlay` shows the
frozen response above **Copy**, **Select** and **Share**; hosts can provide
`MarkdownMessageActions` through `.markdownMessageActions` to add **Reply** and an
upper 👍 / 👎 strip, with asynchronous load/save closures.
The renderer shows confirmed feedback only and keeps retry IDs for failed saves.
Tapping outside the cards dismisses the menu, including the empty space beside
the action list and between cards. Layout containers must not intercept those taps.
Copy exports the whole rendered response without selecting it. Select closes
the message menu and starts native selection at the pressed paragraph. The
selection menu offers **Copy**, **Select All**, and **More** for format-specific
copy actions; `.markdownSelectionAction` puts one host action before Copy. Copying or tapping elsewhere ends selection. A fresh long press
opens message actions again, even if the previous selection was abandoned.
Only dragging a selection handle continues the current selection. Tables and formulas are atomic; dragging a handle can cross them
and scroll the conversation. VoiceOver exposes Copy Response and Select Text, and Message actions in the overlay style.

The `MarkdownTheme` API configures paragraph/list leading, heading sizes, colors,
code/table surfaces and formula styles. Host adapters must use their own tokens;
no Impo or Rebyte theme, authentication, API or business model is imported here.

## Copy checklist

- Preserve `LICENSE`, `LICENSE.impo`, `UPSTREAM.md`, and the MIT notices in parser/SVG sources.
- Bundle the notices in the consuming app.
- Check both menu stages, repeated long presses, outside-tap dismissal, full and partial copy, wide tables, tall
  formulas, links, streaming and long conversations at normal/large text sizes.
- Confirm physical-device gesture behavior through TestFlight.

See `UPSTREAM.md` for provenance and local changes. MathJaxSwift and SwiftDraw
retain their own dependency licenses and resources.
