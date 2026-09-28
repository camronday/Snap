import SwiftUI

/// The small control shown beside a dragged selection in `.gifRegion` mode,
/// in place of the full annotation toolbar: just Record and Cancel.
struct GIFRegionControl: View {
    @Environment(OverlaySession.self) private var session

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                Button("Cancel") {
                    session.finish(.cancel)
                }
                .buttonStyle(.glass)
                .help("Cancel (Esc)")

                Button("Record") {
                    session.finish(.startRecording)
                }
                .buttonStyle(.glassProminent)
                .help("Record (Return)")
            }
            .padding(8)
        }
    }
}
