import CoreGraphics

/// Flattens a capture's annotations onto its base image for export (clipboard
/// or save), at the requested output resolution.
enum Renderer {
    struct RenderError: Error {}

    @concurrent
    static func render(
        items: [Annotation],
        base: CGImage,
        crop: CGRect,
        baseScale: CGFloat,
        outputScale: CGFloat,
        override: WindowImageOverride? = nil
    ) async throws -> CGImage {
        let pixelWidth = Int((crop.width * outputScale).rounded())
        let pixelHeight = Int((crop.height * outputScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { throw RenderError() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError()
        }

        // Raw bitmap contexts are bottom-left, y-up by default; flip to
        // top-left, y-down, in points, matching the space annotations are
        // stored in and the space `Canvas` already gives the live preview.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: outputScale, y: -outputScale)

        AnnotationDrawer.draw(items, in: context, base: base, crop: crop, scale: baseScale, override: override)

        guard let image = context.makeImage() else { throw RenderError() }
        return image
    }
}
