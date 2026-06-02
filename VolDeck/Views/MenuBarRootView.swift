import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings

    private let outputOptions = [
        "System Default",
        "Built-in Speakers",
        "Headphones",
        "External Display",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            outputPicker
            Divider()
            appList
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("VolDeck")
                    .font(.headline)
                Text("Preview mixer shell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(14)
    }

    private var outputPicker: some View {
        HStack(spacing: 12) {
            Label("Output", systemImage: "speaker.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Output", selection: $preferences.selectedOutputName) {
                ForEach(outputOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .disabled(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(PlaceholderAudioApp.samples.indices, id: \.self) { index in
                    let app = PlaceholderAudioApp.samples[index]
                    AppVolumeRow(app: app)
                    if index < PlaceholderAudioApp.samples.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
        .frame(height: 356)
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
    }
}

#Preview {
    MenuBarRootView(preferences: AppPreferences())
}
