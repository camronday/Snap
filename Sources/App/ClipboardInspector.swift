import AppKit

/// Checks pasteboard contents for menu item enablement.
enum ClipboardInspector {
    static var hasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// The best available image on the pasteboard, with its true pixel size
    /// (from the bitmap representation) and the point size to display it at.
    /// The point size is derived from the same width-based scale factor for
    /// both dimensions, so an inconsistent DPI tag can't distort the aspect
    /// ratio.
    static func bestImage() -> (image: CGImage, pointSize: CGSize)? {
        guard let nsImage = NSImage(pasteboard: .general),
              let rep = nsImage.representations.compactMap({ $0 as? NSBitmapImageRep })
                  .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
              let cgImage = rep.cgImage
        else { return nil }

        let pixelWidth = CGFloat(rep.pixelsWide)
        let pixelHeight = CGFloat(rep.pixelsHigh)
        let scale = nsImage.size.width > 0 ? pixelWidth / nsImage.size.width : 1
        let pointSize = CGSize(width: pixelWidth / scale, height: pixelHeight / scale)
        return (cgImage, pointSize)
    }
}
