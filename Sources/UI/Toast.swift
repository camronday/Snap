import AppKit
import SwiftUI

/// Small view-polish helpers shared by the overlay's floating controls
/// (toolbar, GIF/Live Text pills, toasts).
extension View {
    /// Reports this view's rendered size into `size`, for a caller that
    /// needs to lay another view out relative to it (e.g. clamping a
    /// position so a floating control stays on screen as its own width
    /// changes, such as the toolbar's selected-tool glass morph).
    func measuringControlsSize(_ size: Binding<CGSize>) -> some View {
        onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            size.wrappedValue = newSize
        }
    }

    /// The standard appear/disappear transition for a floating glass
    /// control: grows in from a slight scale while fading.
    func glassControlTransition() -> some View {
        transition(.scale(scale: 0.9, anchor: .center).combined(with: .opacity))
    }
}

/// One toast's contents: a title and an optional preview snippet (already
/// truncated by the caller).
struct ToastContent: Equatable {
    let title: String
    let snippet: String?

    /// Snippets are capped at ~80 characters and 2 lines.
    static func snippet(from text: String, limit: Int = 80) -> String {
        String(text.prefix(limit))
    }
}

/// Shows a glass HUD, bottom centre of the screen containing the mouse.
/// Nonactivating and ignores mouse events, so it never steals focus. Only
/// one toast is shown at a time; a new one replaces whatever is showing.
@MainActor
enum ToastPresenter {
    private static var panel: ToastPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ content: ToastContent) {
        dismissTask?.cancel()

        let screen = ScreenLocator.containingMouse()
        if let panel {
            panel.update(content)
            panel.reposition(on: screen)
        } else {
            let panel = ToastPanel(content: content)
            panel.reposition(on: screen)
            Self.panel = panel
        }
        panel?.orderFrontRegardless()
        // A fresh `renderID` each time (below, via `update`/`init`) forces
        // `ToastView` to remount, so the glass materialise animation replays
        // for every toast, not just the first one to use this panel.

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }
}

private final class ToastPanel: NSPanel {
    private let hostingView: NSHostingView<ToastView>

    init(content: ToastContent) {
        hostingView = NSHostingView(rootView: ToastView(content: content, renderID: UUID()))
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
    }

    func update(_ content: ToastContent) {
        hostingView.rootView = ToastView(content: content, renderID: UUID())
        setContentSize(hostingView.fittingSize)
    }

    func reposition(on screen: NSScreen) {
        let size = hostingView.fittingSize
        setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 72, width: size.width, height: size.height), display: false)
    }
}

private struct ToastView: View {
    let content: ToastContent
    /// Changes on every `show`/`update` call, forcing this subtree to
    /// remount so the materialise animation below replays each time.
    let renderID: UUID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 4) {
            Text(content.title)
                .font(.callout.weight(.semibold))
            if let snippet = content.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 280)
        .fixedSize()
        .glassEffect(in: .rect(cornerRadius: 16))
        .scaleEffect(isVisible ? 1 : 0.85)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isVisible = true
                }
            }
        }
        .id(renderID)
    }
}
