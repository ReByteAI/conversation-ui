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

public struct ConversationScrollStatus {
    public let isFollowing: Bool
    public let isAtBottom: Bool
    public let unreadCount: Int
    public var showsReturnToLatest: Bool { !isFollowing && !isAtBottom }
}

struct ConversationFollowState {
    private(set) var following = true
    private(set) var atBottom = true
    mutating func measured(atBottom: Bool) { self.atBottom = atBottom }
    mutating func beganReading() { following = false }
    mutating func finishedScrolling() { following = atBottom }
    mutating func followLatest() { following = true }
}

private struct ConversationGeometry: Equatable {
    let content: CGSize
    let container: CGSize
    let bottomInset: CGFloat
    let atBottom: Bool
}

/// A measured conversation column shared by Impo and Rebyte.
///
/// Deliberately uses VStack: native Markdown, tables and charts change height
/// after rendering. LazyVStack's estimated extent can put its tail outside the
/// visible content and leave a blank viewport after a send or tab restoration.
/// Callers page their history and supply rows, selection state and their own
/// return-to-latest control. Keep lazy containers out of the content builder.
public struct ConversationScrollView<Content: View, Accessory: View>: View {
    private let messageIDs: [String]
    private let enabled: Bool
    private let isInteracting: Bool
    private let scrollRequest: Int
    private let spacing: CGFloat
    private let padding: EdgeInsets
    private let maximumWidth: CGFloat
    private let content: () -> Content
    private let accessory: (ConversationScrollStatus, @escaping () -> Void) -> Accessory
    @State private var state = ConversationFollowState()
    @State private var unread = ConversationUnreadTracker()
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var followTask: Task<Void, Never>?

    public init(messageIDs: [String], enabled: Bool = true, isInteracting: Bool = false,
                scrollRequest: Int = 0, spacing: CGFloat = 0,
                padding: EdgeInsets = EdgeInsets(), maximumWidth: CGFloat = .infinity,
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder accessory: @escaping (ConversationScrollStatus, @escaping () -> Void) -> Accessory) {
        self.messageIDs = messageIDs
        self.enabled = enabled
        self.isInteracting = isInteracting
        self.scrollRequest = scrollRequest
        self.spacing = spacing
        self.padding = padding
        self.maximumWidth = maximumWidth
        self.content = content
        self.accessory = accessory
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .frame(maxWidth: maximumWidth, alignment: .leading)
                .padding(padding)
                .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(canFollow ? .bottom : nil, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: ConversationGeometry.self) { geometry in
            ConversationGeometry(content: geometry.contentSize, container: geometry.containerSize,
                bottomInset: geometry.contentInsets.bottom,
                atBottom: geometry.contentSize.height - geometry.visibleRect.maxY <= 40)
        } action: { _, geometry in
            state.measured(atBottom: geometry.atBottom)
            if geometry.atBottom { unread.markRead() }
            scheduleFollow()
        }
        .onScrollPhaseChange { old, new in
            if new == .tracking || new == .interacting {
                state.beganReading()
                cancelFollow()
            }
            if new == .idle, old == .tracking || old == .interacting || old == .decelerating {
                state.finishedScrolling()
                if state.following { unread.markRead() }
            }
        }
        .onChange(of: messageIDs, initial: true) { _, ids in
            unread.update(ids, following: state.following || !enabled)
            scheduleFollow()
        }
        .onChange(of: canFollow) { _, value in if value { scheduleFollow() } else { cancelFollow() } }
        .onChange(of: scrollRequest) { _, _ in followLatest() }
        .onAppear { scheduleFollow() }
        .onDisappear { cancelFollow() }
        .overlay(alignment: .bottom) {
            accessory(ConversationScrollStatus(isFollowing: state.following, isAtBottom: state.atBottom,
                unreadCount: unread.unread.count), followLatest)
        }
    }

    private var canFollow: Bool { enabled && state.following && !isInteracting }

    private func followLatest() {
        state.followLatest()
        unread.markRead()
        scheduleFollow()
    }

    private func cancelFollow() { followTask?.cancel(); followTask = nil }

    private func scheduleFollow() {
        guard canFollow, followTask == nil else { return }
        followTask = Task { @MainActor in
            // Coalesce one layout pass, without timers or animated height estimates.
            await Task.yield()
            guard !Task.isCancelled else { return }
            followTask = nil
            guard canFollow else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.scrollTo(edge: .bottom) }
        }
    }
}
