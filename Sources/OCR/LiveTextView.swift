import AppKit
import SwiftUI
import VisionKit

/// Hosts VisionKit's Live Text overlay over the selection's cropped pixels,
/// so a line of text (or a URL, via data detectors) can be selected or
/// clicked in place instead of forcing a copy-all. Lives in the overlay's
/// un-gestured controls layer so the `ImageAnalysisOverlayView`'s own mouse
/// handling isn't swallowed by the selection's drag gesture.
struct LiveTextView: NSViewRepresentable {
    let image: CGImage
    let session: OverlaySession

    func makeNSView(context: Context) -> ContainerView {
        let container = ContainerView()

        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        container.addSubview(imageView)
        container.imageView = imageView

        let overlayView = ImageAnalysisOverlayView()
        overlayView.preferredInteractionTypes = [.textSelection, .dataDetectors]
        overlayView.trackingImageView = imageView
        container.addSubview(overlayView)
        container.overlayView = overlayView

        session.liveTextSelectedTextProvider = { [weak overlayView] in overlayView?.selectedText ?? "" }

        Task {
            do {
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
                let analysis = try await analyzer.analyze(image, orientation: .up, configuration: configuration)
                overlayView.analysis = analysis
            } catch {
                Log.capture.error("Live Text analysis failed: \(error.localizedDescription)")
            }
        }

        return container
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        nsView.imageView?.frame = nsView.bounds
        nsView.overlayView?.frame = nsView.bounds
    }

    /// Plain `NSView` host: lets the image view and the analysis overlay
    /// share exactly the same bounds, with no SwiftUI layout in between.
    final class ContainerView: NSView {
        weak var imageView: NSImageView?
        weak var overlayView: ImageAnalysisOverlayView?

        override func layout() {
            super.layout()
            imageView?.frame = bounds
            overlayView?.frame = bounds
        }
    }
}

/// The small glass pill shown alongside the Live Text overlay: "Copy All"
/// (via `TextRecognizer`, independent of any in-place selection) and "Done".
struct LiveTextControlPill: View {
    @Environment(OverlaySession.self) private var session

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button("Copy All") {
                    session.copyAllRecognizedText()
                }
                .buttonStyle(.glass)
                .help("Copy all recognised text")

                Button("Done") {
                    session.exitLiveTextMode()
                }
                .buttonStyle(.glassProminent)
                .help("Done (Esc)")
            }
            .padding(8)
        }
    }
}
