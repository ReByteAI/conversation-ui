#if canImport(UIKit)
import SwiftUI
import UIKit

/// One row of a `ConversationList`: a message, a separator, a status line.
public struct ConversationListRow: Identifiable {
    public let id: String
    /// Changes when the row's content changes while it is off screen, so its height is measured again.
    public let revision: AnyHashable
    public let content: AnyView

    public init<Content: View>(id: String, revision: AnyHashable = 0, @ViewBuilder content: () -> Content) {
        self.id = id
        self.revision = revision
        self.content = AnyView(content())
    }
}

/// A request to show `id` at the top of the list instead of following the latest row.
/// A new `request` value asks again; the list waits until a row with that id exists.
public struct ConversationListReveal: Equatable {
    public let id: String
    public let request: Int
    public init(id: String, request: Int) { self.id = id; self.request = request }
}

/// A conversation column that keeps only the rows near the viewport alive.
///
/// The design follows Telegram's chat list: every row has an exact height once it
/// has rendered, rows far from the viewport are released, and any change in height,
/// insertion or prepend keeps the row the reader is looking at still (or the bottom,
/// while following the latest message). Memory therefore depends on the screen,
/// not on the length of the conversation.
public struct ConversationList<Accessory: View>: View {
    private let rows: [ConversationListRow]
    private let enabled: Bool
    private let isInteracting: Bool
    private let scrollRequest: Int
    private let spacing: CGFloat
    private let padding: EdgeInsets
    private let maximumWidth: CGFloat
    private let onReachTop: () -> Void
    private let reveal: ConversationListReveal?
    private let onVisibleRows: ([String]) -> Void
    private let accessory: (ConversationScrollStatus, @escaping () -> Void) -> Accessory
    @State private var status = ConversationScrollStatus(isFollowing: true, isAtBottom: true, unreadCount: 0)
    @State private var followRequests = 0

    public init(rows: [ConversationListRow], enabled: Bool = true, isInteracting: Bool = false,
                scrollRequest: Int = 0, spacing: CGFloat = 0, padding: EdgeInsets = EdgeInsets(),
                maximumWidth: CGFloat = .infinity, onReachTop: @escaping () -> Void = {},
                reveal: ConversationListReveal? = nil, onVisibleRows: @escaping ([String]) -> Void = { _ in },
                @ViewBuilder accessory: @escaping (ConversationScrollStatus, @escaping () -> Void) -> Accessory) {
        self.rows = rows
        self.enabled = enabled
        self.isInteracting = isInteracting
        self.scrollRequest = scrollRequest
        self.spacing = spacing
        self.padding = padding
        self.maximumWidth = maximumWidth
        self.onReachTop = onReachTop
        self.reveal = reveal
        self.onVisibleRows = onVisibleRows
        self.accessory = accessory
    }

    public var body: some View {
        ConversationListRepresentable(rows: rows, enabled: enabled, isInteracting: isInteracting,
            followRequest: scrollRequest + followRequests, spacing: spacing, padding: padding,
            maximumWidth: maximumWidth, onReachTop: onReachTop, reveal: reveal, onVisibleRows: onVisibleRows) { status = $0 }
            .overlay(alignment: .bottom) { accessory(status) { followRequests += 1 } }
    }
}

private struct ConversationListRepresentable: UIViewControllerRepresentable {
    let rows: [ConversationListRow]
    let enabled: Bool
    let isInteracting: Bool
    let followRequest: Int
    let spacing: CGFloat
    let padding: EdgeInsets
    let maximumWidth: CGFloat
    let onReachTop: () -> Void
    let reveal: ConversationListReveal?
    let onVisibleRows: ([String]) -> Void
    let onStatus: (ConversationScrollStatus) -> Void

    func makeUIViewController(context: Context) -> ConversationListController { ConversationListController() }

