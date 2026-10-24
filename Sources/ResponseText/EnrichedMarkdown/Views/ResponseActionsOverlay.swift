import SwiftUI
import UIKit

/// Host-owned actions and authenticated feedback. Provider details stay outside the renderer.
@MainActor public struct MarkdownMessageActions {
    public var reply: (() -> Void)?
    public var loadFeedback: (() async throws -> String?)?
    public var submitFeedback: ((String, String) async throws -> String)?
    public var background: UIColor
    public var foreground: UIColor
    public init(reply: (() -> Void)? = nil, loadFeedback: (() async throws -> String?)? = nil,
                submitFeedback: ((String, String) async throws -> String)? = nil,
                background: UIColor = .secondarySystemBackground, foreground: UIColor = .label) {
        self.reply = reply; self.loadFeedback = loadFeedback; self.submitFeedback = submitFeedback
        self.background = background; self.foreground = foreground
    }
}

/// How a long press on a response shows its message actions.
public enum MarkdownMessageMenuStyle: Sendable {
    /// The system context menu: Copy, Copy as Markdown and Select Text.
    case contextMenu
    /// A full-screen overlay with Copy, Select and Share, plus the host's
    /// `MarkdownMessageActions` (Reply and the feedback strip).
    case actionsOverlay
}

private struct MarkdownMessageMenuStyleKey: EnvironmentKey {
    static let defaultValue = MarkdownMessageMenuStyle.contextMenu
}
extension EnvironmentValues {
    var markdownMessageMenuStyle: MarkdownMessageMenuStyle {
        get { self[MarkdownMessageMenuStyleKey.self] }
        set { self[MarkdownMessageMenuStyleKey.self] = newValue }
    }
}
public extension View {
    func markdownMessageMenuStyle(_ style: MarkdownMessageMenuStyle) -> some View {
        environment(\.markdownMessageMenuStyle, style)
    }
}

private struct MarkdownMessageActionsKey: EnvironmentKey {
    static let defaultValue: MarkdownMessageActions? = nil
}
extension EnvironmentValues {
    var markdownMessageActions: MarkdownMessageActions? {
        get { self[MarkdownMessageActionsKey.self] }
        set { self[MarkdownMessageActionsKey.self] = newValue }
    }
}
public extension View {
    func markdownMessageActions(_ actions: MarkdownMessageActions?) -> some View {
        environment(\.markdownMessageActions, actions)
    }
}

/// Lets a host's visible action row run the long-press actions on the same
/// rendered response: Copy exports the whole document, Select starts native
/// selection of all of it, Share presents the system share sheet.
@MainActor public final class MarkdownMessageHandle {
    weak var menu: ResponseMessageMenu?
    public init() {}
    public func copy() { menu?.copyResponse() }
    public func selectText() { menu?.selectResponse() }
    public func share() { menu?.shareResponse() }
}

private struct MarkdownMessageHandleKey: EnvironmentKey {
    static let defaultValue: MarkdownMessageHandle? = nil
}
extension EnvironmentValues {
    var markdownMessageHandle: MarkdownMessageHandle? {
        get { self[MarkdownMessageHandleKey.self] }
        set { self[MarkdownMessageHandleKey.self] = newValue }
    }
}
public extension View {
    func markdownMessageHandle(_ handle: MarkdownMessageHandle?) -> some View {
        environment(\.markdownMessageHandle, handle)
    }
}

/// A separate reaction strip, readable message preview and compact action menu.
@MainActor final class ResponseActionsOverlay: UIViewController {
    let actions: MarkdownMessageActions
    let preview: ResponseMarkdownTextView
    var onClose: ((Bool) -> Void)?
    var onCopy: (() -> Void)?
    var onSelect: (() -> Void)?
    var onShare: (() -> Void)?
    var requestID: (String) -> String = { _ in UUID().uuidString }
    var completedRequest: (String) -> Void = { _ in }
    private let stack = MessageMenuLayoutStack()
    private let status = UILabel()
    private var buttons: [String: UIButton] = [:]
    private var feedbackTask: Task<Void, Never>?
    private var rating: String?
    private var busy = false
    private var loaded = false
    private let sourceRect: CGRect
    private var previewHeight: NSLayoutConstraint?
    private var contentHeight: NSLayoutConstraint?
    private var messageCard: UIView?
    private var top: NSLayoutConstraint?

