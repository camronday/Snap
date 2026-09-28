import SwiftUI

/// The annotation surface inside the clipboard image editor: the same
/// `AnnotationCanvas` and drawing tools as the overlay, minus the
/// selection-creation/resize gestures, since the whole image is always the
/// selection here.
struct EditorCanvasView: View {
    @Environment(OverlaySession.self) private var session

    private var display: FrozenDisplay? { session.activeFrozenDisplay }

    var body: some View {
        if let display {
            ZStack(alignment: .topLeading) {
                AnnotationCanvas(
                    base: display.image,
                    scale: display.scale,
                    crop: CGRect(origin: .zero, size: display.frame.size),
                    items: session.document.items
                )

                if session.liveTextMode, let image = session.liveTextSourceImage() {
                    LiveTextView(image: image, session: session)
                        .frame(width: display.frame.width, height: display.frame.height)

                    LiveTextControlPill()
                        .environment(session)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                if let pending = session.pendingTextEdit, !session.liveTextMode {
                    TextEntryField(origin: pending.origin, colour: session.colour) { text in
                        session.commitPendingText(text)
                    }
                }
            }
            .frame(width: display.frame.width, height: display.frame.height)
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
    }

    // Tracks whether the drag currently in progress already started an
    // annotation, since (unlike the overlay) there's no separate selection
    // phase to distinguish a fresh drag from a continuing one.
    @State private var isDragging = false

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    beginDrawing(at: value.startLocation)
                }
                updateDrawing(to: value.location)
            }
            .onEnded { value in
                endDrawing(at: value.location)
                isDragging = false
            }
    }

    private func beginDrawing(at point: CGPoint) {
        guard !session.liveTextMode, let tool = session.currentTool, tool != .text, tool != .callout else { return }
        session.startAnnotation(AnnotationStroke.begin(kind: tool, colour: session.colour, at: point))
    }

    private func updateDrawing(to point: CGPoint) {
        guard !session.liveTextMode, let tool = session.currentTool, tool != .text, tool != .callout else { return }
        session.updateLastAnnotation { annotation in
            AnnotationStroke.update(&annotation, to: point)
        }
    }

    private func endDrawing(at point: CGPoint) {
        guard !session.liveTextMode, let tool = session.currentTool else { return }
        switch tool {
        case .text:
            session.pendingTextEdit = PendingTextEdit(origin: point)
        case .callout:
            session.addCallout(at: point)
        default:
            session.finalizeFilteredPatch()
        }
    }
}
