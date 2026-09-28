import AppKit

/// A single display's screenshot plus enough geometry to place an overlay
/// panel over it and to map annotation coordinates back to pixels.
struct FrozenDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    /// The screen's frame in AppKit global coordinates (points), used to
    /// position the overlay panel.
    let frame: CGRect
    /// Pixels-per-point for this display, i.e. `NSScreen.backingScaleFactor`.
    let scale: CGFloat
    /// The captured frame, at `frame.size * scale` pixels.
    let image: CGImage

    /// Crops `image` to `rect` (in this display's local points), for uses
    /// that want the raw pixels without annotations, such as OCR.
    func croppedImage(for rect: CGRect) -> CGImage? {
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        return image.cropping(to: pixelRect)
    }

    /// Converts a rect in this display's local, top-left/y-down overlay
    /// space (as selections are stored) to AppKit's global, bottom-left/y-up
    /// screen space, for positioning a separate floating panel relative to
    /// the selection (the recording border and its pill).
    func globalRect(forLocal local: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x + local.origin.x,
            y: frame.origin.y + frame.height - local.origin.y - local.height,
            width: local.width,
            height: local.height
        )
    }
}

extension NSScreen {
    var directDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
