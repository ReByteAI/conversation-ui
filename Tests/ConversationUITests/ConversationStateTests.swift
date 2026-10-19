import XCTest
@testable import ConversationUI

final class ConversationStateTests: XCTestCase {
    func testLayoutGrowthDoesNotCountAsAUserScroll() {
        var state = ConversationFollowState()
        state.measured(atBottom: false)
        XCTAssertTrue(state.following)
        state.beganReading()
        state.measured(atBottom: false)
        state.finishedScrolling()
        XCTAssertFalse(state.following)
        state.measured(atBottom: true)
        state.finishedScrolling()
        XCTAssertTrue(state.following)
    }

    func testExplicitReturnResumesFollowing() {
        var state = ConversationFollowState()
        state.beganReading()
        state.followLatest()
        XCTAssertTrue(state.following)
    }

    func testOnlyAppendedMessagesCountWhileReadingHistory() {
        var tracker = ConversationUnreadTracker()
        tracker.update(["3", "4"], following: true)
        tracker.update(["1", "2", "3", "4"], following: false)
        XCTAssertTrue(tracker.unread.isEmpty)
        tracker.update(["1", "2", "3", "4", "5"], following: false)
        tracker.update(["1", "2", "3", "4", "5"], following: false)
        XCTAssertEqual(tracker.unread, ["5"])
        tracker.update(["new-conversation"], following: false)
        XCTAssertTrue(tracker.unread.isEmpty)
    }
}
