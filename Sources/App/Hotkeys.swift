import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", default: .init(.s, modifiers: [.control, .shift]))
    static let recordGIF = Self("recordGIF", default: .init(.g, modifiers: [.control, .shift]))
}

/// Wires global hotkeys to the coordinator. Call once at launch.
@MainActor
enum HotkeyRegistrar {
    static func register(coordinator: AppCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .captureRegion) {
            coordinator.captureRegion()
        }
        KeyboardShortcuts.onKeyUp(for: .recordGIF) {
            coordinator.toggleGIFRecording()
        }
    }
}
