# Shared response renderer

Impo and Rebyte iOS both render replies with this one copy (product `ResponseText` of
this package). It replaced the two copies each app vendored from 2026-10-07 on.

Source: https://github.com/software-mansion-labs/enriched-markdown-ios
Version: 0.3.0
Commit: b5e6da71d9197842b242e4a0096d63d249bf364a
Imported: 2026-10-07
License: MIT; see LICENSE. MD4C keeps its copyright and MIT license in core/md4c.

The Swift renderer (this directory) and the C++ parser shim and MD4C source
(`Sources/EnrichedMarkdownCppShim`) are compiled from this package. No remote Enriched
Markdown package or RaTeX binary is used. The targets build in Swift 5 language mode
and C++17, isolated from the Swift 6 applications.

Local adaptations:
- Compile the core and math source together; replace package access with internal.
- Include an offline MathJax/SwiftDraw adapter and MIT SVG geometry helpers from LaTeXSwiftUI.
- Keep normalization, rendering and interactions in this copyable source directory.
- Show whole-message actions first; Select Text enters native range selection.
- Freeze rendered content and copy source together while a native selection is active.
- Add selection-state reporting and edge scrolling in the enclosing conversation.
- Exit abandoned selections on outside taps and fresh body touches; keep handle drags active. Anchor the compact selection menu around selected lines.
- Restore equation source in plain/HTML copy, including equations inside table cells.
- Accept only web/mail/telephone links and HTTP(S) image destinations.
- Preserve paragraph leading while indenting lists, space list items and retain
  continued paragraphs without duplicate markers; restore enclosing block styles.
- MD4C: a table may directly follow paragraph text (as in GFM); the paragraph's last line
  with a pipe becomes the header (`md_last_block_line_has_pipe`).
- Let table rows expand for tall math, and apply heading margins without fake lines.
- Keep Debug-only observation hooks for UI acceptance tests.
- Host options, each off or unchanged unless a host sets it:
  - `markdownMessageMenuStyle`: `.contextMenu` (default; Copy, Copy as Markdown, Select
    Text; Rebyte) or `.actionsOverlay` (Copy, Select, Share plus `MarkdownMessageActions`
    Reply and feedback, `MarkdownMessageHandle`; Impo).
  - `markdownSelectionAction`: one host action first in the selection menu with the
    selected rendered text (Rebyte's Ask Rebyte).
  - `Link().customURLs` + `onCustomLinkPress`, `onMarkdownBlockquoteFrames`,
    `Blockquote().trailingInset`, `markdownReadableSuffix` (Impo's reply parts).
  - `MarkdownMenuIcons.imageProvider` (Impo's Lucide artwork; system symbols otherwise).
- Size images, tables and formulas for the largest connected screen (iPhone Duo).
- Render a row's first document synchronously so lazy conversation rows have their
  real height on first layout; later updates stay asynchronous.

Host styling and conversation scroll coordination remain in each app's adapter. Source updates must revalidate native selection, copying, streaming,
Dynamic Type, horizontal tables, math baselines and chat scrolling.
