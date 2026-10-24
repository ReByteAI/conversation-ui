# ConversationUI

The shared SwiftUI conversation viewport for Impo and Rebyte (iOS 18+, macOS 15+).
The source of truth is [ReByteAI/conversation-ui](https://github.com/ReByteAI/conversation-ui).
Both applications depend on this repository at a pinned Git revision. Do not copy
the implementation into either app. After changing the component, test both apps
and update their dependency revisions together.

`ConversationList` owns row placement, bottom following, user-scroll state,
selection pauses and unread counts. Each app supplies its rows (`ConversationListRow`),
its composer and the return-to-latest control. Product styling remains outside this
package.

`ResponseText` (iOS only) is the response renderer both apps show replies with:
Markdown through MD4C, math, tables, native selection and message actions. Each app
applies its own theme and picks its message-menu style; see
[Sources/ResponseText/README.md](Sources/ResponseText/README.md) and
[UPSTREAM.md](Sources/ResponseText/UPSTREAM.md). It needs UIKit, so run this package's
tests on an iOS simulator:

```sh
xcodebuild test -scheme ConversationUI-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The design follows Telegram's chat list (iOS 18+ only; macOS has no list yet):

- Only rows within 600 pt of the viewport are alive; rows beyond 1,400 pt are
  released. Memory depends on the screen, not on the conversation length.
- Each row is a separate `UIHostingController`. Its height is measured when it
  renders and cached; an unrendered row keeps the estimate it first got (the mean
  measured height) until it renders.
- One anchor rule handles every change: before a pass the list records the row the
  reader is looking at (or the bottom, while following); after heights, inserts or
  prepends are applied, it moves the content offset so that row is where it was.
  Height changes above the viewport therefore never move what the reader sees.
- Rows outside the viewport are built at most two per frame; visible rows are built
  at once.
- Preferences do not cross the hosting boundary: forward row state (such as text
  selection) through closures, and pass `isInteracting` to pause following.
- `onReachTop` fires once the oldest row is within the preload distance, once per
  set of rows, so the next history page loads before the reader arrives.

Dragging pauses following; reaching the actual bottom (within one point of rounding)
or invoking the supplied action resumes it. A small upward drag must stay in history
after release; proximity to the tail does not resume following. No delay-based grace
period.

Validation:

- Run the package tests on an iOS simulator (command above): geometry, follow state,
  unread counting and the response renderer.
- In the Impo checkout: `IMPO_IOS_TEST_CLASS=InstantNativeTests/ConversationScrollingTests npm run test:ios:app -- --simulator <UDID>` — hosted-view checks for append/resize, tab restoration, selection, history paging, prepend and resize anchoring, and a 3,000-row list that keeps fewer than 60 rows alive.
- In the Impo checkout, a Debug build launched with `--scroll-soak <file>` scrolls the main chat through its whole history and back, writing the memory footprint every half second.
- Build Rebyte after resolving its pinned remote dependency.

The native checks use a unit-test host and real UIKit layout, without an XCUITest
driver or account. They do not substitute for physical-device testing.

## Swift Package Manager

Add `https://github.com/ReByteAI/conversation-ui.git` and the `ConversationUI`
library product to your app. The package has no third-party dependencies.
It requires Swift 6, iOS 18 or macOS 15.

## Origin and license

Extracted without source changes from Impo's ConversationUI component on
2026-10-19. Original source commit: `6acbe85bc298c03571f1878a81618668e1d7825f`.
MIT licensed; the original Impo contributor notice is preserved in `LICENSE`.
The list design is modeled on Telegram iOS's `ListView`; no Telegram code is used.
