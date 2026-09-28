import AppKit

/// Puts a finished GIF on the pasteboard as raw `com.compuserve.gif` data
/// AND its file URL, both on one `NSPasteboardItem`, so Slack and browsers
/// that only look for one or the other both see it.
enum GIFPasteboardWriter {
    struct WriteError: Error {}

    static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

    static func write(fileURL: URL, to pasteboard: NSPasteboard = .general) throws {
        let data = try Data(contentsOf: fileURL)
        let item = NSPasteboardItem()
        item.setData(data, forType: gifType)
        item.setString(fileURL.absoluteString, forType: .fileURL)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw WriteError() }
    }
}
