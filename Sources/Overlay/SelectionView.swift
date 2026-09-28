import AppKit
import SwiftUI

/// The root view for one display's overlay panel: the frozen image,
/// dimming outside the selection, the drag-to-select/move/resize/draw
/// interaction, and (on the active display) the toolbar.
struct SelectionView: View {
    @Environment(OverlaySession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let displayID: CGDirectDisplayID

    @State private var dragPhase: DragPhase = .none
    /// Fixed anchor point for a selection currently being drawn, since the
    /// selection rect itself is re-standardized (its origin moves) as the
    /// drag grows up or left.
    @State private var creationAnchor: CGPoint = .zero
    @State private var hoveredWindow: PickableWindow?
    /// The dimming scrim fades in on first appearance rather than snapping.
    @State private var dimOpacity: CGFloat = 0
    /// Measured size of whichever floating control (toolbar/GIF/Live Text
    /// pill) is currently shown, so the clamp in `toolbarPosition` tracks its
    /// real width instead of a guessed constant.
    @State private var controlsSize = CGSize(width: 330, height: 56)

    private var display: FrozenDisplay? {
        session.frozenDisplays.first { $0.displayID == displayID }
    }

    private var isActive: Bool { session.activeDisplayID == displayID }

    var body: some View {
        // Controls sit outside the gestured canvas so the zero-distance drag
        // gesture can never swallow button clicks or text field focus.
        ZStack(alignment: .topLeading) {
            canvasLayer
            controlsLayer
        }
    }

    private var canvasLayer: some View {
        ZStack(alignment: .topLeading) {
            if let display {
                AnnotationCanvas(
                    base: display.image,
                    scale: display.scale,
                    crop: CGRect(origin: .zero, size: display.frame.size),
                    items: isActive ? session.document.items : [],
                    override: session.override(on: displayID)
                )

                Canvas { context, size in
                    var mask = Path(CGRect(origin: .zero, size: size))
                    if isActive, let selection = session.selection {
                        mask.addRect(selection)
                    }
                    context.fill(mask, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                }
                .frame(width: display.frame.width, height: display.frame.height)
                .opacity(dimOpacity)
                .allowsHitTesting(false)
                .onAppear {
                    if reduceMotion {
                        dimOpacity = 1
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) { dimOpacity = 1 }
                    }
                }
            }

            if isActive, let selection = session.selection {
                Rectangle()
                    .stroke(.white, lineWidth: 1)
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .allowsHitTesting(false)

                ForEach(SelectionHandle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .position(handle.position(in: selection))
                }

                sizeLabel(for: selection, display: display)
            }

            if session.windowPickMode {
                windowPickOverlay
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onContinuousHover { phase in
            guard session.windowPickMode else { return }
            switch phase {
            case .active(let location):
                hoveredWindow = WindowPicker.hitTest(location, in: session.pickableWindows, displayID: displayID)
            case .ended:
                hoveredWindow = nil
            }
        }
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder
    private var controlsLayer: some View {
        Group {
            if isActive, let selection = session.selection {
                if session.liveTextMode, let image = session.liveTextSourceImage() {
                    LiveTextView(image: image, session: session)
                        .frame(width: selection.width, height: selection.height)
                        .position(x: selection.midX, y: selection.midY)

                    LiveTextControlPill()
                        .environment(session)
                        .measuringControlsSize($controlsSize)
                        .position(toolbarPosition(for: selection, in: display?.frame.size ?? .zero))
                        .glassControlTransition()
                } else if session.purpose == .annotate {
                    ToolbarView()
                        .environment(session)
                        .measuringControlsSize($controlsSize)
                        .position(toolbarPosition(for: selection, in: display?.frame.size ?? .zero))
                        .glassControlTransition()
                } else if session.purpose == .gifRegion {
                    GIFRegionControl()
                        .environment(session)
                        .measuringControlsSize($controlsSize)
                        .position(toolbarPosition(for: selection, in: display?.frame.size ?? .zero))
                        .glassControlTransition()
                }

                if let pending = session.pendingTextEdit {
                    TextEntryField(origin: pending.origin, colour: session.colour) { text in
                        session.commitPendingText(text)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: controlsKind)
    }

    /// Which floating control is currently shown, so its appear/disappear
    /// (and the toolbar-to-pill swap) can be driven by one `.animation`.
    private enum ControlsKind: Equatable { case none, liveText, toolbar, gif }

    private var controlsKind: ControlsKind {
        guard isActive, session.selection != nil else { return .none }
        if session.liveTextMode { return .liveText }
        if session.purpose == .annotate { return .toolbar }
        if session.purpose == .gifRegion { return .gif }
        return .none
    }

    @ViewBuilder
    private var windowPickOverlay: some View {
        if let hoveredWindow {
            let local = WindowPicker.localFrame(for: hoveredWindow.globalFrame, displayBounds: CGDisplayBounds(displayID))
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 3))
                .frame(width: local.width, height: local.height)
                .position(x: local.midX, y: local.midY)
                .allowsHitTesting(false)
        }

        Text("Click a window. Space for region.")
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(in: .capsule)
            .position(x: (display?.frame.width ?? 0) / 2, y: 30)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sizeLabel(for selection: CGRect, display: FrozenDisplay?) -> some View {
        let scale = display?.scale ?? 1
        let pixelWidth = Int((selection.width * scale).rounded())
        let pixelHeight = Int((selection.height * scale).rounded())
        Text("\(pixelWidth) \u{00D7} \(pixelHeight)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(in: .capsule)
            .position(x: selection.minX + 40, y: max(selection.minY - 14, 10))
    }

    private func toolbarPosition(for selection: CGRect, in displaySize: CGSize) -> CGPoint {
        // Keep the whole bar on screen when the selection hugs a side edge;
        // `controlsSize` tracks the real, currently-shown control's measured
        // size (toolbar/GIF/Live Text pill each differ, and the toolbar's
        // own width shifts as its selected-tool glass morphs).
        let halfWidth = controlsSize.width / 2
        let height = controlsSize.height
        let midX = min(max(selection.midX, halfWidth + 8), max(displaySize.width - halfWidth - 8, halfWidth + 8))
        if selection.maxY + height + 12 <= displaySize.height {
            return CGPoint(x: midX, y: selection.maxY + height / 2 + 8)
        } else if selection.minY - height - 12 >= 0 {
            return CGPoint(x: midX, y: selection.minY - height / 2 - 8)
        } else {
            return CGPoint(x: midX, y: selection.maxY - height / 2 - 8)
        }
    }

    // MARK: - Gesture

    private enum DragPhase {
        case none
        case creatingSelection
        case movingSelection(offset: CGSize)
        case resizing(handle: SelectionHandle, original: CGRect)
        case drawing
        case tap(AnnotationKind)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch dragPhase {
                case .none:
                    dragPhase = beginDrag(at: value.startLocation)
                default:
                    break
                }
                updateDrag(to: value.location)
            }
            .onEnded { value in
                endDrag(at: value.location)
                dragPhase = .none
            }
    }

    private func beginDrag(at point: CGPoint) -> DragPhase {
        // Live Text owns the selection interior while it's active; the
        // `LiveTextView` sits above this gestured layer and handles its own
        // clicks, so there's nothing for the drag gesture to do here.
        if session.liveTextMode {
            return .none
        }

        if session.windowPickMode {
            if let window = WindowPicker.hitTest(point, in: session.pickableWindows, displayID: displayID) {
                let local = WindowPicker.localFrame(for: window.globalFrame, displayBounds: CGDisplayBounds(displayID))
                session.selectWindow(window, on: displayID, at: local)
            }
            return .none
        }

        if !isActive {
            session.beginSelection(on: displayID, at: point)
            creationAnchor = point
            return .creatingSelection
        }

        if let selection = session.selection, let handle = SelectionHandle.hitTest(point, in: selection) {
            return .resizing(handle: handle, original: selection)
        }

        if let selection = session.selection, selection.contains(point) {
            guard let tool = session.currentTool else {
                return .movingSelection(offset: CGSize(width: point.x - selection.minX, height: point.y - selection.minY))
            }
            if tool == .text || tool == .callout {
                return .tap(tool)
            }
            session.startAnnotation(AnnotationStroke.begin(kind: tool, colour: session.colour, at: point))
            return .drawing
        }

        session.beginSelection(on: displayID, at: point)
        creationAnchor = point
        return .creatingSelection
    }

    private func updateDrag(to point: CGPoint) {
        switch dragPhase {
        case .none, .tap:
            break

        case .creatingSelection:
            session.updateSelection(to: CGRect(origin: creationAnchor, size: .zero).union(CGRect(origin: point, size: .zero)))

        case .movingSelection(let offset):
            guard let size = session.selection?.size else { break }
            session.updateSelection(to: CGRect(x: point.x - offset.width, y: point.y - offset.height, width: size.width, height: size.height))

        case .resizing(let handle, let original):
            session.updateSelection(to: handle.resize(original, to: point))

        case .drawing:
            session.updateLastAnnotation { annotation in
                AnnotationStroke.update(&annotation, to: point)
            }
        }
    }

    private func endDrag(at point: CGPoint) {
        switch dragPhase {
        case .drawing:
            session.finalizeFilteredPatch()
        case .tap(.text):
            session.pendingTextEdit = PendingTextEdit(origin: point)
        case .tap(.callout):
            session.addCallout(at: point)
        case .creatingSelection, .resizing, .movingSelection:
            if session.purpose == .ocr, let selection = session.selection, selection.width > 4, selection.height > 4 {
                session.captureText()
            }
        default:
            break
        }
    }
}
