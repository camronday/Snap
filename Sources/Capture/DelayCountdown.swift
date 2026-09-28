import AppKit
import SwiftUI

/// A brief glass countdown shown before a delayed capture. Never activates
/// the app or takes key focus, so it doesn't interrupt whatever the user is
/// doing (e.g. a menu they've opened) while the countdown runs.
enum DelayCountdown {
    static func run(seconds: Int) async {
        guard seconds > 0 else { return }
        let screen = ScreenLocator.containingMouse()
        let panel = CountdownPanel(screen: screen, value: seconds)
        panel.orderFrontRegardless()

        for remaining in stride(from: seconds, through: 1, by: -1) {
            panel.update(remaining)
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
    }
}

/// Screen lookup shared by the countdown HUD and the toast.
enum ScreenLocator {
    static func containingMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class CountdownPanel: NSPanel {
    private let hostingView: NSHostingView<CountdownView>
    private static let size = CGSize(width: 96, height: 96)

    init(screen: NSScreen, value: Int) {
        hostingView = NSHostingView(rootView: CountdownView(value: value))
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = hostingView
        setFrameOrigin(CGPoint(x: screen.frame.midX - Self.size.width / 2, y: screen.frame.midY - Self.size.height / 2))
    }

    override var canBecomeKey: Bool { false }

    func update(_ value: Int) {
        hostingView.rootView = CountdownView(value: value)
    }
}

private struct CountdownView: View {
    let value: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(value)")
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : .default, value: value)
            .frame(width: 96, height: 96)
            .glassEffect(in: .circle)
    }
}
