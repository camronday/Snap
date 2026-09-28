import AppKit
import SwiftUI

/// One borderless panel per display, floating above everything (including
/// full-screen apps and other spaces) while the overlay is up.
final class OverlayPanel: NSPanel {
    init(frame: CGRect, rootView: some View) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        contentView = NSHostingView(rootView: rootView)
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}
