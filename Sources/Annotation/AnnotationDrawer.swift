import AppKit
import CoreGraphics
import CoreText

/// Draws annotations into a `CGContext`, used by both the live SwiftUI
/// `Canvas` (via `context.withCGContext`) and the export `Renderer`, so the
/// preview and the saved/copied image always match pixel for pixel.
///
/// The context must already be top-left origin, y-down, in points, with any
/// output-resolution scale already applied to its CTM by the caller. That is
/// what `Canvas` gives for free, and what `Renderer` sets up by hand.
nonisolated enum AnnotationDrawer {
    static func draw(_ items: [Annotation], in context: CGContext, base: CGImage, crop: CGRect, scale: CGFloat, override: WindowImageOverride? = nil) {
        context.saveGState()
        context.translateBy(x: -crop.origin.x, y: -crop.origin.y)

        let pixelRect = CGRect(
            x: crop.origin.x * scale,
            y: crop.origin.y * scale,
            width: crop.width * scale,
            height: crop.height * scale
        ).integral
        if let visible = base.cropping(to: pixelRect) {
            drawImage(visible, in: crop, context: context)
        }

        drawOverride(override, in: context, crop: crop)

        for item in items {
            drawOne(item, in: context)
        }
        context.restoreGState()
    }

    /// `CGContext.draw` assumes a y-up space; our context is y-down, so flip
    /// locally around `rect` or images render upside down.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// Patches in a window's own capture over the part of `crop` it covers,
    /// so a window pick shows the unobscured, shadow-free window image
    /// (with its transparent corners) instead of the frozen desktop.
    private static func drawOverride(_ override: WindowImageOverride?, in context: CGContext, crop: CGRect) {
        guard let override else { return }
        let overlap = crop.intersection(override.frame)
        guard !overlap.isNull else { return }

        let localPixelRect = CGRect(
            x: (overlap.minX - override.frame.minX) * override.scale,
            y: (overlap.minY - override.frame.minY) * override.scale,
            width: overlap.width * override.scale,
            height: overlap.height * override.scale
        ).integral
        guard let patch = override.image.cropping(to: localPixelRect) else { return }
        drawImage(patch, in: overlap, context: context)
    }

    private static func drawOne(_ item: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(item.colour.cgColor)
        context.setFillColor(item.colour.cgColor)

        switch item.kind {
        case .rectangle:
            context.setLineWidth(Annotation.strokeWidth)
            context.stroke(item.rect)

        case .arrow:
            drawArrow(item, in: context)

        case .freehand:
            context.setLineWidth(Annotation.strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            strokePath(item.points, in: context)

        case .highlight:
            context.setAlpha(Annotation.highlightOpacity)
            context.setLineWidth(Annotation.highlightWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            // One stroke call for the whole path so overlapping segments
            // don't darken where the marker doubles back on itself.
            strokePath(item.points, in: context)

        case .text:
            drawText(item, in: context)

        case .blur, .pixelate:
            if let patch = item.filteredPatch {
                drawImage(patch, in: item.rect, context: context)
            } else {
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 3])
                context.stroke(item.rect)
            }

        case .callout:
            drawCallout(item, in: context)
        }
    }

    private static func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func drawArrow(_ item: Annotation, in context: CGContext) {
        guard item.points.count >= 2 else { return }
        let start = item.points[0]
        let end = item.points[1]
        context.setLineWidth(Annotation.strokeWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 14
        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let right = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        context.beginPath()
        context.move(to: end)
        context.addLine(to: left)
        context.move(to: end)
        context.addLine(to: right)
        context.strokePath()
    }

    private static func drawText(_ item: Annotation, in context: CGContext) {
        guard !item.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: Annotation.textFontSize, weight: .semibold)
        let attributed = NSAttributedString(string: item.text, attributes: [
            .font: font,
            .foregroundColor: item.colour.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)

        // Core Text's own convention draws upward from the text position in
        // a non-flipped space; counter the outer top-left flip locally so
        // glyphs land right-side up at `origin`.
        context.translateBy(x: item.origin.x, y: item.origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
    }

    private static func drawCallout(_ item: Annotation, in context: CGContext) {
        let radius = Annotation.calloutDiameter / 2
        let circleRect = CGRect(x: item.origin.x - radius, y: item.origin.y - radius, width: Annotation.calloutDiameter, height: Annotation.calloutDiameter)
        context.fillEllipse(in: circleRect)

        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
        let attributed = NSAttributedString(string: "\(item.calloutNumber)", attributes: [
            .font: font,
            .foregroundColor: NSColor.white.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        context.translateBy(x: item.origin.x - bounds.width / 2, y: item.origin.y + bounds.height / 2)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
    }
}
