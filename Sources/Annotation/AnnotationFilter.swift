import CoreImage
import CoreGraphics

/// Renders the blur/pixelate patch for one annotation's rect against a
/// display's base image. Computed once per drag-end, then cached on the
/// annotation, so live drawing never re-runs a Core Image filter per frame.
nonisolated enum AnnotationFilter {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameters:
    ///   - rect: the annotation's rect, in the same display-local point
    ///     space as `base`'s coordinate origin.
    ///   - base: the full display image the rect was drawn over.
    ///   - scale: pixels-per-point of `base`.
    @concurrent
    static func makePatch(kind: AnnotationKind, rect: CGRect, base: CGImage, scale: CGFloat) async -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        guard let cropped = base.cropping(to: pixelRect) else { return nil }
        let input = CIImage(cgImage: cropped)

        let filter: CIFilter?
        switch kind {
        case .blur:
            filter = CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: input,
                kCIInputRadiusKey: 12,
            ])
        case .pixelate:
            filter = CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: input,
                kCIInputScaleKey: 12,
            ])
        default:
            filter = nil
        }

        guard let output = filter?.outputImage else { return nil }
        // Blur bleeds past the source extent; clamp back to it so the patch
        // stays exactly the rect's size with no transparent fringe.
        let clamped = output.clamped(to: input.extent).cropped(to: input.extent)
        return ciContext.createCGImage(clamped, from: input.extent)
    }
}
