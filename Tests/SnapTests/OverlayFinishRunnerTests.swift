import CoreGraphics
import Testing
@testable import Snap

/// `OverlayFinishRunner.run(.save, ...)` must close the overlay panels
/// *before* handing the rendered image to the save presenter, or
/// `NSSavePanel` opens behind the `.screenSaver`-level overlay. This drives
/// it with a fake presenter (never a real `NSSavePanel`) and records the
/// order the two injected closures fire in.
@MainActor
struct OverlayFinishRunnerTests {
    @Test func saveClosesTheOverlayBeforePresentingTheSavePanel() async throws {
        let display = FrozenDisplay(
            displayID: 0,
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            image: try Self.makeImage()
        )
        let session = OverlaySession(frozenDisplays: [display])
        session.selection = CGRect(x: 0, y: 0, width: 20, height: 20)

        let recorder = EventRecorder()

        await withCheckedContinuation { continuation in
            OverlayFinishRunner.run(
                .save,
                session: session,
                outputScale: 1,
                presentSave: { _ in
                    recorder.events.append("present")
                    continuation.resume()
                    return nil
                },
                close: {
                    recorder.events.append("close")
                }
            )
        }

        #expect(recorder.events == ["close", "present"])
    }

    private static func makeImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        return try #require(context.makeImage())
    }
}

/// Plain call-order recorder; everything here runs on `MainActor` within a
/// single `Task`, so no synchronization beyond that is needed.
@MainActor
private final class EventRecorder {
    var events: [String] = []
}
