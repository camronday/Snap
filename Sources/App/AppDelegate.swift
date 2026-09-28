import AppKit
import SwiftUI

/// Runs launch-time setup outside SwiftUI's lazy menu-content lifecycle, so
/// hotkeys and the permission check both happen even if the user never opens
/// the menu bar dropdown.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GIFEncoder.removeOrphanedTemporaryFiles()
        HotkeyRegistrar.register(coordinator: .shared)
        AppCoordinator.shared.showPermissionOnboarding = { [weak self] in
            self?.showPermissionOnboarding()
        }
        if !ScreenCapturePermission.isGranted {
            showPermissionOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GIFEncoder.removeOrphanedTemporaryFiles()
    }

    private func showPermissionOnboarding() {
        if permissionWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PermissionOnboardingView()))
            window.title = "Screen Recording Access"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            permissionWindow = window
        }
        permissionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
