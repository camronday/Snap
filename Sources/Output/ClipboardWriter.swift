import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Puts a rendered capture on the pasteboard as PNG and TIFF, tagged with a
/// DPI that matches the requested output scale so other apps paste it at the
/// right point size.
enum ClipboardWriter {
    struct WriteError: Error {}

    static func write(_ image: CGImage, outputScale: CGFloat, to pasteboard: NSPasteboard = .general) throws {
        let dpi = 72.0 * outputScale
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw WriteError()
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WriteError() }

        let pointSize = NSSize(width: CGFloat(image.width) / outputScale, height: CGFloat(image.height) / outputScale)
        let nsImage = NSImage(cgImage: image, size: pointSize)

        pasteboard.clearContents()
        pasteboard.setData(data as Data, forType: .png)
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
