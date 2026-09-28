import AppKit
@preconcurrency import ScreenCaptureKit

/// A single window's own capture, used in place of a display's base image
/// once the user picks a window in window-pick mode. `frame` is the window's
/// rect in the same display-local point space as the selection it replaces.
nonisolated struct WindowImageOverride: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let image: CGImage
    let frame: CGRect
    let scale: CGFloat
}

/// Captures a single window, independent of what else is on screen.
enum WindowCapture {
    struct CaptureError: Error {}

    static func capture(windowID: CGWindowID, pointSize: CGSize, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError()
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((pointSize.width * scale).rounded()))
        configuration.height = max(1, Int((pointSize.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
