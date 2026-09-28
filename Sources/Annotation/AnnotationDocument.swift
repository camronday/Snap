import CoreGraphics
import Foundation

/// The set of annotations for one capture, with its own value-type undo
/// history (array snapshots, not `NSUndoManager`).
struct AnnotationDocument: @unchecked Sendable {
    private(set) var items: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var nextCalloutNumber: Int {
        items.filter { $0.kind == .callout }.count + 1
    }

    /// Commits a new annotation, pushing an undo step.
    mutating func add(_ annotation: Annotation) {
        undoStack.append(items)
        redoStack.removeAll()
        items.append(annotation)
    }

    /// Replaces the in-progress last item without pushing an undo step, for
    /// live updates while a drag is still happening.
    mutating func updateLast(_ transform: (inout Annotation) -> Void) {
        guard var last = items.popLast() else { return }
        transform(&last)
        items.append(last)
    }

    /// Patches one item in place by id, without touching the undo stack.
    /// Used to fill in a blur/pixelate patch once it finishes computing.
    mutating func update(id: UUID, _ transform: (inout Annotation) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index])
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }

    /// Clears everything, e.g. when the selection moves to another display.
    mutating func clear() {
        items = []
        undoStack = []
        redoStack = []
    }
}