    func updateUIViewController(_ controller: ConversationListController, context: Context) {
        controller.onReachTop = onReachTop
        controller.onStatus = onStatus
        controller.onVisibleRows = onVisibleRows
        controller.update(rows: rows, environment: context.environment, style: .init(spacing: spacing,
            padding: padding, maximumWidth: maximumWidth), enabled: enabled, isInteracting: isInteracting,
            followRequest: followRequest, reveal: reveal)
    }
}

/// The environment and the reporting closure a hosted row needs.
private struct ConversationListRowRoot: View {
    var content: AnyView
    var environment: EnvironmentValues
    var style: ConversationListController.Style
    var report: (CGFloat) -> Void

    var body: some View {
        content
            .frame(maxWidth: style.maximumWidth, alignment: .leading)
            .padding(.leading, style.padding.leading)
            .padding(.trailing, style.padding.trailing)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { report($0) }
            .environment(\.self, environment)
    }
}

@MainActor final class ConversationListController: UIViewController, UIScrollViewDelegate {
    struct Style: Equatable {
        var spacing: CGFloat
        var padding: EdgeInsets
        var maximumWidth: CGFloat
    }

    private final class Row {
        let host: UIHostingController<ConversationListRowRoot>
        var revision: AnyHashable
        init(host: UIHostingController<ConversationListRowRoot>, revision: AnyHashable) {
            self.host = host
            self.revision = revision
        }
    }

    /// Rows within this distance of the viewport stay alive; the next screen renders before it is seen.
    private static let preload: CGFloat = 600
    /// Rows are released only beyond this distance, so a small scroll back does not rebuild them.
    private static let retain: CGFloat = 1400
    /// Rows outside the viewport are built at most this many per frame, to keep scrolling at full rate.
    private static let buildsPerFrame = 2

    var onReachTop: () -> Void = {}
    var onStatus: (ConversationScrollStatus) -> Void = { _ in }
    var onVisibleRows: ([String]) -> Void = { _ in }

    private let scroll = UIScrollView()
    private var geometry = ConversationListGeometry()
    private var content: [String: ConversationListRow] = [:]
    private var live: [String: Row] = [:]
    private var environment = EnvironmentValues()
    private var style = Style(spacing: 0, padding: EdgeInsets(), maximumWidth: .infinity)
    private var width: CGFloat = 0
    private var enabled = true
    private var isInteracting = false
    private var followRequest = 0
    private var revealed: Int?
    private var visibleRows: [String] = []
    private var follow = ConversationFollowState()
    private var unread = ConversationUnreadTracker()
    private var reported: ConversationScrollStatus?
    /// The rows the reader had when the top was last reached; reaching it again with the same rows does nothing.
    private var reachedTopFor: String?
    private var applying = false
    private var pending = false
    private var displayLink: CADisplayLink?

    override func loadView() {
        scroll.delegate = self
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.keyboardDismissMode = .interactive
        scroll.contentInsetAdjustmentBehavior = .always
        scroll.backgroundColor = .clear
        view = scroll
    }

    // MARK: Inputs

    func update(rows: [ConversationListRow], environment: EnvironmentValues, style: Style, enabled: Bool,
                isInteracting: Bool, followRequest: Int, reveal: ConversationListReveal? = nil) {
        var anchor = currentAnchor()
        self.environment = environment
        if self.style != style {
            self.style = style
            invalidateMeasurements()
        }
        self.enabled = enabled
        self.isInteracting = isInteracting
        let ids = rows.map(\.id)
        if ids != geometry.ids {
            for id in Set(geometry.ids).subtracting(ids) { release(id); geometry.heights[id] = nil; geometry.measured.remove(id) }
            unread.update(ids, following: follow.following || !enabled)
        }
        for row in rows {
            if let previous = content[row.id], previous.revision != row.revision, live[row.id] == nil {
                geometry.measured.remove(row.id)
            }
        }
        content = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        geometry.ids = ids
        for (id, row) in live {
            guard let next = content[id] else { continue }
            row.revision = next.revision
            row.host.rootView = root(for: next)
        }
        if followRequest != self.followRequest {
            self.followRequest = followRequest
            follow.followLatest()
            unread.markRead()
        }
        if let reveal, reveal.request != revealed, ids.contains(reveal.id) {
            // Stop following and read from the requested row, as if the reader had scrolled there.
            revealed = reveal.request
            follow.beganReading()
            follow.measured(atBottom: false)
            anchor = .row(id: reveal.id, offset: 0)
        }
        // Following may resume in this update (selection ended, search cleared, a follow request).
        relayout(anchor: canFollow ? .bottom : anchor)
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let anchor = currentAnchor()
        if scroll.bounds.width != width {
            width = scroll.bounds.width
            invalidateMeasurements()
        }
        relayout(anchor: anchor)
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        // The keyboard or composer changed the visible area; keep the same row (or the bottom) in view.
        relayout(anchor: currentAnchor())
    }

