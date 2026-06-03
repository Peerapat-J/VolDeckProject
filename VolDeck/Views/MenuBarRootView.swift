import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var outputHelper: OutputHelperController
    @Environment(\.openSettings) private var openSettings
    @State private var outputOptions = [AudioOutputDeviceOption]()

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
        .onAppear(perform: refreshOutputOptions)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("VolDeck")
                    .font(.headline)
                Text("Helper \(outputHelper.state.rawValue)")
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

            Picker(
                "Output",
                selection: Binding(
                    get: { preferences.selectedOutputDeviceID },
                    set: { newValue in
                        let didChange = preferences.selectedOutputDeviceID != newValue
                        preferences.selectOutputDevice(id: newValue, from: outputOptions)
                        if didChange, outputHelper.canStop {
                            outputHelper.restart(outputDeviceUID: preferences.selectedOutputDeviceID)
                        }
                    }
                )
            ) {
                ForEach(outputOptions, id: \.self) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .disabled(outputOptions.count <= 1)
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

    private func refreshOutputOptions() {
        outputOptions = AudioOutputDeviceCatalog.availableOutputDevices()
        preferences.refreshSelectedOutputName(from: outputOptions)
    }
}

#Preview {
    MenuBarRootView(preferences: AppPreferences(), outputHelper: OutputHelperController())
}
