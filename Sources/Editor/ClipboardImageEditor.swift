import AppKit
import SwiftUI

/// "Annotate Clipboard Image": opens the best image on the general
/// pasteboard in a normal, resizable window using the same annotation
/// canvas and toolbar as the capture overlay.
@MainActor
enum ClipboardImageEditor {
    private static var current: EditorWindowController?

    /// Rejected outright rather than decoded further: a maliciously crafted
    /// clipboard image (or just a huge screenshot from another app) could
    /// otherwise drive the annotation canvas and its render pipeline to
    /// allocate an unreasonable amount of memory.
    static let maxDimension = 16384
    static let maxPixelCount = 100_000_000

    static func open() {
        guard let (image, pointSize) = ClipboardInspector.bestImage() else { return }
        guard image.width <= maxDimension, image.height <= maxDimension,
              image.width * image.height <= maxPixelCount
        else {
            Log.app.notice("annotateClipboard rejected oversized image \(image.width)x\(image.height)")
            ToastPresenter.show(ToastContent(title: "Image too large to annotate", snippet: nil))
            return
        }
        let display = FrozenDisplay(displayID: 0, frame: CGRect(origin: .zero, size: pointSize), scale: CGFloat(image.width) / pointSize.width, image: image)
        let session = OverlaySession(frozenDisplays: [display], purpose: .clipboardEdit)

        let controller = EditorWindowController(session: session, display: display) {
            current = nil
        }
        current = controller
        controller.show()
    }
}

/// Owns the editor's window and its keyboard monitor.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let session: OverlaySession
    private let window: NSWindow
    private var keyMonitor: Any?
    private let onClosed: () -> Void

    init(session: OverlaySession, display: FrozenDisplay, onClosed: @escaping () -> Void) {
        self.session = session
        self.onClosed = onClosed
        session.selection = CGRect(origin: .zero, size: display.frame.size)

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fitScale = min(1, screenFrame.width * 0.8 / display.frame.width, screenFrame.height * 0.8 / display.frame.height)

        let root = EditorRootView(session: session, fitScale: fitScale)
        let hosting = NSHostingController(rootView: root)
        window = NSWindow(contentViewController: hosting)
        window.title = "Annotate Clipboard Image"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(CGSize(width: display.frame.width * fitScale + 48, height: display.frame.height * fitScale + 120))
        window.center()
        window.isReleasedWhenClosed = false

        super.init()
        window.delegate = self
    }

    func show() {
        session.onComplete = { [weak self] action in
            guard let self else { return }
            OverlayFinishRunner.run(action, session: session, outputScale: Preferences.outputScale) { [weak self] in
                self?.close()
            }
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func close() {
        window.close()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let isEditingText = session.pendingTextEdit != nil
        return AnnotationHotkeys.handle(event, session: session, isEditingText: isEditingText) { [weak self] in
            self?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        onClosed()
    }
}
