import CoreGraphics
import Foundation

/// One on-screen window candidate for window-pick mode, snapshotted once at
/// freeze time so hover/click never re-queries the window server while the
/// overlay is up.
nonisolated struct PickableWindow: Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    /// Frame in CG global coordinates (points, origin top-left of the
    /// primary display), as `CGWindowListCopyWindowInfo` reports it.
    let globalFrame: CGRect
}

enum WindowPicker {
    static let minimumSize: CGFloat = 40

    /// Snapshots on-screen, layer-0 windows, front to back, excluding our own
    /// process and anything smaller than `minimumSize` in either dimension.
    /// Call this before the overlay panels are shown, since they would
    /// otherwise appear in the list themselves.
    static func snapshot() -> [PickableWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info -> PickableWindow? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            guard bounds.width >= minimumSize, bounds.height >= minimumSize else { return nil }
            return PickableWindow(windowID: windowID, ownerPID: pid, globalFrame: bounds)
        }
    }

    /// Converts a CG global-coordinate rect (origin top-left of the primary
    /// display, y-down) into a display's own local point space (origin
    /// top-left of that display), matching the space the overlay's
    /// `SelectionView` draws and stores selections in. Pure, so it is unit
    /// tested directly.
    static func localFrame(for globalFrame: CGRect, displayBounds: CGRect) -> CGRect {
        CGRect(
            x: globalFrame.minX - displayBounds.minX,
            y: globalFrame.minY - displayBounds.minY,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    /// The frontmost pickable window whose frame contains `point`, given in
    /// `displayID`'s own local point space.
    static func hitTest(_ point: CGPoint, in windows: [PickableWindow], displayID: CGDirectDisplayID) -> PickableWindow? {
        let bounds = CGDisplayBounds(displayID)
        return windows.first { localFrame(for: $0.globalFrame, displayBounds: bounds).contains(point) }
    }
}
