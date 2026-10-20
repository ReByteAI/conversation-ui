import XCTest
@testable import ConversationUI

final class ConversationStateTests: XCTestCase {
    func testLayoutGrowthDoesNotCountAsAUserScroll() {
        var state = ConversationFollowState()
        state.measured(atBottom: ConversationFollowState.isAtBottom(100))
        XCTAssertTrue(state.following)
        state.beganReading()
        state.measured(atBottom: ConversationFollowState.isAtBottom(100))
        state.finishedScrolling()
        XCTAssertFalse(state.following)
        state.measured(atBottom: ConversationFollowState.isAtBottom(0))
        state.finishedScrolling()
        XCTAssertTrue(state.following)
    }

    func testSmallUpwardScrollDoesNotResumeFollowingOnRelease() {
        for distance: CGFloat in [2, 10, 24, 39, 40, 80] {
            var state = ConversationFollowState()
            state.beganReading()
            state.measured(atBottom: ConversationFollowState.isAtBottom(distance))
            state.finishedScrolling()
            XCTAssertFalse(state.following, "Must preserve reading position even just \(distance) points above the bottom")
            // A new reply/layout pass must not restart following either.
            state.measured(atBottom: ConversationFollowState.isAtBottom(distance + 100))
            XCTAssertFalse(state.following)
            state.measured(atBottom: ConversationFollowState.isAtBottom(0))
            state.finishedScrolling()
            XCTAssertTrue(state.following)
        }
    }

    func testBottomRoundingAndRubberBandingStillResumeFollowing() {
        for distance: CGFloat in [-20, 0, 0.5, 1] {
            var state = ConversationFollowState()
            state.beganReading()
            state.measured(atBottom: ConversationFollowState.isAtBottom(distance))
            state.finishedScrolling()
            XCTAssertTrue(state.following)
        }
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
