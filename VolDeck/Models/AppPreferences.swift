import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginStatus: String
    @Published var localDiagnosticsEnabled: Bool {
        didSet {
            defaults.set(localDiagnosticsEnabled, forKey: Keys.localDiagnosticsEnabled)
        }
    }
    @Published var selectedOutputName: String {
        didSet {
            defaults.set(selectedOutputName, forKey: Keys.selectedOutputName)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLoginEnabled)
        self.localDiagnosticsEnabled = defaults.bool(forKey: Keys.localDiagnosticsEnabled)
        self.selectedOutputName = defaults.string(forKey: Keys.selectedOutputName) ?? "System Default"
        self.launchAtLoginStatus = "Not registered"
        refreshLaunchAtLoginStatus()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            defaults.set(isEnabled, forKey: Keys.launchAtLoginEnabled)
            launchAtLoginEnabled = isEnabled
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginStatus = "Could not update login item: \(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginStatus = "Enabled"
            launchAtLoginEnabled = true
        case .notRegistered:
            launchAtLoginStatus = "Off"
            launchAtLoginEnabled = false
        case .requiresApproval:
            launchAtLoginStatus = "Requires approval in System Settings"
            launchAtLoginEnabled = true
        case .notFound:
            launchAtLoginStatus = "Unavailable for this build"
        @unknown default:
            launchAtLoginStatus = "Unknown"
        }
    }
}

private enum Keys {
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
    static let localDiagnosticsEnabled = "localDiagnosticsEnabled"
    static let selectedOutputName = "selectedOutputName"
}
