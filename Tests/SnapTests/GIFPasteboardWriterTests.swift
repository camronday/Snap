import AppKit
import Testing
@testable import Snap

@MainActor
struct GIFPasteboardWriterTests {
    @Test func writesBothGIFDataAndFileURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFPasteboardWriterTests-\(UUID().uuidString).gif")
        try Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]).write(to: url) // "GIF89a" header is enough for this test
        defer { try? FileManager.default.removeItem(at: url) }

        let pasteboard = NSPasteboard(name: .init("SnapGIFTests"))
        try GIFPasteboardWriter.write(fileURL: url, to: pasteboard)

        let gifData = pasteboard.data(forType: GIFPasteboardWriter.gifType)
        #expect(gifData != nil)

        let fileURLString = pasteboard.string(forType: .fileURL)
        #expect(fileURLString == url.absoluteString)
    }
}
