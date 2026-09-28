import SwiftUI

/// Draws a base image plus its annotations (and an optional window-capture
/// patch) at a fixed size. Shared by the overlay's `SelectionView` (one per
/// display) and the clipboard image editor (one whole-image canvas), so the
/// live preview always matches the exported `Renderer` output pixel for pixel.
struct AnnotationCanvas: View {
    let base: CGImage
    let scale: CGFloat
    let crop: CGRect
    let items: [Annotation]
    var override: WindowImageOverride?

    var body: some View {
        Canvas { context, _ in
            context.withCGContext { cg in
                AnnotationDrawer.draw(items, in: cg, base: base, crop: crop, scale: scale, override: override)
            }
        }
        .frame(width: crop.width, height: crop.height)
    }
}