    private var viewport: CGFloat { scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom }
    /// The content offset in list coordinates: 0 is the top of the first row's area.
    private var offset: CGFloat { scroll.contentOffset.y + scroll.adjustedContentInset.top }

    private func currentAnchor() -> ConversationListGeometry.Anchor {
        guard !geometry.tops.isEmpty, width > 0 else { return .bottom }
        return geometry.anchor(offset: offset, viewport: viewport, following: canFollow)
    }

    private var canFollow: Bool { follow.following && enabled && !isInteracting }

    private func invalidateMeasurements() {
        // Keep the old heights as estimates until each row renders at the new width.
        geometry.measured.removeAll()
    }

    /// One layout pass: place rows, render the ones near the viewport, then restore `anchor`.
    private func relayout(anchor: ConversationListGeometry.Anchor) {
        guard width > 0, !applying else { return }
        applying = true
        defer { applying = false }
        geometry.spacing = style.spacing
        geometry.top = style.padding.top
        geometry.bottom = style.padding.bottom
        var budget = Self.buildsPerFrame
        var unfinished = false
        // Building a row can change its height; settle within a few passes, each restoring the anchor.
        for _ in 0..<4 {
            geometry.rebuild(viewport: viewport)
            apply(anchor: anchor)
            let changed = materialize(budget: &budget, unfinished: &unfinished)
            if !changed { break }
        }
        place()
        release()
        reportStatus()
        if unfinished { scheduleBuild() }
    }

    private func apply(anchor: ConversationListGeometry.Anchor) {
        scroll.contentSize = CGSize(width: width, height: geometry.contentHeight)
        let target = geometry.offset(for: anchor, viewport: viewport, fallback: offset)
        if abs(target - offset) > 0.25 {
            // Moving the bounds keeps an ongoing deceleration; only the content under it shifts.
            scroll.contentOffset.y = target - scroll.adjustedContentInset.top
        }
    }

    /// Builds rows near the viewport. Returns true when a measured height changed the geometry.
    private func materialize(budget: inout Int, unfinished: inout Bool) -> Bool {
        let visible = geometry.range(minY: offset, maxY: offset + viewport)
        let wanted = geometry.range(minY: offset - Self.preload, maxY: offset + viewport + Self.preload)
        var changed = false
        // Visible rows first, then the rest outward, so the screen fills before the margins.
        let order = Array(visible) + wanted.filter { !visible.contains($0) }
            .sorted { distance($0, from: visible) < distance($1, from: visible) }
        for index in order {
            let id = geometry.ids[index]
            if live[id] == nil {
                if !visible.contains(index) {
                    guard budget > 0 else { unfinished = true; continue }
                    budget -= 1
                }
                build(id)
            }
            if !geometry.measured.contains(id), let row = live[id] {
                let size = row.host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                changed = setHeight(ceil(size.height), for: id) || changed
            }
        }
        return changed
    }

    private func distance(_ index: Int, from range: Range<Int>) -> Int {
        index < range.lowerBound ? range.lowerBound - index : index - range.upperBound
    }

    @discardableResult
    private func setHeight(_ height: CGFloat, for id: String) -> Bool {
        geometry.measured.insert(id)
        guard abs((geometry.heights[id] ?? -1) - height) > 0.5 else { return false }
        geometry.heights[id] = height
        return true
    }

