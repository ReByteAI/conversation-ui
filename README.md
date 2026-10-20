# ConversationUI

The shared SwiftUI conversation viewport for Impo and Rebyte (iOS 18+, macOS 15+).
The source of truth is [ReByteAI/conversation-ui](https://github.com/ReByteAI/conversation-ui).
Both applications depend on this repository at a pinned Git revision. Do not copy
the implementation into either app. After changing the component, test both apps
and update their dependency revisions together.

`ConversationScrollView` owns content measurement, bottom following, user-scroll
state, selection pauses and unread counts. Each app supplies message rows, its
composer and the return-to-latest control. Message rendering and product styling
remain outside this package.

The column uses `VStack`, not `LazyVStack`. Markdown, tables and charts change
height after rendering; estimated lazy extents can move the viewport beyond the
last row. One `ScrollPosition` follows the measured bottom after layout updates.
Content growth does not count as a user scroll. Dragging pauses following; reaching
the actual bottom (within one point of rounding) or invoking the supplied action resumes it.
A small upward drag must stay in history after release; proximity to the tail
does not resume following. No delay-based grace period
or simultaneous top-ID position competes with bottom following.

Pass stable message IDs and selection state. Supply `scrollRequest` when a composer
must explicitly return to the latest message. Keep lazy containers out of the
content builder. Page history on actual row visibility (`onScrollVisibilityChange`),
not `onAppear`: eager measurement creates offscreen rows. The apps own history
paging and prepend-position restoration. This intentionally trades lazy rendering
for correct measured heights; very long loaded histories still need profiling.

Validation:

- Run `swift test` in this repository for follow state and unread counting.
- In the Impo checkout: `IMPO_IOS_TEST_CLASS=InstantNativeTests/ConversationScrollingTests npm run test:ios:app -- --simulator <UDID>` — native hosted-view layout checks for append/resize, tab restoration, selection and offscreen pagination.
- Build Rebyte after resolving its pinned remote dependency.

The native checks use a unit-test host and real SwiftUI/UIScrollView layout, without
an XCUITest driver or account. They do not substitute for physical-device testing.

## Swift Package Manager

Add `https://github.com/ReByteAI/conversation-ui.git` and the `ConversationUI`
library product to your app. The package has no third-party dependencies.
It requires Swift 6, iOS 18 or macOS 15.

## Origin and license

Extracted without source changes from Impo's ConversationUI component on
2026-10-19. Original source commit: `6acbe85bc298c03571f1878a81618668e1d7825f`.
MIT licensed; the original Impo contributor notice is preserved in `LICENSE`.