    init(textView: ResponseMarkdownTextView, actions: MarkdownMessageActions, sourceRect: CGRect) {
        self.actions = actions; self.sourceRect = sourceRect
        preview = ResponseMarkdownTextView()
        super.init(nibName: nil, bundle: nil)
        preview.styleConfig = textView.styleConfig
        preview.isSelectionEnabled = false
        preview.isSelectable = false
        preview.setMarkdownAttributedText(textView.attributedText)
        preview.accessibilityIdentifier = "message.menu.preview"
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.frame = view.bounds; blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blur)
        let backdrop = UIButton(); backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.14)
        backdrop.frame = view.bounds; backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.accessibilityLabel = "Dismiss message menu"; backdrop.accessibilityIdentifier = "message.menu.dismiss"
        backdrop.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        view.addSubview(backdrop)
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        top = stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16), top!,
            stack.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8)])

        if actions.submitFeedback != nil {
            let reactions = UIStackView(); reactions.spacing = 8; reactions.distribution = .fillEqually
            for (value, emoji, title) in [("positive", "👍", "Good response"), ("negative", "👎", "Bad response")] {
                let button = UIButton(type: .system)
                var config = UIButton.Configuration.plain(); config.title = emoji
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in var out = input; out.font = .systemFont(ofSize: 28); return out }
                config.cornerStyle = .capsule; button.configuration = config
                button.accessibilityLabel = title; button.accessibilityIdentifier = "message.feedback.\(value)"
                button.addAction(UIAction { [weak self] _ in self?.submit(value) }, for: .touchUpInside)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
                buttons[value] = button; reactions.addArrangedSubview(button)
            }
            let row = UIStackView(); row.axis = .vertical; row.spacing = 0
            row.addArrangedSubview(reactions)
            status.textAlignment = .center; status.font = .preferredFont(forTextStyle: .caption1)
            status.adjustsFontForContentSizeCategory = true; status.numberOfLines = 0
            status.textColor = actions.foreground; status.accessibilityIdentifier = "message.feedback.status"
            row.addArrangedSubview(status)
            stack.addArrangedSubview(card(row, radius: 28, inset: 6))
        }

        let scroll = UIScrollView(); scroll.alwaysBounceVertical = false
        preview.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(preview)
        contentHeight = preview.heightAnchor.constraint(equalToConstant: 60)
        contentHeight?.isActive = true
        NSLayoutConstraint.activate([preview.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            preview.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            preview.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            preview.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        let message = card(scroll, radius: 22, inset: 16)
        messageCard = message
        previewHeight = message.heightAnchor.constraint(equalToConstant: 160); previewHeight?.isActive = true
        stack.addArrangedSubview(message)
        let menu = UIStackView(); menu.axis = .vertical
        if actions.reply != nil { menu.addArrangedSubview(action("Reply", "arrowshape.turn.up.left") { [weak self] in self?.close(completion: self?.actions.reply) }) }
        menu.addArrangedSubview(action("Copy", "doc.on.doc") { [weak self] in self?.onCopy?(); self?.close() })
        menu.addArrangedSubview(action("Select", "text.cursor") { [weak self] in self?.close(selecting: true, completion: self?.onSelect) })
        menu.addArrangedSubview(action("Share", "square.and.arrow.up") { [weak self] in self?.close(completion: self?.onShare) })
        let menuCard = card(menu, radius: 24, inset: 6)
        let spacer = UIView(); spacer.isUserInteractionEnabled = false
        let menuRow = MessageMenuLayoutStack(arrangedSubviews: [menuCard, spacer])
        stack.addArrangedSubview(menuRow)
        menuCard.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.68).isActive = true
        load()
    }

    private func card(_ content: UIView, radius: CGFloat, inset: CGFloat) -> UIView {
        let card = UIView(); card.backgroundColor = actions.background.withAlphaComponent(0.97)
        card.layer.cornerRadius = radius; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)])
        return card
    }
    private func action(_ title: String, _ symbol: String, handler: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain(); config.title = title; config.image = MarkdownMenuIcons.image(symbol)
        config.imagePadding = 14; config.baseForegroundColor = actions.foreground
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in var out = input; out.font = .preferredFont(forTextStyle: .body); return out }
        button.configuration = config; button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "message.menu.\(title.lowercased())"
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return button
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let available = view.safeAreaLayoutGuide.layoutFrame
        let width = max(100, available.width - 64)
        let natural = preview.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        if contentHeight?.constant != natural { contentHeight?.constant = natural }
        // Keep every action reachable and let long responses scroll within their preview.
        let chrome = stack.arrangedSubviews.filter { $0 !== messageCard }
            .reduce(CGFloat(0)) { $0 + $1.systemLayoutSizeFitting(CGSize(width: available.width - 32, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height }
        let height = min(natural + 32, max(60, available.height - chrome - 40))
        if previewHeight?.constant != height { previewHeight?.constant = height }
        let total = height + chrome + CGFloat(stack.arrangedSubviews.count - 1) * 8
        let origin = max(8, min(sourceRect.minY - available.minY - (actions.submitFeedback == nil ? 0 : 76), available.height - total - 8))
        if top?.constant != origin { top?.constant = origin }
    }
    private func load() {
        guard let load = actions.loadFeedback else { loaded = true; return }
        busy = true; status.text = "Loading feedback…"; updateButtons()
        feedbackTask = Task { [weak self] in
            do {
                let value = try await load(); guard !Task.isCancelled, let self else { return }
                self.rating = value; if let value { self.completedRequest(value) }; self.loaded = true; self.status.text = value == nil ? nil : "Feedback saved"
            } catch { guard !Task.isCancelled else { return }; self?.status.text = "Could not load feedback. Tap a reaction to retry." }
            self?.busy = false; self?.updateButtons()
        }
    }
    private func submit(_ value: String) {
        guard !busy else { return }
        guard loaded else { load(); return }
        if rating == value { close(); return }
        guard let submit = actions.submitFeedback else { return }
        busy = true; status.text = "Saving feedback…"; updateButtons()
        let id = requestID(value)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        feedbackTask = Task { [weak self] in
            do {
                let saved = try await submit(value, id); guard !Task.isCancelled, let self else { return }
                self.rating = saved; self.completedRequest(value); self.status.text = "Feedback saved"
                UIAccessibility.post(notification: .announcement, argument: "Feedback saved")
            } catch { guard !Task.isCancelled else { return }; self?.status.text = "Could not save feedback. Tap again to retry." }
            self?.busy = false; self?.updateButtons()
        }
    }
    private func updateButtons() {
        for (value, button) in buttons {
            button.isEnabled = !busy; button.isSelected = rating == value
            button.accessibilityValue = rating == value ? "Selected" : "Not selected"
            button.configuration?.background.backgroundColor = rating == value ? view.tintColor.withAlphaComponent(0.16) : .clear
        }
        view.setNeedsLayout()
    }
    func close(selecting: Bool = false, completion: (() -> Void)? = nil) {
        feedbackTask?.cancel()
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in self?.onClose?(selecting); completion?() }
    }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
}

/// Empty layout space belongs to the dismiss button behind the menu cards.
private final class MessageMenuLayoutStack: UIStackView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
