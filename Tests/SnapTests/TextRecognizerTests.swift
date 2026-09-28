import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Snap

struct TextRecognizerTests {
    @Test func recognizesRenderedText() async throws {
        let image = Self.makeTestImage()
        let text = await TextRecognizer.recognize(image)
        #expect(text.contains("Hello Snap"))
    }

    private static func makeTestImage() -> CGImage {
        let width = 640, height = 160
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let attributed = NSAttributedString(string: "Hello Snap 123", attributes: [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 20, y: 60)
        CTLineDraw(line, context)

        return context.makeImage()!
    }
}
