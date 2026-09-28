import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `CVPixelBuffer` isn't `Sendable`, but each captured frame is only ever
/// touched by one owner at a time (the stream's dedicated queue, then the
/// recorder actor, then the encoder actor), so it's safe to hand across
/// those boundaries wrapped like this, the same pattern `FrozenDisplay` and
/// `WindowImageOverride` use for `CGImage`.
nonisolated struct CapturedPixelBuffer: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let time: CMTime
}

/// One frame's worth of GIF container bytes, parsed out of a single-frame
/// GIF that ImageIO produced for that frame alone.
private struct ParsedGIFFrame: Sendable {
    let canvasWidth: Int
    let canvasHeight: Int
    let left: Int
    let top: Int
    let width: Int
    let height: Int
    let interlaced: Bool
    let colorTableSizeBits: UInt8
    let colorTable: [UInt8]
    let lzwMinimumCodeSize: UInt8
    /// Raw sub-blocks (length byte + data, repeated) including the trailing
    /// zero-length terminator, copied verbatim: the LZW codes reference the
    /// colour table we're carrying alongside them, so they stay valid no
    /// matter where that table ends up living in the spliced file.
    let imageDataBlocks: [UInt8]
}

/// Encodes each frame alone with ImageIO (reusing its quantiser and LZW
/// encoder per frame) and splices the result into one long-lived GIF file,
/// rather than handing every frame to a single `CGImageDestination` whose
/// `finalize()` materialises the whole frame corpus at once. See
/// `GIFSplice` for the byte-level GIF89a parsing and writing this relies on.
private nonisolated enum GIFSplice {
    static func encodeSingleFrame(_ image: CGImage) throws -> ParsedGIFFrame {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil) else {
            throw GIFEncoder.EncodeError()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GIFEncoder.EncodeError() }
        return try parse(data as Data)
    }

    /// Walks a GIF89a byte stream: header, logical screen descriptor (plus
    /// its optional global colour table), then extension blocks (skipped,
    /// since we write our own graphic control extension and don't need
    /// ImageIO's application/comment ones), then the single image
    /// descriptor (plus its own colour table, global or local).
    static func parse(_ data: Data) throws -> ParsedGIFFrame {
        let bytes = [UInt8](data)
        var i = 0
        func readByte() throws -> UInt8 {
            guard i < bytes.count else { throw GIFEncoder.EncodeError() }
            defer { i += 1 }
            return bytes[i]
        }
        func readUInt16() throws -> Int {
            let lo = try readByte()
            let hi = try readByte()
            return Int(lo) | (Int(hi) << 8)
        }
        func readBytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, i + count <= bytes.count else { throw GIFEncoder.EncodeError() }
            defer { i += count }
            return Array(bytes[i..<(i + count)])
        }

        guard bytes.count > 13 else { throw GIFEncoder.EncodeError() }
        i = 6 // "GIF87a" / "GIF89a"

        let canvasWidth = try readUInt16()
        let canvasHeight = try readUInt16()
        let lsdPacked = try readByte()
        _ = try readByte() // background colour index
        _ = try readByte() // pixel aspect ratio

        var globalColorTable: [UInt8]?
        var globalSizeBits: UInt8 = 0
        if lsdPacked & 0x80 != 0 {
            globalSizeBits = lsdPacked & 0x07
            globalColorTable = try readBytes(3 * (2 << Int(globalSizeBits)))
        }

        while true {
            let marker = try readByte()
            if marker == 0x21 {
                _ = try readByte() // extension label
                while true {
                    let size = try readByte()
                    if size == 0 { break }
                    _ = try readBytes(Int(size))
                }
            } else if marker == 0x2C {
                break
            } else {
                throw GIFEncoder.EncodeError()
            }
        }

        let left = try readUInt16()
        let top = try readUInt16()
        let width = try readUInt16()
        let height = try readUInt16()
        let idPacked = try readByte()
        let interlaced = idPacked & 0x40 != 0

        let colorTableSizeBits: UInt8
        let colorTable: [UInt8]
        if idPacked & 0x80 != 0 {
            colorTableSizeBits = idPacked & 0x07
            colorTable = try readBytes(3 * (2 << Int(colorTableSizeBits)))
        } else if let globalColorTable {
            colorTableSizeBits = globalSizeBits
            colorTable = globalColorTable
        } else {
            throw GIFEncoder.EncodeError()
        }

        let lzwMinimumCodeSize = try readByte()
        var imageDataBlocks: [UInt8] = []
        while true {
            let size = try readByte()
            imageDataBlocks.append(size)
            if size == 0 { break }
            imageDataBlocks.append(contentsOf: try readBytes(Int(size)))
        }

        return ParsedGIFFrame(
            canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            left: left, top: top, width: width, height: height,
            interlaced: interlaced,
            colorTableSizeBits: colorTableSizeBits, colorTable: colorTable,
            lzwMinimumCodeSize: lzwMinimumCodeSize, imageDataBlocks: imageDataBlocks
        )
    }

    /// File-level header: signature, logical screen descriptor sized to the
    /// canvas with no global colour table (every frame carries its own
    /// local one), and a NETSCAPE2.0 extension looping forever.
    static func header(canvasWidth: Int, canvasHeight: Int) -> Data {
        var out = Data()
        out.append(contentsOf: Array("GIF89a".utf8))
        appendUInt16(&out, canvasWidth)
        appendUInt16(&out, canvasHeight)
        out.append(contentsOf: [0x00, 0x00, 0x00]) // no global colour table, bg index, pixel aspect ratio
        out.append(contentsOf: [0x21, 0xFF, 0x0B])
        out.append(contentsOf: Array("NETSCAPE2.0".utf8))
        out.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
        return out
    }

    /// One frame: our own graphic control extension carrying the delay,
    /// then the image descriptor with the colour table moved to local,
    /// then the table and LZW data untouched.
    static func frame(_ frame: ParsedGIFFrame, delay: TimeInterval) -> Data {
        var out = Data()
        let centiseconds = UInt16(clamping: Int((max(delay, GIFEncoder.minimumDelay) * 100).rounded()))
        out.append(contentsOf: [0x21, 0xF9, 0x04, 0x04]) // extension, GCE label, block size, disposal 1
        out.append(UInt8(centiseconds & 0xFF))
        out.append(UInt8(centiseconds >> 8))
        out.append(contentsOf: [0x00, 0x00]) // transparent index, block terminator

        out.append(0x2C)
        appendUInt16(&out, frame.left)
        appendUInt16(&out, frame.top)
        appendUInt16(&out, frame.width)
        appendUInt16(&out, frame.height)
        var packed: UInt8 = 0x80 | (frame.colorTableSizeBits & 0x07)
        if frame.interlaced { packed |= 0x40 }
        out.append(packed)

        out.append(contentsOf: frame.colorTable)
        out.append(frame.lzwMinimumCodeSize)
        out.append(contentsOf: frame.imageDataBlocks)
        return out
    }

    private static func appendUInt16(_ data: inout Data, _ value: Int) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
}

