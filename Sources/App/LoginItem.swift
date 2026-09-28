import ServiceManagement

/// Thin wrapper over SMAppService.mainApp for the "Launch at login" toggle.
@MainActor
enum LoginItem {
    /// True only when actually enabled; .notFound and .notRegistered both read as off.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user needs to approve the login item in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("LoginItem toggle failed: \(error.localizedDescription)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
