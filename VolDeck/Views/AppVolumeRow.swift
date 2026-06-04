import SwiftUI

struct AppVolumeRow: View {
    let session: AppAudioSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                if let icon = session.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: "app.fill")
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(session.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .help("Mute")
                }

                HStack(spacing: 10) {
                    Slider(value: .constant(1.0), in: 0...1)
                        .disabled(true)

                    Text("100%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(0.92)
    }
}

#Preview {
    VStack {
        AppVolumeRow(session: AppAudioSession(
            id: "bundle:com.apple.Music",
            clientID: 1,
            processID: 100,
            displayName: "Music",
            detail: "Active audio - com.apple.Music",
            bundleIdentifier: "com.apple.Music",
            icon: nil,
            isActive: true,
            lastChangedHostTime: 0
        ))
    }
    .frame(width: 380)
}
