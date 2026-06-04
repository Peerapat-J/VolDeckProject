import Foundation

@main
struct SessionIdentityBehaviorTests {
    static func main() {
        assertEqual(
            AudioSessionIdentityResolver.stableIdentityKey(
                bundleIdentifier: "com.example.Player",
                executablePath: "/Applications/Player.app/Contents/MacOS/Player",
                processID: 101,
                clientID: 1
            ),
            "bundle:com.example.Player",
            "bundle id should be the durable identity key"
        )

        let firstPathKey = AudioSessionIdentityResolver.stableIdentityKey(
            bundleIdentifier: nil,
            executablePath: "/Applications/StandaloneTool",
            processID: 101,
            clientID: 1
        )
        let relaunchedPathKey = AudioSessionIdentityResolver.stableIdentityKey(
            bundleIdentifier: nil,
            executablePath: "/Applications/StandaloneTool",
            processID: 202,
            clientID: 2
        )
        assertEqual(firstPathKey, relaunchedPathKey, "path fallback should survive relaunch")
        assertTrue(!firstPathKey.contains("/Applications/StandaloneTool"), "path fallback should not persist the raw executable path")

        assertEqual(
            AudioSessionIdentityResolver.stableIdentityKey(
                bundleIdentifier: nil,
                executablePath: nil,
                processID: 303,
                clientID: 42
            ),
            "client:42",
            "unknown fallback should not persist pid"
        )

        let session = HALAudioClientSession(
            clientID: 7,
            processID: 987_654,
            bundleIdentifier: "com.example.HelperOwner",
            active: true,
            lastChangedHostTime: 10
        )
        let resolved = AudioSessionIdentityResolver().resolve(session: session)
        assertEqual(resolved.id, "bundle:com.example.HelperOwner", "CoreAudio bundle id should be used when NSRunningApplication is unavailable")
        assertEqual(resolved.bundleIdentifier, "com.example.HelperOwner", "resolved session should retain bundle id")

        print("VolDeck session identity behavior tests passed")
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ scenario: String) {
        guard actual == expected else {
            fputs("error: \(scenario): expected \(expected), got \(actual)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func assertTrue(_ condition: Bool, _ scenario: String) {
        guard condition else {
            fputs("error: \(scenario)\n", stderr)
            Foundation.exit(1)
        }
    }
}
