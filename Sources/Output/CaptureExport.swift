import CoreGraphics
import Foundation

/// Renders the active selection and puts it on the clipboard or on disk,
/// with a toast to confirm. Shared by the capture overlay and the clipboard
/// image editor, since both drive the same `OverlaySession`.
enum CaptureExport {
    static func copy(session: OverlaySession, outputScale requested: CGFloat) async {
        let outputScale = effectiveScale(requested, session: session)
        guard let image = await render(session: session, outputScale: outputScale) else { return }
        try? ClipboardWriter.write(image, outputScale: outputScale)
        ToastPresenter.show(ToastContent(title: "Copied to clipboard", snippet: nil))
    }

    /// Renders the selection at its effective (never-upsampled) scale, for
    /// `.save`. Deliberately stops short of presenting anything: the caller
    /// (`OverlayFinishRunner`) closes the overlay panels between this and
    /// showing the save panel, since a `.screenSaver`-level panel would
    /// otherwise sit in front of `NSSavePanel`.
    static func renderForSave(session: OverlaySession, outputScale requested: CGFloat) async -> CGImage? {
        await render(session: session, outputScale: effectiveScale(requested, session: session))
    }

    /// Never upsample: the Retina preference means "native pixels", so a 1x
    /// display exports at 1x.
    private static func effectiveScale(_ requested: CGFloat, session: OverlaySession) -> CGFloat {
        min(requested, session.activeFrozenDisplay?.scale ?? requested)
    }

    private static func render(session: OverlaySession, outputScale: CGFloat) async -> CGImage? {
        guard let display = session.activeFrozenDisplay, let selection = session.selection,
              selection.width > 1, selection.height > 1 else { return nil }
        return try? await Renderer.render(
            items: session.document.items,
            base: display.image,
            crop: selection,
            baseScale: display.scale,
            outputScale: outputScale,
            override: session.override(on: display.displayID)
        )
    }
}

/// Runs the copy/save/cancel that finishes an annotation session, then hands
/// back to the caller to tear down its window(s). Shared by the overlay's
/// `OverlayController` and the editor's `EditorWindowController`.
///
/// `.save` renders first, closes the overlay, and only then presents the
/// save panel: presenting `NSSavePanel` while the overlay's
/// `.screenSaver`-level panels are still up puts the save panel behind them.
/// `presentSave` is injected (defaulting to `ImageSaver.save`) so a test can
/// verify that ordering without driving a real save panel.
@MainActor
enum OverlayFinishRunner {
    static func run(
        _ action: OverlayFinishAction,
        session: OverlaySession,
        outputScale: CGFloat,
        presentSave: @escaping (CGImage) async -> URL? = ImageSaver.save,
        close: @escaping () -> Void
    ) {
        switch action {
        case .cancel, .startRecording:
            // `.startRecording` is intercepted by `OverlayController` before
            // it reaches here; treated as a plain close if it ever isn't.
            close()

        case .copy:
            Task {
                await CaptureExport.copy(session: session, outputScale: outputScale)
                close()
            }

        case .save:
            Task {
                let image = await CaptureExport.renderForSave(session: session, outputScale: outputScale)
                close()
                guard let image, let url = await presentSave(image) else { return }
                ToastPresenter.show(ToastContent(title: "Saved", snippet: url.lastPathComponent))
            }
        }
    }
}
