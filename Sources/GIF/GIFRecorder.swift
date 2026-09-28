import AppKit
@preconcurrency import ScreenCaptureKit
import os

/// Captures one region of one display as a sequence of frames via `SCStream`
/// and feeds them to a `GIFEncoder` as they arrive. One instance per
/// recording; fully torn down in `stop()` so nothing lingers at idle.
actor GIFRecorder {
    struct StartError: Error {}

    struct Result: Sendable {
        let url: URL
        let duration: TimeInterval
        let fileSize: Int
    }

    private static let frameInterval = CMTime(value: 1, timescale: 15)
    private static let queueLabel = "com.cameronro.Snap.GIFRecorder"
    /// `GIFEncoder` streams frames straight to disk, so memory no longer
    /// scales with recording length or frame size. This cap stays for the
    /// encoded file's own size and decode cost: a very large or
    /// multi-display selection would otherwise produce an unreasonably
    /// heavy GIF. It doesn't bound frame count, which `gifMaxDuration`
    /// handles instead.
    private static let maxEncodedDimension: CGFloat = 1280

    private var stream: SCStream?
    private var delegate: StreamDelegate?
    private var encoder: GIFEncoder?
    /// The most recent complete frame, held back until either the next
    /// complete frame arrives (so its delay can be computed) or `stop()` is
    /// called. Any idle frames in between are simply skipped, which is what
    /// naturally "extends" the previous frame's delay.
    private var pendingFrame: CapturedPixelBuffer?
    private var lastDelay: TimeInterval = 1.0 / 15.0
    /// Sum of the delays actually written to the encoder, kept alongside
    /// `frameCount` rather than recomputed from it: frames can be skipped as
    /// idle, so a per-frame duration times frame count wouldn't match what
    /// was really encoded.
    private var totalDuration: TimeInterval = 0
    /// The callback runs on its own serial queue and could otherwise reach
    /// the actor as several independent, unordered `Task`s; funnelling every
    /// frame through one stream and one long-lived consumer task keeps
    /// arrival order intact.
    private var frameContinuation: AsyncStream<(CapturedPixelBuffer, Bool)>.Continuation?
    private var consumerTask: Task<Void, Never>?

    func start(displayID: CGDirectDisplayID, selection: CGRect) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw StartError()
        }
        // Inlined (rather than calling `ScreenFreezer.excludingOwnApp`,
        // which is main-actor-isolated) since `[SCRunningApplication]` isn't
        // `Sendable` and can't cross back into this actor.
        let ownApp = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let excluded = ownApp.map { [$0] } ?? []
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let downscale = min(1, Self.maxEncodedDimension / max(selection.width, selection.height))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection
        configuration.width = max(1, Int((selection.width * downscale).rounded()))
        configuration.height = max(1, Int((selection.height * downscale).rounded()))
        configuration.minimumFrameInterval = Self.frameInterval
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3

        let encoder = try GIFEncoder()
        self.encoder = encoder

        let (frames, continuation) = AsyncStream<(CapturedPixelBuffer, Bool)>.makeStream()
        self.frameContinuation = continuation

        let delegate = StreamDelegate { frame, isComplete in
            continuation.yield((frame, isComplete))
        }
        self.delegate = delegate

        self.consumerTask = Task { [weak self] in
            for await (frame, isComplete) in frames {
                guard let self else { break }
                await self.ingest(frame, isComplete: isComplete)
            }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
        try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue(label: Self.queueLabel))
        try await stream.startCapture()
        self.stream = stream
    }

    private func ingest(_ frame: CapturedPixelBuffer, isComplete: Bool) async {
        guard isComplete, let encoder else { return }
        if let pending = pendingFrame {
            let delay = max(CMTimeGetSeconds(frame.time) - CMTimeGetSeconds(pending.time), GIFEncoder.minimumDelay)
            lastDelay = delay
            await encoder.append(pending, delay: delay)
            totalDuration += delay
        }
        pendingFrame = frame
    }

    /// Stops and releases the stream, flushes the held-back last frame and
    /// finalises the file. Returns nil if nothing usable was captured.
    func stop() async -> Result? {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        delegate = nil

        frameContinuation?.finish()
        frameContinuation = nil
        await consumerTask?.value
        consumerTask = nil

        guard let encoder else { return nil }
        if let pending = pendingFrame {
            await encoder.append(pending, delay: lastDelay)
            totalDuration += lastDelay
        }
        pendingFrame = nil
        self.encoder = nil

        guard let output = try? await encoder.finalize() else { return nil }
        return Result(url: output.url, duration: totalDuration, fileSize: output.fileSize)
    }
}

/// The `SCStreamOutput`/`SCStreamDelegate` object, living on its own serial
/// queue; forwards each complete frame's pixel buffer and timestamp back to
/// the actor rather than holding any state itself.
nonisolated final class StreamDelegate: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let onFrame: @Sendable (CapturedPixelBuffer, Bool) -> Void

    init(onFrame: @escaping @Sendable (CapturedPixelBuffer, Bool) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame(CapturedPixelBuffer(pixelBuffer: pixelBuffer, time: time), sampleBuffer.frameStatus == .complete)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger(subsystem: "com.cameronro.Snap", category: "capture").error("GIF stream stopped with error: \(error.localizedDescription)")
    }
}

private extension CMSampleBuffer {
    nonisolated var frameStatus: SCFrameStatus {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw) else {
            return .idle
        }
        return status
    }
}
