import XCTest
@testable import ConversationUI

final class ConversationListGeometryTests: XCTestCase {
    private func geometry(_ heights: [CGFloat], viewport: CGFloat = 500) -> ConversationListGeometry {
        var geometry = ConversationListGeometry()
        geometry.ids = heights.indices.map { "m\($0)" }
        for (index, height) in heights.enumerated() {
            geometry.heights["m\(index)"] = height
            geometry.measured.insert("m\(index)")
        }
        geometry.spacing = 10
        geometry.top = 8
        geometry.bottom = 24
        geometry.rebuild(viewport: viewport)
        return geometry
    }

    func testRowsStackWithSpacingAndPadding() {
        let geometry = geometry([100, 200, 300])
        XCTAssertEqual(geometry.tops, [8, 118, 328])
        XCTAssertEqual(geometry.contentHeight, 8 + 620 + 24)
    }

    func testShortConversationSitsAgainstTheBottom() {
        let geometry = geometry([100], viewport: 500)
        XCTAssertEqual(geometry.contentHeight, 500)
        XCTAssertEqual(geometry.tops, [500 - 24 - 100])
    }

    func testGrowthAboveTheViewportKeepsTheReadRowStill() {
        var geometry = geometry(Array(repeating: 100, count: 50))
        let offset: CGFloat = 2000
        let anchor = geometry.anchor(offset: offset, viewport: 500, following: false)
        guard case let .row(id, _) = anchor else { return XCTFail("Expected a row anchor") }
        let before = geometry.tops[geometry.index(of: id)!] - offset
        // A row far above renders taller than its estimate.
        geometry.heights["m3"] = 400
        geometry.rebuild(viewport: 500)
        let restored = geometry.offset(for: anchor, viewport: 500, fallback: offset)
        XCTAssertEqual(geometry.tops[geometry.index(of: id)!] - restored, before)
        XCTAssertEqual(restored, offset + 300)
    }

    func testPrependKeepsTheReadRowStill() {
        var geometry = geometry(Array(repeating: 100, count: 20))
        let offset: CGFloat = 450
        let anchor = geometry.anchor(offset: offset, viewport: 500, following: false)
        geometry.ids = (0..<30).map { "old\($0)" } + geometry.ids
        geometry.rebuild(viewport: 500)
        let restored = geometry.offset(for: anchor, viewport: 500, fallback: offset)
        XCTAssertEqual(restored, offset + 30 * 110, accuracy: 0.01)
    }

    func testFollowingPinsTheBottom() {
        var geometry = geometry(Array(repeating: 100, count: 20))
        let anchor = geometry.anchor(offset: 1000, viewport: 500, following: true)
        XCTAssertEqual(anchor, .bottom)
        geometry.heights["m19"] = 600
        geometry.rebuild(viewport: 500)
        XCTAssertEqual(geometry.offset(for: anchor, viewport: 500, fallback: 0), geometry.contentHeight - 500)
    }

    func testRangeIsContiguousAndBounded() {
        let geometry = geometry(Array(repeating: 100, count: 100))
        XCTAssertEqual(geometry.range(minY: 1000, maxY: 1500), 9..<14)
        XCTAssertEqual(geometry.range(minY: -500, maxY: 0), 0..<0)
        XCTAssertEqual(geometry.range(minY: 100_000, maxY: 100_500), 0..<0)
    }

    func testUnmeasuredRowsUseTheMeanMeasuredHeight() {
        var geometry = geometry([100, 300])
        geometry.ids.append("new")
        geometry.rebuild(viewport: 500)
        XCTAssertEqual(geometry.height("new"), 200)
    }
}
