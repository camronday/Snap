import AppKit
import SwiftUI

/// Colour stored as plain components so it survives undo snapshots and
/// draws identically in the live preview and the exported image.
nonisolated struct RGBAColour: Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let red = RGBAColour(red: 1, green: 0, blue: 0, alpha: 1)

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        func byte(_ value: Double) -> String {
            String(format: "%02X", max(0, min(255, Int(value * 255))))
        }
        return byte(red) + byte(green) + byte(blue) + byte(alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        red = ns.redComponent
        green = ns.greenComponent
        blue = ns.blueComponent
        alpha = ns.alphaComponent
    }

    init?(hexString: String) {
        guard hexString.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&value) else { return nil }
        red = Double((value >> 24) & 0xFF) / 255
        green = Double((value >> 16) & 0xFF) / 255
        blue = Double((value >> 8) & 0xFF) / 255
        alpha = Double(value & 0xFF) / 255
    }
}

nonisolated enum AnnotationKind: String, CaseIterable, Sendable {
    case rectangle, arrow, freehand, highlight, text, blur, pixelate, callout

    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .freehand: "scribble"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .blur: "drop.degreesign"
        case .pixelate: "square.grid.3x3.fill"
        case .callout: "circle.fill"
        }
    }

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .freehand: "Freehand"
        case .highlight: "Highlight"
        case .text: "Text"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .callout: "Callout"
        }
    }

    /// Blur/pixelate need the base image pixels; the rest just draw shapes.
    var needsFilteredPatch: Bool { self == .blur || self == .pixelate }
}

/// One drawn element. A single struct (rather than an enum with per-case
/// payloads) so the document can cheaply "update the last item" while
/// dragging, and so blur/pixelate can cache their filtered patch in place.
nonisolated struct Annotation: Identifiable, @unchecked Sendable {
    static let strokeWidth: CGFloat = 3
    static let highlightWidth: CGFloat = 18
    static let highlightOpacity: Double = 0.35
    static let textFontSize: CGFloat = 18
    static let calloutDiameter: CGFloat = 28

    let id: UUID
    var kind: AnnotationKind
    var colour: RGBAColour

    /// Rectangle / blur / pixelate bounds.
    var rect: CGRect = .zero
    /// Arrow (2 points) / freehand / highlight path, display-local points.
    var points: [CGPoint] = []
    /// Text contents and top-left origin of its bounding box.
    var text: String = ""
    var origin: CGPoint = .zero
    /// Callout number, 1-based.
    var calloutNumber: Int = 0
    /// Rasterised blur/pixelate result for `rect`, computed once the drag
    /// that created or resized it ends, so live drawing stays cheap.
    var filteredPatch: CGImage?

    init(kind: AnnotationKind, colour: RGBAColour) {
        id = UUID()
        self.kind = kind
        self.colour = colour
    }
}
