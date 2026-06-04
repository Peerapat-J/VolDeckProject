import AppKit
import Foundation

struct HALAudioClientSession: Decodable, Identifiable, Equatable {
    let clientID: UInt32
    let processID: Int32
    let bundleIdentifier: String?
    let active: Bool
    let lastChangedHostTime: UInt64

    var id: String {
        "\(clientID)-\(processID)"
    }
}

struct AppAudioSession: Identifiable {
    let id: String
    let clientID: UInt32
    let processID: Int32
    let displayName: String
    let detail: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let isActive: Bool
    let lastChangedHostTime: UInt64
}

struct AudioSessionIdentityResolver {
    func resolve(sessions: [HALAudioClientSession]) -> [AppAudioSession] {
        sessions
            .map(resolve(session:))
            .sorted { lhs, rhs in
                let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.clientID < rhs.clientID
            }
    }

    func resolve(session: HALAudioClientSession) -> AppAudioSession {
        let runningApp = NSRunningApplication(processIdentifier: pid_t(session.processID))
        let bundleIdentifier = runningApp?.bundleIdentifier ?? session.bundleIdentifier
        let executablePath = runningApp?.executableURL?.path
        let displayName = Self.displayName(
            runningApp: runningApp,
            executablePath: executablePath,
            processID: session.processID,
            clientID: session.clientID
        )
        let identityKey = Self.stableIdentityKey(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            processID: session.processID,
            clientID: session.clientID
        )
        let detail = Self.detail(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            processID: session.processID,
            active: session.active
        )

        return AppAudioSession(
            id: identityKey,
            clientID: session.clientID,
            processID: session.processID,
            displayName: displayName,
            detail: detail,
            bundleIdentifier: bundleIdentifier,
            icon: runningApp?.icon,
            isActive: session.active,
            lastChangedHostTime: session.lastChangedHostTime
        )
    }

    static func stableIdentityKey(
        bundleIdentifier: String?,
        executablePath: String?,
        processID: Int32,
        clientID: UInt32
    ) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }

        if let executablePath, !executablePath.isEmpty {
            let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
            return "path:\(stablePathHash(executablePath)):\(executableName)"
        }

        return "client:\(clientID)"
    }

    private static func displayName(
        runningApp: NSRunningApplication?,
        executablePath: String?,
        processID: Int32,
        clientID: UInt32
    ) -> String {
        if let localizedName = runningApp?.localizedName, !localizedName.isEmpty {
            return localizedName
        }

        if let executablePath, !executablePath.isEmpty {
            let fileName = URL(fileURLWithPath: executablePath).deletingPathExtension().lastPathComponent
            if !fileName.isEmpty {
                return fileName
            }
        }

        if processID > 0 {
            return "Process \(processID)"
        }

        return "Audio Client \(clientID)"
    }

    private static func detail(
        bundleIdentifier: String?,
        executablePath: String?,
        processID: Int32,
        active: Bool
    ) -> String {
        let state = active ? "Active audio" : "Idle"

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "\(state) - \(bundleIdentifier)"
        }

        if let executablePath, !executablePath.isEmpty {
            return "\(state) - \(URL(fileURLWithPath: executablePath).lastPathComponent)"
        }

        if processID > 0 {
            return "\(state) - pid \(processID)"
        }

        return "\(state) - unknown process"
    }

    private static func stablePathHash(_ path: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
