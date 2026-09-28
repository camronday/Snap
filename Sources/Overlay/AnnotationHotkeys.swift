import AppKit

/// Key codes used across the overlay and the clipboard editor.
enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
}

/// Routes a key event against the session actions shared by the capture
/// overlay and the clipboard image editor: copy, save, undo/redo and escape.
/// Returns nil to consume the event, or the event itself to pass it through.
enum AnnotationHotkeys {
    static func handle(_ event: NSEvent, session: OverlaySession, isEditingText: Bool, onEscapeWhenIdle: () -> Void) -> NSEvent? {
        switch event.keyCode {
        case KeyCode.escape:
            if isEditingText {
                session.pendingTextEdit = nil
            } else if session.liveTextMode {
                // Live Text exits first; a second Esc is needed to close.
                session.exitLiveTextMode()
            } else {
                onEscapeWhenIdle()
            }
            return nil

        case KeyCode.returnKey:
            if isEditingText { return event }
            if session.liveTextMode, copySelectedLiveText(session: session) { return nil }
            session.finish(session.purpose == .gifRegion ? .startRecording : .copy)
            return nil

        default:
            break
        }

        // Command is the Mac convention; Control is accepted too since the capture hotkey uses it.
        guard !isEditingText, !event.modifierFlags.isDisjoint(with: [.command, .control]) else { return event }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            if session.liveTextMode, copySelectedLiveText(session: session) { return nil }
            session.finish(.copy)
            return nil
        case "s":
            session.finish(.save)
            return nil
        case "z":
            if event.modifierFlags.contains(.shift) {
                session.redo()
            } else {
                session.undo()
            }
            return nil
        default:
            return event
        }
    }

    /// Copies the Live Text overlay's current selection, if any, and shows a
    /// toast. Returns whether it did, so the caller can fall back to the
    /// normal whole-selection copy when nothing is selected.
    private static func copySelectedLiveText(session: OverlaySession) -> Bool {
        guard let text = session.liveTextSelectedTextProvider?(), !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastPresenter.show(ToastContent(title: "Text copied", snippet: ToastContent.snippet(from: text)))
        return true
    }
}
