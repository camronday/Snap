import AppKit
import UniformTypeIdentifiers

/// Saves the last recorded GIF (already sitting in the temp directory) to a
/// user-chosen location via `NSSavePanel`.
enum GIFSaver {
    @MainActor
    static func save(from sourceURL: URL) async {
        NSApp.activate()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true

        guard await panel.beginSheetModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.copyItem(at: sourceURL, to: url)
    }
}
