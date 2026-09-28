import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 420)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(PreferencesKey.retinaClipboard) private var retinaClipboard = PreferencesDefault.retinaClipboard
    @AppStorage(PreferencesKey.gifMaxDuration) private var gifMaxDuration = PreferencesDefault.gifMaxDuration

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }

                if needsApproval {
                    HStack {
                        Text("Approval needed in Login Items settings.")
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            LoginItem.openSystemSettings()
                        }
                    }
                }
            }

            Section {
                Toggle("Copy at full Retina resolution", isOn: $retinaClipboard)
            }

            Section {
                Stepper(value: $gifMaxDuration, in: PreferencesRange.gifMaxDuration) {
                    Text("GIF max duration: \(gifMaxDuration) s")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            needsApproval = LoginItem.needsApproval
        }
    }
}

private struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture Region:", name: .captureRegion)
                KeyboardShortcuts.Recorder("Record GIF:", name: .recordGIF)
            }
        }
        .formStyle(.grouped)
    }
}
