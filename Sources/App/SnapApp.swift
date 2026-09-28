import SwiftUI

@main
struct SnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(coordinator)
        } label: {
            Image(systemName: coordinator.isRecordingGIF ? "record.circle.fill" : "camera.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}

/// The menu bar dropdown contents, split out for readability.
private struct MenuBarContent: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Button("Capture Region") { coordinator.captureRegion() }
            .globalKeyboardShortcut(.captureRegion)
        Button("Capture Window") { coordinator.captureWindow() }
        Button("Capture in 3 Seconds") { coordinator.captureDelayed(seconds: 3) }
        Button("Capture in 5 Seconds") { coordinator.captureDelayed(seconds: 5) }
        Button("Capture Text (OCR)") { coordinator.captureText() }
        Button(coordinator.isRecordingGIF ? "Stop Recording" : "Record GIF") {
            coordinator.toggleGIFRecording()
        }
        .globalKeyboardShortcut(.recordGIF)
        Button("Annotate Clipboard Image") { coordinator.annotateClipboard() }
            .disabled(!ClipboardInspector.hasImage)
        Button("Save Last GIF…") { coordinator.saveLastGIF() }
            .disabled(coordinator.lastGIFURL == nil)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Quit Snap") {
            NSApplication.shared.terminate(nil)
        }
    }
}
