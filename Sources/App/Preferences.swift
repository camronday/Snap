import SwiftUI

/// Central store for user-facing preferences, backed by @AppStorage.
/// Later phases read these; Phase 1 only defines and surfaces them in Settings.
enum PreferencesKey {
    static let annotationColour = "annotationColour"
    static let retinaClipboard = "retinaClipboard"
    static let gifMaxDuration = "gifMaxDuration"
}

enum PreferencesDefault {
    /// Hex RGBA string, default red.
    static let annotationColour = "FF0000FF"
    static let retinaClipboard = true
    static let gifMaxDuration = 30
}

/// Bounds for the GIF max duration slider/stepper.
enum PreferencesRange {
    static let gifMaxDuration = 5...120
}

/// Reads preferences from outside SwiftUI's `@AppStorage`, for plain classes
/// like `AppCoordinator` and `OverlaySession`.
enum Preferences {
    static var outputScale: CGFloat {
        let retina = UserDefaults.standard.object(forKey: PreferencesKey.retinaClipboard) as? Bool
            ?? PreferencesDefault.retinaClipboard
        return retina ? 2 : 1
    }

    static var gifMaxDuration: Int {
        let stored = UserDefaults.standard.object(forKey: PreferencesKey.gifMaxDuration) as? Int
            ?? PreferencesDefault.gifMaxDuration
        return PreferencesRange.gifMaxDuration.clamping(stored)
    }
}

private extension ClosedRange where Bound == Int {
    func clamping(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