/// Encodes GIF frames incrementally as they arrive, splicing each one
/// straight onto an open file handle so memory stays O(1 frame) regardless
/// of recording length; see `GIFSplice`. One instance per recording;
/// `finalize()` closes it out.
actor GIFEncoder {
    struct EncodeError: Error {}

    struct Output: Sendable {
        let url: URL
        let frameCount: Int
        let fileSize: Int
    }

    /// GIF's practical floor: most viewers treat anything shorter as 0.1 s.
    static let minimumDelay: TimeInterval = 0.05

    let url: URL
    private let fileHandle: FileHandle
    private let ciContext = CIContext()
    private(set) var frameCount = 0
    private var finalized = false
    private var headerWritten = false
    /// The most recently encoded frame, held back one step: it's only
    /// written once this call (or `finalize`) confirms nothing more needs
    /// to be coalesced into it.
    private var pending: (frame: ParsedGIFFrame, delay: TimeInterval)?

    init(url: URL = GIFEncoder.makeTemporaryURL()) throws {
        self.url = url
        // 0600: this file holds a decoded screen recording until it's
        // either copied to the pasteboard or explicitly saved, so it
        // shouldn't be readable by other users on the system.
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else { throw EncodeError() }
        guard let handle = try? FileHandle(forWritingTo: url) else { throw EncodeError() }
        self.fileHandle = handle
    }

    static func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString).gif")
    }

    /// Removes any `Snap-*.gif` temp files left behind by a previous run
    /// (e.g. after a crash, or a recording that was never copied/saved).
    /// Called at launch and again on quit so nothing lingers on disk.
    nonisolated static func removeOrphanedTemporaryFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("Snap-") && url.pathExtension == "gif" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Converts and appends a captured frame. Cheap conversion via Core
    /// Image rather than a manual pixel copy.
    func append(_ frame: CapturedPixelBuffer, delay: TimeInterval) {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        append(image: image, delay: delay)
    }

    /// Appends an already-rendered frame (also the path used by tests).
    func append(image: CGImage, delay: TimeInterval) {
        guard !finalized else { return }
        guard let parsed = try? GIFSplice.encodeSingleFrame(image) else { return }

        if !headerWritten {
            let header = GIFSplice.header(canvasWidth: parsed.canvasWidth, canvasHeight: parsed.canvasHeight)
            guard (try? fileHandle.write(contentsOf: header)) != nil else { return }
            headerWritten = true
        }

        if let pending {
            try? fileHandle.write(contentsOf: GIFSplice.frame(pending.frame, delay: pending.delay))
        }
        pending = (parsed, delay)
        frameCount += 1
    }

    @discardableResult
    func finalize() throws -> Output {
        guard !finalized else { throw EncodeError() }
        finalized = true
        guard frameCount > 0 else { throw EncodeError() }

        if let pending {
            try fileHandle.write(contentsOf: GIFSplice.frame(pending.frame, delay: pending.delay))
        }
        pending = nil
        try fileHandle.write(contentsOf: Data([0x3B]))
        try fileHandle.close()

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        return Output(url: url, frameCount: frameCount, fileSize: size)
    }
}
