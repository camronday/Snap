import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Saves a rendered capture to disk via `NSSavePanel`, after the overlay has
/// closed and the app has been brought to the front.
enum ImageSaver {
    struct SaveError: Error {}

    /// Returns the saved file's URL, or nil if the user cancelled the panel
    /// or the write failed.
    @MainActor
    @discardableResult
    static func save(_ image: CGImage) async -> URL? {
        NSApp.activate()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultFileName()
        panel.canCreateDirectories = true

        guard await panel.beginSheetModal() == .OK, let url = panel.url else { return nil }
        do {
            try write(image, to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SaveError()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SaveError() }
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Snap \(formatter.string(from: .now)).png"
    }
}

extension NSSavePanel {
    @MainActor
    func beginSheetModal() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
