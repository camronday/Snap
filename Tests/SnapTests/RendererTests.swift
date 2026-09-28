import CoreGraphics
import Testing
@testable import Snap

struct RendererTests {
    private static func makeBaseImage(pixelSize: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        return context.makeImage()!
    }

    @Test func outputPixelSizeMatchesOutputScale() async throws {
        // A 50x50pt display captured at 2x looks like a 100x100px image.
        let base = Self.makeBaseImage(pixelSize: 100)
        let crop = CGRect(x: 0, y: 0, width: 50, height: 50)

        let at2x = try await Renderer.render(items: [], base: base, crop: crop, baseScale: 2, outputScale: 2)
        #expect(at2x.width == 100)
        #expect(at2x.height == 100)

        let at1x = try await Renderer.render(items: [], base: base, crop: crop, baseScale: 2, outputScale: 1)
        #expect(at1x.width == 50)
        #expect(at1x.height == 50)
    }

    /// Top half red, bottom half blue (a y-up bitmap context, so the top half is high y).
    private static func makeTwoToneImage(pixelSize: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let half = CGFloat(pixelSize) / 2
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelSize), height: half))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: half, width: CGFloat(pixelSize), height: half))
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) with y measured from the top.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        return (data[i], data[i + 1], data[i + 2])
    }

    @Test func outputKeepsImageUpright() async throws {
        let base = Self.makeTwoToneImage(pixelSize: 100)

        let full = try await Renderer.render(items: [], base: base, crop: CGRect(x: 0, y: 0, width: 50, height: 50), baseScale: 2, outputScale: 2)
        #expect(Self.pixel(full, x: 50, y: 5).r > 200)
        #expect(Self.pixel(full, x: 50, y: 95).b > 200)

        // A crop of the top half (top-left origin points) must be all red.
        let top = try await Renderer.render(items: [], base: base, crop: CGRect(x: 0, y: 0, width: 50, height: 25), baseScale: 2, outputScale: 2)
        #expect(Self.pixel(top, x: 50, y: 2).r > 200)
        #expect(Self.pixel(top, x: 50, y: 47).r > 200)
    }
}
