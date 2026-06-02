import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }

            diagnosticsTab
                .tabItem {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
        }
        .frame(width: 540, height: 430)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { preferences.launchAtLoginEnabled },
                        set: { preferences.setLaunchAtLoginEnabled($0) }
                    )
                )

                LabeledContent("Login item status", value: preferences.launchAtLoginStatus)

                LabeledContent("Driver status", value: "Not installed")
                LabeledContent("Helper status", value: "Not running")
            } header: {
                Text("Startup")
            } footer: {
                Text("The M1 app shell does not activate any audio driver or helper process.")
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            Section {
                Label("No microphone permission for the core mixer", systemImage: "mic.slash")
                Label("No virtual input device in the core path", systemImage: "speaker.badge.exclamationmark")
                Label("No analytics or telemetry by default", systemImage: "network.slash")
                Label("No audio samples are written to logs", systemImage: "waveform.badge.magnifyingglass")
            } header: {
                Text("Core rules")
            }

            Section {
                Text("VolDeck should avoid APIs and device shapes that trigger mic or system-audio recording indicators. If a future feature needs capture permission, it must be optional and documented separately.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Indicator policy")
            }
        }
        .formStyle(.grouped)
    }

    private var diagnosticsTab: some View {
        Form {
            Section {
                Toggle("Enable local diagnostics", isOn: $preferences.localDiagnosticsEnabled)

                Text("Diagnostics are local-only in this shell. They must never record audio samples, audio content, or telemetry.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Local diagnostics")
            }

            Section {
                LabeledContent("Audio backend", value: "Not connected")
                LabeledContent("Selected output", value: preferences.selectedOutputName)
                LabeledContent("Privacy gate", value: "No permissions requested")
            } header: {
                Text("M1 placeholder state")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView(preferences: AppPreferences())
}
