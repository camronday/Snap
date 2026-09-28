import CoreGraphics

/// Shared drag logic for an in-progress annotation, used by both the
/// overlay's `SelectionView` and the clipboard editor's `EditorCanvasView`.
nonisolated enum AnnotationStroke {
    /// Starts a new annotation of `kind` at the drag's first point.
    static func begin(kind: AnnotationKind, colour: RGBAColour, at point: CGPoint) -> Annotation {
        var annotation = Annotation(kind: kind, colour: colour)
        switch kind {
        case .rectangle, .blur, .pixelate:
            annotation.rect = CGRect(origin: point, size: .zero)
        case .arrow:
            annotation.points = [point, point]
        case .freehand, .highlight:
            annotation.points = [point]
        default:
            break
        }
        return annotation
    }

    /// Grows `annotation` as the drag continues to `point`.
    static func update(_ annotation: inout Annotation, to point: CGPoint) {
        switch annotation.kind {
        case .rectangle, .blur, .pixelate:
            let start = annotation.rect.origin
            annotation.rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        case .arrow:
            if annotation.points.count >= 2 {
                annotation.points[1] = point
            }
        case .freehand, .highlight:
            annotation.points.append(point)
        default:
            break
        }
    }
}
