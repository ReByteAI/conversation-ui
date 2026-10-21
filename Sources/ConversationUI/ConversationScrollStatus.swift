import SwiftUI

/// Messages appended while reading history count once. Prepends and token updates do not.
public struct ConversationUnreadTracker {
    private var previous: [String] = []
    public private(set) var unread: Set<String> = []
    public init() {}

    public mutating func update(_ ids: [String], following: Bool) {
        defer { previous = ids }
        guard !following else { unread = []; return }
        guard let tail = previous.last, let index = ids.firstIndex(of: tail) else {
            unread = []; return
        }
        let known = Set(previous)
        unread.formIntersection(ids)
        unread.formUnion(ids.dropFirst(index + 1).filter { !known.contains($0) })
    }

    public mutating func markRead() { unread = [] }
}

public struct ConversationScrollStatus: Equatable {
    public let isFollowing: Bool
    public let isAtBottom: Bool
    public let unreadCount: Int
    public var showsReturnToLatest: Bool { !isFollowing && !isAtBottom }
}

struct ConversationFollowState {
    private(set) var following = true
    private(set) var atBottom = true
    static func isAtBottom(_ distanceFromBottom: CGFloat) -> Bool {
        // Tolerate layout rounding, not a reader who stopped slightly above the tail.
        distanceFromBottom <= 1
    }
    mutating func measured(atBottom: Bool) { self.atBottom = atBottom }
    mutating func beganReading() { following = false }
    mutating func finishedScrolling() { following = atBottom }
    mutating func followLatest() { following = true }
}
