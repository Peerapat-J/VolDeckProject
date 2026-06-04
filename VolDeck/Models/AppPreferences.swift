import Foundation
import CoreAudio
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
    @Published var selectedOutputDeviceID: String {
        didSet {
            defaults.set(selectedOutputDeviceID, forKey: Keys.selectedOutputDeviceID)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLoginEnabled)
        self.localDiagnosticsEnabled = defaults.bool(forKey: Keys.localDiagnosticsEnabled)
        self.selectedOutputName = defaults.string(forKey: Keys.selectedOutputName) ?? "System Default"
        self.selectedOutputDeviceID = defaults.string(forKey: Keys.selectedOutputDeviceID) ?? AudioOutputDeviceCatalog.systemDefaultOutputDeviceID
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

    func selectOutputDevice(id: String, from devices: [AudioOutputDeviceOption]) {
        selectedOutputDeviceID = id
        selectedOutputName = devices.first(where: { $0.id == id })?.displayName ?? "System Default"
    }

    func refreshSelectedOutputName(from devices: [AudioOutputDeviceOption]) {
        guard let selectedDevice = devices.first(where: { $0.id == selectedOutputDeviceID }) else {
            selectedOutputDeviceID = AudioOutputDeviceCatalog.systemDefaultOutputDeviceID
            selectedOutputName = "System Default"
            return
        }

        selectedOutputName = selectedDevice.displayName
    }
}

private enum Keys {
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
    static let localDiagnosticsEnabled = "localDiagnosticsEnabled"
    static let selectedOutputName = "selectedOutputName"
    static let selectedOutputDeviceID = "selectedOutputDeviceID"
}

struct AudioOutputDeviceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let isDefault: Bool
}

enum AudioOutputDeviceRestoreError: Error, LocalizedError {
    case systemDefaultPlaceholder
    case notFound(String)
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemDefaultPlaceholder:
            "System Default is a placeholder and cannot be restored directly"
        case .notFound(let id):
            "No output device matches UID \(id)"
        case .coreAudio(let status):
            "CoreAudio rejected the restore with OSStatus \(status)"
        }
    }
}

enum AudioOutputDeviceCatalog {
    static let systemDefaultOutputDeviceID = "__system_default__"
    private static let volDeckOutputDeviceUID = "com.peerapatj.voldeck.output"

    @MainActor
    static func availableOutputDevices() -> [AudioOutputDeviceOption] {
        var options = [
            AudioOutputDeviceOption(id: systemDefaultOutputDeviceID, displayName: "System Default", isDefault: true)
        ]

        guard let devices = try? realOutputDevices() else {
            return options
        }

        options.append(contentsOf: devices.map(\.option))
        return options
    }

    static func currentDefaultRealOutputDevice() -> AudioOutputDeviceOption? {
        let defaultID = defaultOutputDeviceID()
        guard defaultID != AudioDeviceID(kAudioObjectUnknown),
              let device = try? realOutputDevices().first(where: { $0.deviceID == defaultID }) else {
            return nil
        }

        return device.option
    }

    static func realOutputDevice(id: String?) -> AudioOutputDeviceOption? {
        guard let id, !id.isEmpty, id != systemDefaultOutputDeviceID,
              let device = try? realOutputDevices().first(where: { $0.option.id == id }) else {
            return nil
        }

        return device.option
    }

    @discardableResult
    static func setDefaultOutputDevice(id: String) throws -> AudioOutputDeviceOption {
        guard id != systemDefaultOutputDeviceID else {
            throw AudioOutputDeviceRestoreError.systemDefaultPlaceholder
        }

        guard let device = try realOutputDevices().first(where: { $0.option.id == id }) else {
            throw AudioOutputDeviceRestoreError.notFound(id)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = device.deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.stride),
            &deviceID
        )
        guard status == noErr else {
            throw AudioOutputDeviceRestoreError.coreAudio(status)
        }

        return device.option
    }

    private struct AudioOutputDeviceCandidate {
        let deviceID: AudioDeviceID
        let option: AudioOutputDeviceOption
    }

    private static func realOutputDevices() throws -> [AudioOutputDeviceCandidate] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize)
        guard status == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        guard deviceCount > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: deviceCount)
        status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            return []
        }

        let defaultID = defaultOutputDeviceID()
        return deviceIDs.compactMap { deviceID in
            guard outputChannelCount(for: deviceID) > 0,
                  let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
                  uid != volDeckOutputDeviceUID,
                  let name = stringProperty(deviceID, kAudioObjectPropertyName) else {
                return nil
            }

            return AudioOutputDeviceCandidate(
                deviceID: deviceID,
                option: AudioOutputDeviceOption(
                    id: uid,
                    displayName: defaultID == deviceID ? "\(name) (Default)" : name,
                    isDefault: defaultID == deviceID
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.option.isDefault != rhs.option.isDefault {
                return lhs.option.isDefault
            }
            return lhs.option.displayName.localizedStandardCompare(rhs.option.displayName) == .orderedAscending
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.stride)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : AudioDeviceID(kAudioObjectUnknown)
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize >= UInt32(MemoryLayout<AudioBufferList>.stride) else {
            return 0
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            buffer.deallocate()
        }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer)
        guard status == noErr else {
            return 0
        }

        let audioBufferList = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(UInt32(0)) { partial, audioBuffer in
            partial + audioBuffer.mNumberChannels
        }
    }
}
