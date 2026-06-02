import SwiftUI

@main
struct VolDeckApp: App {
    @StateObject private var preferences = AppPreferences()
    @StateObject private var outputHelper = OutputHelperController()

    var body: some Scene {
        MenuBarExtra("VolDeck", systemImage: "slider.horizontal.3") {
            MenuBarRootView(preferences: preferences, outputHelper: outputHelper)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, outputHelper: outputHelper)
        }
    }
}
