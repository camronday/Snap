import CoreGraphics
import Testing
@testable import Snap

struct AnnotationDocumentTests {
    @Test func addAndUndoRedo() {
        var document = AnnotationDocument()
        #expect(document.canUndo == false)

        document.add(Annotation(kind: .rectangle, colour: .red))
        #expect(document.items.count == 1)
        #expect(document.canUndo)
        #expect(document.canRedo == false)

        document.undo()
        #expect(document.items.isEmpty)
        #expect(document.canRedo)

        document.redo()
        #expect(document.items.count == 1)
    }

    @Test func calloutNumberingIncrementsAndUndoDecrements() {
        var document = AnnotationDocument()
        #expect(document.nextCalloutNumber == 1)

        var first = Annotation(kind: .callout, colour: .red)
        first.calloutNumber = document.nextCalloutNumber
        document.add(first)
        #expect(document.nextCalloutNumber == 2)

        var second = Annotation(kind: .callout, colour: .red)
        second.calloutNumber = document.nextCalloutNumber
        document.add(second)
        #expect(document.nextCalloutNumber == 3)

        document.undo()
        #expect(document.nextCalloutNumber == 2)
    }

    @Test func updateLastDoesNotPushAnUndoStep() {
        var document = AnnotationDocument()
        document.add(Annotation(kind: .freehand, colour: .red))
        let undoStackDepthBefore = document.canUndo

        document.updateLast { $0.points.append(CGPoint(x: 1, y: 1)) }

        #expect(document.canUndo == undoStackDepthBefore)
        #expect(document.items.last?.points.count == 1)

        document.undo()
        #expect(document.items.isEmpty)
    }
}
