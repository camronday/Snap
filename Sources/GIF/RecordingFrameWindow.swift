import AppKit
import SwiftUI

/// While a GIF recording is in progress: a click-through accent border just
/// outside the recorded region, plus a small glass pill (elapsed time, Stop)
/// next to it. Both are torn down the moment recording stops, so nothing
/// lingers (or ticks) at idle.
@MainActor
enum RecordingFrameWindow {
    private static var borderPanel: NSPanel?
    private static var pillPanel: NSPanel?

    private static let outset: CGFloat = 4
    private static let pillSize = CGSize(width: 148, height: 40)
    private static let pillGap: CGFloat = 8

    static func show(display: FrozenDisplay, selection: CGRect, onStop: @escaping () -> Void) {
        hide()

        let border = display.globalRect(forLocal: selection).insetBy(dx: -outset, dy: -outset)

        let borderPanel = BorderPanel(frame: border)
        borderPanel.orderFrontRegardless()
        Self.borderPanel = borderPanel

        let pillFrame = pillFrame(besideBorder: border)
        let pillPanel = PillPanel(frame: pillFrame, startDate: .now, onStop: onStop)
        pillPanel.orderFrontRegardless()
        Self.pillPanel = pillPanel
    }

    static func hide() {
        borderPanel?.orderOut(nil)
        borderPanel = nil
        pillPanel?.orderOut(nil)
        pillPanel = nil
    }

    /// Prefers just below the border, right-aligned to it; falls back above
    /// it if there's no room underneath.
    private static func pillFrame(besideBorder border: CGRect) -> CGRect {
        let x = border.maxX - pillSize.width
        let below = border.minY - pillGap - pillSize.height
        let y = below >= 0 ? below : border.maxY + pillGap
        return CGRect(origin: CGPoint(x: x, y: y), size: pillSize)
    }
}

/// Click-through outline. Never becomes key, never intercepts the mouse.
private final class BorderPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: RecordingBorderView())
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { false }
}

/// Accepts the Stop click, but `.nonactivatingPanel` means becoming key
/// never brings Snap to the front.
private final class PillPanel: NSPanel {
    init(frame: CGRect, startDate: Date, onStop: @escaping () -> Void) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        contentView = NSHostingView(rootView: RecordingPillView(startDate: startDate, onStop: onStop))
        setFrame(frame, display: true)
    }
}

private struct RecordingBorderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.accentColor, lineWidth: 4)
    }
}

private struct RecordingPillView: View {
    let startDate: Date
    let onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            GlassEffectContainer {
                HStack(spacing: 8) {
                    Text(elapsed(since: context.date))
                        .font(.caption.monospacedDigit())
                    Button("Stop", action: onStop)
                        .buttonStyle(.glassProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
            }
        }
    }

    private func elapsed(since now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
