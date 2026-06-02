import SwiftUI

struct AppVolumeRow: View {
    let app: PlaceholderAudioApp

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: app.systemImage)
                    .foregroundStyle(app.isMuted ? .secondary : .primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(app.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                    } label: {
                        Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(app.isMuted ? .red : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .help(app.isMuted ? "Muted preview" : "Mute preview")
                }

                HStack(spacing: 10) {
                    Slider(value: .constant(app.volume), in: 0...1)
                        .disabled(true)

                    Text("\(Int(app.volume * 100))%")
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
        AppVolumeRow(app: PlaceholderAudioApp.samples[0])
        AppVolumeRow(app: PlaceholderAudioApp.samples[1])
    }
    .frame(width: 380)
}
