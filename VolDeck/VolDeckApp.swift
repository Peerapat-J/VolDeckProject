import SwiftUI

@main
struct VolDeckApp: App {
    @StateObject private var preferences = AppPreferences()
    @StateObject private var outputHelper = OutputHelperController()
    @StateObject private var audioSessions = AudioSessionController()

    var body: some Scene {
        MenuBarExtra("VolDeck", systemImage: "slider.horizontal.3") {
            MenuBarRootView(
                preferences: preferences,
                outputHelper: outputHelper,
                audioSessions: audioSessions
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                preferences: preferences,
                outputHelper: outputHelper,
                audioSessions: audioSessions
            )
        }
    }
}
