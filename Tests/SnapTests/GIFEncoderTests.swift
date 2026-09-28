import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Snap

@MainActor
struct GIFEncoderTests {
    @Test func framesAndDelaysReadBackCorrectly() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFEncoderTests-\(UUID().uuidString).gif")
        let encoder = try GIFEncoder(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let delays: [Double] = [0.1, 0.2, 0.3]
        for delay in delays {
            await encoder.append(image: try makeImage(color: (1, 0, 0)), delay: delay)
        }
        try await encoder.finalize()

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == delays.count)

        for (index, expected) in delays.enumerated() {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            let readDelay = try #require(gifProperties[kCGImagePropertyGIFDelayTime] as? Double)
            #expect(abs(readDelay - expected) < 0.02)
        }
    }

    @Test func delayIsClampedToTheMinimum() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFEncoderTests-\(UUID().uuidString).gif")
        let encoder = try GIFEncoder(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await encoder.append(image: try makeImage(color: (0, 1, 0)), delay: 0.01)
        try await encoder.finalize()

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        let readDelay = try #require(gifProperties[kCGImagePropertyGIFDelayTime] as? Double)
        #expect(readDelay >= GIFEncoder.minimumDelay - 0.01)
    }

    @Test func loopCountAndDimensionsAreCorrect() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFEncoderTests-\(UUID().uuidString).gif")
        let encoder = try GIFEncoder(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await encoder.append(image: try makeImage(color: (0, 0, 1), size: 20), delay: 0.1)
        await encoder.append(image: try makeImage(color: (1, 1, 0), size: 20), delay: 0.1)
        try await encoder.finalize()

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)

        let properties = try #require(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        let loopCount = try #require(gifProperties[kCGImagePropertyGIFLoopCount] as? Int)
        #expect(loopCount == 0)

        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 20)
        #expect(image.height == 20)
    }

    private func makeImage(color: (r: CGFloat, g: CGFloat, b: CGFloat), size: Int = 8) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }
}
