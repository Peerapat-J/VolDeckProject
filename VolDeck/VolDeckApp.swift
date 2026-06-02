import SwiftUI

@main
struct VolDeckApp: App {
    @StateObject private var preferences = AppPreferences()

    var body: some Scene {
        MenuBarExtra("VolDeck", systemImage: "slider.horizontal.3") {
            MenuBarRootView(preferences: preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences)
        }
    }
}
