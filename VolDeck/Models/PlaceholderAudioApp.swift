import Foundation

struct PlaceholderAudioApp: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let systemImage: String
    let volume: Double
    let isMuted: Bool

    static let samples: [PlaceholderAudioApp] = [
        .init(name: "Wuthering Waves", detail: "Game audio", systemImage: "gamecontroller.fill", volume: 0.35, isMuted: true),
        .init(name: "YouTube", detail: "Browser video", systemImage: "play.rectangle.fill", volume: 0.82, isMuted: false),
        .init(name: "Music", detail: "Music player", systemImage: "music.note", volume: 0.62, isMuted: false),
        .init(name: "Discord", detail: "Voice/chat", systemImage: "person.2.fill", volume: 0.74, isMuted: false),
        .init(name: "LINE", detail: "Messages", systemImage: "message.fill", volume: 0.48, isMuted: false),
        .init(name: "Safari", detail: "Web audio", systemImage: "safari.fill", volume: 0.70, isMuted: false),
        .init(name: "QuickTime Player", detail: "Local media", systemImage: "film.fill", volume: 0.55, isMuted: false),
        .init(name: "System Alerts", detail: "Notification sounds", systemImage: "bell.fill", volume: 0.25, isMuted: false),
    ]
}
