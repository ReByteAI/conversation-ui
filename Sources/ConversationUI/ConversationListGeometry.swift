import CoreGraphics

/// Row positions of a conversation list, in content coordinates.
///
/// Every row has one height: measured once it has rendered, an estimate before.
/// The list never positions a row from SwiftUI's own layout; it places rows from
/// these heights and keeps the reader still with `Anchor` when any height changes.
struct ConversationListGeometry: Equatable {
    var ids: [String] = []
    var heights: [String: CGFloat] = [:]
    var measured: Set<String> = []
    var spacing: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    /// Space above the first row so a short conversation sits against the bottom.
    var fill: CGFloat = 0
    private(set) var tops: [CGFloat] = []
    private(set) var contentHeight: CGFloat = 0
    private var indices: [String: Int] = [:]

    /// A point in the conversation the reader must not see move.
    enum Anchor: Equatable {
        /// The newest edge: the bottom of the content stays at the bottom of the viewport.
        case bottom
        /// A row's top edge stays at the same distance from the viewport top.
        case row(id: String, offset: CGFloat)
    }

    /// The mean measured height, for rows that have not rendered yet. Updated by `rebuild`.
    private(set) var estimate: CGFloat = 120

    func height(_ id: String) -> CGFloat { heights[id] ?? estimate }
    func index(of id: String) -> Int? { indices[id] }
    func frame(_ index: Int) -> (minY: CGFloat, height: CGFloat) { (tops[index], height(ids[index])) }

    /// Recompute every row's top from the heights. Callers do this once per pass.
    mutating func rebuild(viewport: CGFloat) {
        let known = measured.compactMap { heights[$0] }
        estimate = known.isEmpty ? 120 : known.reduce(0, +) / CGFloat(known.count)
        indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var rows: CGFloat = 0
        var tops: [CGFloat] = []
        tops.reserveCapacity(ids.count)
        for (index, id) in ids.enumerated() {
            if index > 0 { rows += spacing }
            tops.append(rows)
            // A row keeps the estimate it first got until it is measured; later measurements
            // elsewhere must not move rows the reader has not reached.
            if heights[id] == nil { heights[id] = estimate }
            rows += heights[id]!
        }
        fill = max(0, viewport - top - bottom - rows)
        self.tops = tops.map { $0 + top + fill }
        contentHeight = top + fill + rows + bottom
    }

    /// The largest content offset, for a viewport of `viewport` points.
    func maximumOffset(viewport: CGFloat) -> CGFloat { max(0, contentHeight - viewport) }

    /// The anchor that describes what the reader sees at `offset`.
    func anchor(offset: CGFloat, viewport: CGFloat, following: Bool) -> Anchor {
        if following { return .bottom }
        // The first row whose bottom is below the viewport top is the one the reader reads.
        guard let index = firstIndex(below: offset) else { return .bottom }
        return .row(id: ids[index], offset: tops[index] - offset)
    }

    /// The content offset that puts `anchor` back where the reader saw it.
    func offset(for anchor: Anchor, viewport: CGFloat, fallback: CGFloat) -> CGFloat {
        switch anchor {
        case .bottom:
            return maximumOffset(viewport: viewport)
        case let .row(id, offset):
            guard let index = indices[id] else { return min(fallback, maximumOffset(viewport: viewport)) }
            return min(max(0, tops[index] - offset), maximumOffset(viewport: viewport))
        }
    }

    /// Rows that intersect `minY..<maxY`, as one contiguous range.
    func range(minY: CGFloat, maxY: CGFloat) -> Range<Int> {
        guard !ids.isEmpty, let first = firstIndex(below: minY) else { return 0..<0 }
        var last = first
        while last + 1 < ids.count, tops[last + 1] < maxY { last += 1 }
        return tops[first] < maxY ? first..<(last + 1) : first..<first
    }

    /// The first row whose bottom edge is below `y`.
    private func firstIndex(below y: CGFloat) -> Int? {
        var low = 0, high = ids.count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] + height(ids[middle]) <= y { low = middle + 1 } else { high = middle }
        }
        return low < ids.count ? low : nil
    }
}