    private func build(_ id: String) {
        guard let row = content[id] else { return }
        let host = UIHostingController(rootView: root(for: row))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
        live[id] = Row(host: host, revision: row.revision)
    }

    private func root(for row: ConversationListRow) -> ConversationListRowRoot {
        let id = row.id
        return ConversationListRowRoot(content: row.content, environment: environment, style: style) { [weak self] height in
            self?.reported(height, for: id)
        }
    }

    private func place() {
        for (id, row) in live {
            guard let index = geometry.index(of: id) else { continue }
            let frame = geometry.frame(index)
            let target = CGRect(x: 0, y: frame.minY, width: width, height: frame.height)
            if row.host.view.frame != target { row.host.view.frame = target }
        }
    }

    private func release() {
        let keep = geometry.range(minY: offset - Self.retain, maxY: offset + viewport + Self.retain)
        for id in Array(live.keys) {
            guard let index = geometry.index(of: id), keep.contains(index) else { release(id); continue }
        }
    }

    private func release(_ id: String) {
        guard let row = live.removeValue(forKey: id) else { return }
        row.host.willMove(toParent: nil)
        row.host.view.removeFromSuperview()
        row.host.removeFromParent()
    }

    /// A rendered row changed height (Markdown finished, an image loaded, text streamed in).
    private func reported(_ height: CGFloat, for id: String) {
        guard live[id] != nil, height > 0 else { return }
        let measuredHeight = ceil(height)
        guard abs((geometry.heights[id] ?? -1) - measuredHeight) > 0.5 || !geometry.measured.contains(id) else { return }
        reportedHeights[id] = measuredHeight
        guard !pending else { return }
        pending = true
        // Several rows may report in one SwiftUI update; apply them together in the next pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending = false
            // Capture what the reader sees with the old heights, then apply the new ones.
            let anchor = currentAnchor()
            for (id, height) in reportedHeights where live[id] != nil { setHeight(height, for: id) }
            reportedHeights.removeAll()
            relayout(anchor: anchor)
        }
    }

    private var reportedHeights: [String: CGFloat] = [:]

    private func scheduleBuild() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(buildMore))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func buildMore() {
        displayLink?.invalidate()
        displayLink = nil
        relayout(anchor: currentAnchor())
    }

    // MARK: Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !applying else { return }
        relayout(anchor: currentAnchor())
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        follow.beganReading()
        reportStatus()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishedScrolling() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishedScrolling() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { finishedScrolling() }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { false }

    private func finishedScrolling() {
        follow.measured(atBottom: isAtBottom)
        follow.finishedScrolling()
        if follow.following { unread.markRead() }
        reportStatus()
    }

    private var isAtBottom: Bool {
        ConversationFollowState.isAtBottom(geometry.maximumOffset(viewport: viewport) - offset)
    }

    private func reportStatus() {
        // Rows placed in this pass only; before the first layout there are none.
        let visible = geometry.tops.count == geometry.ids.count ? geometry.range(minY: offset, maxY: offset + viewport).map { geometry.ids[$0] } : []
        if visible != visibleRows {
            visibleRows = visible
            let onVisibleRows = onVisibleRows
            DispatchQueue.main.async { onVisibleRows(visible) }
        }
        if isAtBottom, follow.following { unread.markRead() }
        let status = ConversationScrollStatus(isFollowing: follow.following, isAtBottom: isAtBottom,
            unreadCount: unread.unread.count)
        if status != reported {
            reported = status
            let onStatus = onStatus
            // Status is SwiftUI state; never write it inside SwiftUI's own update.
            DispatchQueue.main.async { onStatus(status) }
        }
        let rows = "\(geometry.ids.count)|\(geometry.ids.first ?? "")"
        // The oldest row is built within the preload distance, so the next page loads before the reader arrives.
        if let first = geometry.ids.first, reachedTopFor != rows, live[first] != nil {
            reachedTopFor = rows
            let onReachTop = onReachTop
            DispatchQueue.main.async { onReachTop() }
        }
    }
}
#endif
