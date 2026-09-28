import AppKit
import Observation

/// What the overlay was opened to do. Only `.annotate` is implemented; the
/// others are routed through the same `finish` entry point so Phase 4 can
/// plug in OCR and GIF region pick without touching the overlay plumbing.
enum OverlayPurpose {
    case annotate
    case ocr
    case gifRegion
    case clipboardEdit
}

enum OverlayFinishAction {
    case copy
    case save
    case cancel
    case startRecording
}

/// In-progress state for the inline text tool: a click places this, typing
/// fills `text`, and committing turns it into a real `Annotation`.
struct PendingTextEdit {
    var origin: CGPoint
}

/// All state for one overlay session, shared across every display's panel.
@MainActor
@Observable
final class OverlaySession {
    let frozenDisplays: [FrozenDisplay]
    let purpose: OverlayPurpose

    var activeDisplayID: CGDirectDisplayID?
    var selection: CGRect?
    var currentTool: AnnotationKind?
    var colour: RGBAColour
    var document = AnnotationDocument()
    var windowPickMode: Bool
    var pendingTextEdit: PendingTextEdit?

    /// True while the Live Text overlay is showing over the selection,
    /// replacing the annotation/selection interaction with in-place text
    /// selection until dismissed.
    var liveTextMode = false
    /// Supplied by the active `LiveTextView` so Cmd/Ctrl+C and Return can
    /// read the current text selection without holding a reference to the
    /// AppKit overlay view itself. Cleared when Live Text mode exits.
    var liveTextSelectedTextProvider: (() -> String)?

    /// Windows on screen at freeze time, for window-pick mode's hover/click.
    let pickableWindows: [PickableWindow]
    /// The picked window's own capture, replacing the frozen desktop within
    /// the selection it was picked at.
    private(set) var windowOverride: WindowImageOverride?
    @ObservationIgnored private var windowCaptureGeneration = 0

    /// Called once, when the session should close: renders/copies/saves as
    /// needed, then hands back to the controller to tear down the panels.
    var onComplete: ((OverlayFinishAction) -> Void)?

    /// Called whenever a drag moves the selection to a different display, so
    /// the controller can move keyboard focus (and the panel's key state) over.
    var onActiveDisplayChanged: (() -> Void)?

    init(frozenDisplays: [FrozenDisplay], purpose: OverlayPurpose = .annotate, pickableWindows: [PickableWindow] = [], startInWindowPickMode: Bool = false) {
        self.frozenDisplays = frozenDisplays
        self.purpose = purpose
        self.pickableWindows = pickableWindows
        windowPickMode = startInWindowPickMode
        activeDisplayID = frozenDisplays.first?.displayID
        if let hex = UserDefaults.standard.string(forKey: PreferencesKey.annotationColour),
           let stored = RGBAColour(hexString: hex) {
            colour = stored
        } else {
            colour = RGBAColour(hexString: PreferencesDefault.annotationColour) ?? .red
        }
    }

    var activeFrozenDisplay: FrozenDisplay? {
        frozenDisplays.first { $0.displayID == activeDisplayID }
    }

    func setColour(_ colour: RGBAColour) {
        self.colour = colour
        UserDefaults.standard.set(colour.hexString, forKey: PreferencesKey.annotationColour)
    }

    /// A drag started on `displayID`. If it isn't the active one, the
    /// selection and its annotations move over, per the plan.
    func beginSelection(on displayID: CGDirectDisplayID, at point: CGPoint) {
        if displayID != activeDisplayID {
            activeDisplayID = displayID
            document.clear()
            onActiveDisplayChanged?()
        }
        selection = CGRect(origin: point, size: .zero)
        pendingTextEdit = nil
        windowOverride = nil
    }

