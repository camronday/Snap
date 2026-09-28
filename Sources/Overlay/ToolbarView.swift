import SwiftUI

/// Shown once per app run, the first time any toolbar appears, to point out
/// that Return (or Cmd/Ctrl+C) copies without needing a dedicated button.
@MainActor
private enum ReturnHintState {
    static var hasShown = false
}

/// The floating tool palette beside the selection. Liquid Glass throughout;
/// never placed on top of the screenshot itself (only beside it). Tools,
/// colour, history and actions are separate glass capsules sharing one
/// `GlassEffectContainer`, so the selected tool's highlight can morph
/// between them.
struct ToolbarView: View {
    @Environment(OverlaySession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var showingColourPopover = false
    @State private var showReturnHint = !ReturnHintState.hasShown

    var body: some View {
        ZStack(alignment: .top) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    toolsGroup
                    colourGroup
                    historyGroup
                    actionsGroup
                }
            }

            if showReturnHint {
                Text("Return to copy")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(in: .capsule)
                    .offset(y: -34)
                    .transition(.opacity)
            }
        }
        .task {
            guard showReturnHint else { return }
            ReturnHintState.hasShown = true
            try? await Task.sleep(for: .seconds(2.5))
            dismissReturnHint()
        }
    }

    private func dismissReturnHint() {
        guard showReturnHint else { return }
        if reduceMotion {
            showReturnHint = false
        } else {
            withAnimation(.easeOut(duration: 0.2)) { showReturnHint = false }
        }
    }

    private var toolsGroup: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationKind.allCases, id: \.self) { kind in
                toolButton(kind)
            }
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(session.liveTextMode)
    }

    private var colourGroup: some View {
        colourButton
            .padding(6)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var historyGroup: some View {
        HStack(spacing: 2) {
            iconButton("arrow.uturn.backward", help: "Undo (\u{2318}Z)") { session.undo() }
                .disabled(!session.document.canUndo)
            iconButton("arrow.uturn.forward", help: "Redo (\u{2318}\u{21E7}Z)") { session.redo() }
                .disabled(!session.document.canRedo)
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var actionsGroup: some View {
        HStack(spacing: 2) {
            liveTextButton
            iconButton("square.and.arrow.down", help: "Save (\u{2318}S)") { session.finish(.save) }
            iconButton("xmark", help: "Close (Esc)") { session.finish(.cancel) }
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            dismissReturnHint()
            action()
        } label: {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var liveTextButton: some View {
        Button {
            dismissReturnHint()
            session.toggleLiveTextMode()
        } label: {
            Image(systemName: session.liveTextMode ? "checkmark.circle.fill" : "text.viewfinder")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("Live Text")
    }

    private func toolButton(_ kind: AnnotationKind) -> some View {
        let isActive = session.currentTool == kind
        return Button {
            dismissReturnHint()
            if reduceMotion {
                session.currentTool = isActive ? nil : kind
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    session.currentTool = isActive ? nil : kind
                }
            }
        } label: {
            Image(systemName: kind.symbolName)
                .symbolEffect(.bounce, value: reduceMotion ? false : isActive)
                .frame(width: 30, height: 30)
                .background {
                    // The active tool's own glass lozenge: tagging it with a
                    // shared id in the container's namespace lets Liquid
                    // Glass morph it smoothly to whichever tool is next
                    // selected, rather than crossfading.
                    if isActive {
                        Circle()
                            .glassEffect(.regular.tint(session.colour.color).interactive(), in: .circle)
                            .glassEffectID("selectedTool", in: glassNamespace)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(kind.label)
    }

    private var colourButton: some View {
        Button {
            dismissReturnHint()
            showingColourPopover = true
        } label: {
            Circle()
                .fill(session.colour.color)
                .overlay(Circle().stroke(.primary.opacity(0.3), lineWidth: 1))
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("Colour")
        .popover(isPresented: $showingColourPopover) {
            ColourPopover(session: session)
        }
    }
}

private struct ColourPopover: View {
    let session: OverlaySession

    private static let swatches: [RGBAColour] = [
        RGBAColour(red: 1, green: 0, blue: 0, alpha: 1),
        RGBAColour(red: 1, green: 0.58, blue: 0, alpha: 1),
        RGBAColour(red: 1, green: 0.85, blue: 0, alpha: 1),
        RGBAColour(red: 0.2, green: 0.78, blue: 0.35, alpha: 1),
        RGBAColour(red: 0.2, green: 0.48, blue: 1, alpha: 1),
        RGBAColour(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if swatch == session.colour {
                                Circle().stroke(.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture {
                            session.setColour(swatch)
                        }
                }
            }

            ColorPicker("Custom", selection: Binding(
                get: { session.colour.color },
                set: { session.setColour(RGBAColour(color: $0)) }
            ))
            .labelsHidden()
        }
        .padding(12)
    }
}
