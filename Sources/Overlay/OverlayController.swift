import AppKit
import SwiftUI

/// Owns the per-display panels and the session-scoped keyboard monitor for
/// one overlay session, and performs the render/copy/save when it finishes.
@MainActor
final class OverlayController {
    private let session: OverlaySession
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var keyMonitor: Any?
    private let outputScale: () -> CGFloat
    private let onClosed: () -> Void

    init(session: OverlaySession, outputScale: @escaping () -> CGFloat, onClosed: @escaping () -> Void) {
        self.session = session
        self.outputScale = outputScale
        self.onClosed = onClosed
    }

    func show() {
        for display in session.frozenDisplays {
            let rootView = SelectionView(displayID: display.displayID)
                .environment(session)
            let panel = OverlayPanel(frame: display.frame, rootView: rootView)
            panels[display.displayID] = panel
            panel.orderFrontRegardless()
        }

        session.onComplete = { [weak self] action in
            self?.handleFinish(action)
        }
        session.onActiveDisplayChanged = { [weak self] in
            self?.activeDisplayDidChange()
        }

        // A non-activating panel can take key status without the app being
        // activated (activation is cooperative since macOS 14 and may be
        // refused), so keys always reach us. Use the display under the mouse
        // until a selection picks one.
        keyPanel()?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    /// Called after a drag starts a fresh selection on a different display,
    /// so keyboard focus (and the inline text field) follow it.
    func activeDisplayDidChange() {
        keyPanel()?.makeKeyAndOrderFront(nil)
    }

    private func keyPanel() -> OverlayPanel? {
        if let activeID = session.activeDisplayID, let panel = panels[activeID] {
            return panel
        }
        let mouse = NSEvent.mouseLocation
        return panels.values.first { $0.frame.contains(mouse) } ?? panels.values.first
    }

    private func handleFinish(_ action: OverlayFinishAction) {
        if action == .startRecording {
            if let display = session.activeFrozenDisplay, let selection = session.selection {
                AppCoordinator.shared.startGIFRecording(display: display, selection: selection)
            }
            close()
            return
        }

        OverlayFinishRunner.run(action, session: session, outputScale: outputScale()) { [weak self] in
            self?.close()
        }
    }

    private func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
        onClosed()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let isEditingText = session.pendingTextEdit != nil

        if event.keyCode == KeyCode.space, !isEditingText, session.purpose != .gifRegion {
            session.toggleWindowPickMode()
            return nil
        }

        return AnnotationHotkeys.handle(event, session: session, isEditingText: isEditingText) { [weak session] in
            guard let session else { return }
            if session.windowPickMode {
                session.windowPickMode = false
            } else {
                session.finish(.cancel)
            }
        }
    }
}
