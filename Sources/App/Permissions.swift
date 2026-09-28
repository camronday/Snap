import AppKit
import CoreGraphics

/// Screen Recording permission checks. Hotkeys need no TCC; capture does.
enum ScreenCapturePermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system consent prompt (only shows once per app identity).
    static func request() {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
