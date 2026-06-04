import Combine
import CoreAudio
import Darwin
import Foundation

@MainActor
final class AudioSessionController: ObservableObject {
    @Published private(set) var sessions = [AppAudioSession]()
    @Published private(set) var statusMessage = "No active VolDeck audio apps"
    @Published private(set) var isRefreshing = false

    private let catalog: AudioProcessSessionCatalog
    private let identityResolver: AudioSessionIdentityResolver

    init(
        catalog: AudioProcessSessionCatalog = AudioProcessSessionCatalog(),
        identityResolver: AudioSessionIdentityResolver = AudioSessionIdentityResolver()
    ) {
        self.catalog = catalog
        self.identityResolver = identityResolver
    }

    func refresh() {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            let activeSessions = try catalog.activeOutputSessions()
            sessions = identityResolver.resolve(sessions: activeSessions)
            statusMessage = sessions.isEmpty ? "No active VolDeck audio apps" : "\(sessions.count) active audio app(s)"
        } catch {
            statusMessage = "Session scan unavailable: \(error.localizedDescription)"
        }
    }
}

struct AudioProcessSessionCatalog {
    private let volDeckOutputDeviceUID = "com.peerapatj.voldeck.output"

    func activeOutputSessions() throws -> [HALAudioClientSession] {
        let processObjects = try audioObjectIDList(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        )

        return processObjects.compactMap { processObject in
            guard let processID = try? pidProperty(processObject),
                  processID > 0,
                  (try? uint32Property(processObject, kAudioProcessPropertyIsRunningOutput, scope: kAudioObjectPropertyScopeGlobal)) == 1,
                  (try? outputDeviceUIDs(for: processObject).contains(volDeckOutputDeviceUID)) == true else {
                return nil
            }

            return HALAudioClientSession(
                clientID: UInt32(processObject),
                processID: processID,
                bundleIdentifier: try? stringProperty(processObject, kAudioProcessPropertyBundleID),
                active: true,
                lastChangedHostTime: mach_absolute_time()
            )
        }
    }

    private func outputDeviceUIDs(for processObjectID: AudioObjectID) throws -> [String] {
        try audioObjectIDList(
            objectID: processObjectID,
            selector: kAudioProcessPropertyDevices,
            scope: kAudioObjectPropertyScopeOutput
        )
        .compactMap { try? stringProperty($0, kAudioDevicePropertyDeviceUID) }
    }

    private func audioObjectIDList(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioSessionCatalogError.coreAudio(status, selector)
        }
        guard dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        var values = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &values)
        guard status == noErr else {
            throw AudioSessionCatalogError.coreAudio(status, selector)
        }

        return values.filter { $0 != AudioObjectID(kAudioObjectUnknown) }
    }

    private func pidProperty(_ objectID: AudioObjectID) throws -> Int32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid_t(0)
        var dataSize = UInt32(MemoryLayout<pid_t>.stride)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &pid)
        guard status == noErr else {
            throw AudioSessionCatalogError.coreAudio(status, kAudioProcessPropertyPID)
        }
        return Int32(pid)
    }

    private func uint32Property(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.stride)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            throw AudioSessionCatalogError.coreAudio(status, selector)
        }
        return value
    }

    private func stringProperty(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr, let value else {
            throw AudioSessionCatalogError.coreAudio(status, selector)
        }
        return value.takeRetainedValue() as String
    }
}

enum AudioSessionCatalogError: LocalizedError {
    case coreAudio(OSStatus, AudioObjectPropertySelector)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status, let selector):
            return "CoreAudio selector \(selector) failed with OSStatus \(status)"
        }
    }
}
