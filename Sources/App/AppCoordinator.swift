import AppKit
import Observation

/// Central actions driven by the menu bar and hotkeys.
@MainActor
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    var isRecordingGIF = false
    private(set) var lastGIFURL: URL?

    /// Called by the app delegate to open the permission onboarding window.
    var showPermissionOnboarding: (() -> Void)?

    private var overlayController: OverlayController?
    private var gifRecorder: GIFRecorder?
    private var gifAutoStopTask: Task<Void, Never>?

    private init() {}

    private func requirePermission() -> Bool {
        guard ScreenCapturePermission.isGranted else {
            Log.capture.notice("Screen Recording access not granted, showing onboarding")
            showPermissionOnboarding?()
            return false
        }
        return true
    }

    /// Menu actions fire before the menu has finished closing; a short delay
    /// keeps it out of the frozen screenshot and off screen for the overlay.
    private static let menuCloseDelay = Duration.milliseconds(150)

    func captureRegion() {
        guard requirePermission() else { return }
        guard overlayController == nil else { return }
        Log.capture.info("captureRegion triggered")
        Task {
            try? await Task.sleep(for: Self.menuCloseDelay)
            await beginOverlaySession(purpose: .annotate)
        }
    }

    func captureWindow() {
        guard requirePermission() else { return }
        guard overlayController == nil else { return }
        Log.capture.info("captureWindow triggered")
        Task {
            try? await Task.sleep(for: Self.menuCloseDelay)
            await beginOverlaySession(purpose: .annotate, startInWindowPickMode: true)
        }
    }

    func captureDelayed(seconds: Int) {
        guard requirePermission() else { return }
        guard overlayController == nil else { return }
        Log.capture.info("captureDelayed(\(seconds)) triggered")
        Task {
            try? await Task.sleep(for: Self.menuCloseDelay)
            await DelayCountdown.run(seconds: seconds)
            await beginOverlaySession(purpose: .annotate)
        }
    }

    func captureText() {
        guard requirePermission() else { return }
        guard overlayController == nil else { return }
        Log.capture.info("captureText (OCR) triggered")
        Task {
            try? await Task.sleep(for: Self.menuCloseDelay)
            await beginOverlaySession(purpose: .ocr)
        }
    }

    /// Idle: opens the region-pick overlay. Recording: stops it. Driven by
    /// the menu item and the GIF hotkey alike.
    func toggleGIFRecording() {
        guard requirePermission() else { return }
        if isRecordingGIF {
            stopGIFRecording()
            return
        }
        guard overlayController == nil, gifRecorder == nil else { return }
        Log.capture.info("toggleGIFRecording: opening region picker")
        Task {
            try? await Task.sleep(for: Self.menuCloseDelay)
            await beginOverlaySession(purpose: .gifRegion)
        }
    }

    /// Called by `OverlayController` once the user confirms a region.
    func startGIFRecording(display: FrozenDisplay, selection: CGRect) {
        guard gifRecorder == nil, selection.width > 1, selection.height > 1 else { return }
        Log.capture.info("startGIFRecording on display \(display.displayID), region \(String(describing: selection))")

        let recorder = GIFRecorder()
        gifRecorder = recorder
        isRecordingGIF = true
        RecordingFrameWindow.show(display: display, selection: selection) { [weak self] in
            self?.toggleGIFRecording()
        }

        Task {
            do {
                try await recorder.start(displayID: display.displayID, selection: selection)
            } catch {
                Log.capture.error("GIFRecorder.start failed: \(error.localizedDescription)")
                self.stopGIFRecording()
            }
        }

        gifAutoStopTask = Task {
            try? await Task.sleep(for: .seconds(Preferences.gifMaxDuration))
            guard !Task.isCancelled else { return }
            self.stopGIFRecording()
        }
    }

    func stopGIFRecording() {
        guard let recorder = gifRecorder else { return }
        gifAutoStopTask?.cancel()
        gifAutoStopTask = nil
        gifRecorder = nil
        isRecordingGIF = false
        RecordingFrameWindow.hide()

        Task {
            let result = await recorder.stop()
            finishGIFRecording(result)
        }
    }

    private func finishGIFRecording(_ result: GIFRecorder.Result?) {
        guard let result else {
            Log.capture.notice("GIF recording produced no frames")
            return
        }
        if let previous = lastGIFURL, previous != result.url {
            try? FileManager.default.removeItem(at: previous)
        }
        lastGIFURL = result.url
        do {
            try GIFPasteboardWriter.write(fileURL: result.url)
            let sizeText = ByteCountFormatter.string(fromByteCount: Int64(result.fileSize), countStyle: .file)
            ToastPresenter.show(ToastContent(title: "GIF copied", snippet: String(format: "%.1f s \u{00B7} %@", result.duration, sizeText)))
        } catch {
            Log.capture.error("GIFPasteboardWriter.write failed: \(error.localizedDescription)")
        }
    }

    func saveLastGIF() {
        guard let lastGIFURL else { return }
        Task { await GIFSaver.save(from: lastGIFURL) }
    }

    func annotateClipboard() {
        Log.app.info("annotateClipboard triggered")
        ClipboardImageEditor.open()
    }

    private func beginOverlaySession(purpose: OverlayPurpose, startInWindowPickMode: Bool = false) async {
        do {
            let displays = try await ScreenFreezer.freezeAllDisplays()
            // Snapshotted before the overlay panels are shown, since they
            // would otherwise appear in the list themselves.
            let pickableWindows = WindowPicker.snapshot()
            let session = OverlaySession(frozenDisplays: displays, purpose: purpose, pickableWindows: pickableWindows, startInWindowPickMode: startInWindowPickMode)
            let controller = OverlayController(
                session: session,
                outputScale: { Preferences.outputScale },
                onClosed: { [weak self] in self?.overlayController = nil }
            )
            overlayController = controller
            controller.show()
        } catch {
            Log.capture.error("freezeAllDisplays failed: \(error.localizedDescription)")
        }
    }
}
