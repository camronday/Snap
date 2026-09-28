import AppKit
@preconcurrency import ScreenCaptureKit

/// Captures every connected display at once, "freezing" the desktop so the
/// overlay can draw on top while the real screen keeps updating underneath.
enum ScreenFreezer {
    struct FreezeError: Error {}

    private struct Job {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let scale: CGFloat
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    /// So overlay panels, the recording border and the like never show up in
    /// their own screenshots/streams.
    static func excludingOwnApp(from content: SCShareableContent) -> [SCRunningApplication] {
        content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }.map { [$0] } ?? []
    }

    static func freezeAllDisplays() async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.current
        let excluded = excludingOwnApp(from: content)

        // Content filters are built up front, one per display, so the task
        // group below only has to "send" a distinct instance into each
        // concurrent child task rather than share one across all of them.
        let jobs: [Job] = content.displays.compactMap { display in
            guard let screen = NSScreen.screens.first(where: { $0.directDisplayID == display.displayID }) else {
                return nil
            }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            // SCDisplay.width/height are points; ask for native pixels or
            // Retina captures come out at 1x and look soft.
            let pixelScale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * pixelScale).rounded())
            configuration.height = Int((filter.contentRect.height * pixelScale).rounded())
            configuration.captureResolution = .best
            configuration.showsCursor = false
            return Job(displayID: display.displayID, frame: screen.frame, scale: screen.backingScaleFactor, filter: filter, configuration: configuration)
        }

        return try await withThrowingTaskGroup(of: FrozenDisplay.self) { group in
            for job in jobs {
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: job.filter, configuration: job.configuration)
                    // Derive the scale from the pixels actually returned so crops can never miss the image.
                    let scale = job.frame.width > 0 ? CGFloat(image.width) / job.frame.width : job.scale
                    return FrozenDisplay(displayID: job.displayID, frame: job.frame, scale: scale, image: image)
                }
            }
            var results: [FrozenDisplay] = []
            for try await result in group {
                results.append(result)
            }
            guard !results.isEmpty else { throw FreezeError() }
            return results
        }
    }
}
