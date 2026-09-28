import SwiftUI

/// Shown when Screen Recording access hasn't been granted yet, on launch or
/// when a capture is attempted.
struct PermissionOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var granted = ScreenCapturePermission.isGranted

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Snap needs Screen Recording access")
                .font(.headline)

            Text("macOS requires permission before Snap can capture your screen. Grant access below, then reopen Snap if it doesn't take effect immediately.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if granted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Open System Settings") {
                    ScreenCapturePermission.openSystemSettings()
                }
                Button("Grant Access") {
                    ScreenCapturePermission.request()
                    granted = ScreenCapturePermission.isGranted
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 380)
    }
}