    /// A window was picked in window-pick mode: its frame becomes the
    /// selection and its own capture becomes the base image for it.
    func selectWindow(_ window: PickableWindow, on displayID: CGDirectDisplayID, at localFrame: CGRect) {
        if displayID != activeDisplayID {
            activeDisplayID = displayID
            onActiveDisplayChanged?()
        }
        document.clear()
        windowOverride = nil
        selection = localFrame
        windowPickMode = false
        pendingTextEdit = nil

        let scale = frozenDisplays.first { $0.displayID == displayID }?.scale ?? 2
        windowCaptureGeneration += 1
        let generation = windowCaptureGeneration
        Task {
            do {
                let image = try await WindowCapture.capture(windowID: window.windowID, pointSize: localFrame.size, scale: scale)
                // Drop a late result if the user has since picked again or drawn a new selection.
                guard generation == windowCaptureGeneration, selection == localFrame else { return }
                windowOverride = WindowImageOverride(displayID: displayID, image: image, frame: localFrame, scale: scale)
            } catch {
                Log.capture.error("window capture failed: \(error.localizedDescription)")
            }
        }
    }

    /// The active window-capture override, if any, for `displayID`.
    func override(on displayID: CGDirectDisplayID) -> WindowImageOverride? {
        windowOverride?.displayID == displayID ? windowOverride : nil
    }

    func updateSelection(to rect: CGRect) {
        selection = rect
    }

    func startAnnotation(_ annotation: Annotation) {
        document.add(annotation)
    }

    func updateLastAnnotation(_ transform: (inout Annotation) -> Void) {
        document.updateLast(transform)
    }

    /// Bakes the blur/pixelate patch for the most recently added annotation,
    /// once its rect is final (drag ended). Runs off-actor since Core Image
    /// filtering isn't free; the result is patched back in by id so a
    /// meanwhile-added annotation can't be clobbered.
    func finalizeFilteredPatch() {
        guard let display = activeFrozenDisplay,
              let last = document.items.last,
              last.kind.needsFilteredPatch else { return }
        let id = last.id
        let kind = last.kind
        let rect = last.rect
        let base = display.image
        let baseScale = display.scale
        Task {
            let patch = await AnnotationFilter.makePatch(kind: kind, rect: rect, base: base, scale: baseScale)
            document.update(id: id) { $0.filteredPatch = patch }
        }
    }

    func undo() { document.undo() }
    func redo() { document.redo() }

    func commitPendingText(_ text: String) {
        defer { pendingTextEdit = nil }
        guard let pending = pendingTextEdit, !text.isEmpty else { return }
        var annotation = Annotation(kind: .text, colour: colour)
        annotation.text = text
        annotation.origin = pending.origin
        document.add(annotation)
    }

    func addCallout(at point: CGPoint) {
        var annotation = Annotation(kind: .callout, colour: colour)
        annotation.origin = point
        annotation.calloutNumber = document.nextCalloutNumber
        document.add(annotation)
    }

    func toggleWindowPickMode() {
        windowPickMode.toggle()
    }

    func finish(_ action: OverlayFinishAction) {
        onComplete?(action)
    }

    /// The selection's base pixels (no annotations), for Live Text and
    /// "Copy All": the picked window's own capture when it exactly covers
    /// the selection, else the frozen display cropped to it.
    func liveTextSourceImage() -> CGImage? {
        guard let selection else { return nil }
        if let windowOverride, windowOverride.frame == selection {
            return windowOverride.image
        }
        return activeFrozenDisplay?.croppedImage(for: selection)
    }

    /// Enters Live Text mode over the current selection. Called
    /// automatically once a `.ocr`-purpose selection is drawn, and by the
    /// toolbar's Live Text tool for `.annotate`/`.clipboardEdit` sessions.
    func captureText() {
        guard selection != nil, !liveTextMode else { return }
        liveTextMode = true
    }

    func exitLiveTextMode() {
        liveTextMode = false
        liveTextSelectedTextProvider = nil
    }

    func toggleLiveTextMode() {
        if liveTextMode {
            exitLiveTextMode()
        } else {
            captureText()
        }
    }

    /// Recognises all text in the selection (Live Text's "Copy All"),
    /// copies it as plain text and shows a toast.
    func copyAllRecognizedText() {
        guard let image = liveTextSourceImage() else { return }
        Task {
            let text = await TextRecognizer.recognize(image)
            if text.isEmpty {
                ToastPresenter.show(ToastContent(title: "No text found", snippet: nil))
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                ToastPresenter.show(ToastContent(title: "Copied to clipboard", snippet: ToastContent.snippet(from: text)))
                exitLiveTextMode()
            }
        }
    }
}
