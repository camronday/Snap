import SwiftUI

/// The clipboard editor window's content: the canvas scaled to fit, with the
/// same `ToolbarView` as the overlay pinned below it.
struct EditorRootView: View {
    let session: OverlaySession
    let fitScale: CGFloat

    private var display: FrozenDisplay? { session.activeFrozenDisplay }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                if let display {
                    EditorCanvasView()
                        .scaleEffect(fitScale, anchor: .topLeading)
                        .frame(width: display.frame.width * fitScale, height: display.frame.height * fitScale)
                        .padding(24)
                }
            }
            ToolbarView()
                .padding(.vertical, 12)
        }
        .environment(session)
        .background(.regularMaterial)
    }
}
