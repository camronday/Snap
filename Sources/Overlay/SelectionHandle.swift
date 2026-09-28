import CoreGraphics

/// The 8 resize handles around a selection rect, in display-local points.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var affectsMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var affectsMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var affectsMinY: Bool { self == .topLeft || self == .top || self == .topRight }
    var affectsMaxY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Resizes `original` by dragging this handle to `location`.
    func resize(_ original: CGRect, to location: CGPoint) -> CGRect {
        var rect = original
        if affectsMinX {
            rect.origin.x = location.x
            rect.size.width = original.maxX - location.x
        }
        if affectsMaxX {
            rect.size.width = location.x - original.minX
        }
        if affectsMinY {
            rect.origin.y = location.y
            rect.size.height = original.maxY - location.y
        }
        if affectsMaxY {
            rect.size.height = location.y - original.minY
        }
        return rect.standardized
    }

    static func hitTest(_ point: CGPoint, in rect: CGRect, tolerance: CGFloat = 10) -> SelectionHandle? {
        allCases.first {
            let handlePoint = $0.position(in: rect)
            return abs(handlePoint.x - point.x) <= tolerance && abs(handlePoint.y - point.y) <= tolerance
        }
    }
}
