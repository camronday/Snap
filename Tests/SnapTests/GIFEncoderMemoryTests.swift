import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
@testable import Snap

/// `GIFEncoder` splices each frame in as its own single-frame GIF (ImageIO
/// still does the quantising and LZW work per frame) instead of handing the
/// whole recording to one `CGImageDestination`, whose `finalize()` used to
/// materialise the entire frame corpus at once. This checks that a
/// realistic-length recording no longer grows resident memory with frame
/// count: encoding and appending should stay within a small, roughly
/// constant budget regardless of how many frames have already been
/// written.
struct GIFEncoderMemoryTests {
    @Test func peakMemoryGrowthStaysUnderBudget() async throws {
        let frameCount = 450
        let width = 800
        let height = 600

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFEncoderMemoryTests-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = try GIFEncoder(url: url)

        let before = Self.residentMemoryBytes()
        var peak = before

        for i in 0..<frameCount {
            let image = try Self.makeFrame(width: width, height: height, seed: i)
            await encoder.append(image: image, delay: 1.0 / 15.0)
            peak = max(peak, Self.residentMemoryBytes())
        }

        try await encoder.finalize()
        peak = max(peak, Self.residentMemoryBytes())

        let peakGrowthMB = Double(peak - before) / 1_048_576
        print("[GIFEncoderMemoryTests] frames=\(frameCount) \(width)x\(height): peak resident growth = \(String(format: "%.1f", peakGrowthMB)) MB")

        #expect(peakGrowthMB < 150, "peak growth was \(peakGrowthMB) MB, expected the splice encoder to hold ~O(1 frame) resident")

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == frameCount)
    }

    private static func makeFrame(width: Int, height: Int, seed: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Distinct content per frame (rather than one reused CGImage) so the
        // test can't accidentally pass just because ImageIO dedupes an
        // identical image reference, and so per-frame quantisation work is
        // realistic rather than trivially cached.
        let hue = CGFloat(seed % 255) / 255
        context.setFillColor(CGColor(red: hue, green: 1 - hue, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 1 - hue, green: hue, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
