import AppKit
import CoreGraphics
import ImageIO
import Testing
@testable import Snap

@MainActor
struct ClipboardWriterTests {
    @Test func writesPNGAtTheRequestedDPI() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let image = context.makeImage()!

        let pasteboard = NSPasteboard(name: .init("SnapTests"))
        try ClipboardWriter.write(image, outputScale: 2, to: pasteboard)

        let data = try #require(pasteboard.data(forType: .png))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double

        #expect(dpi == 144)
    }
}
