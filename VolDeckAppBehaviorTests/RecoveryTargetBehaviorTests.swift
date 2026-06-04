import Foundation

@main
struct RecoveryTargetBehaviorTests {
    @MainActor
    static func main() {
        let defaultOutput = AudioOutputDeviceOption(
            id: "built-in-output",
            displayName: "Built-in Output",
            isDefault: true
        )
        let selectedOutput = AudioOutputDeviceOption(
            id: "usb-output",
            displayName: "USB Output",
            isDefault: false
        )

        assertRecoveryTarget(
            defaultOutputDevice: defaultOutput,
            fallbackOutputDevice: selectedOutput,
            expectedID: defaultOutput.id,
            scenario: "real default output wins over fallback"
        )

        assertRecoveryTarget(
            defaultOutputDevice: nil,
            fallbackOutputDevice: selectedOutput,
            expectedID: selectedOutput.id,
            scenario: "selected real output is used when default is VolDeck"
        )

        assertRecoveryTarget(
            defaultOutputDevice: nil,
            fallbackOutputDevice: nil,
            expectedID: nil,
            scenario: "no recovery target is recorded when no real output exists"
        )

        print("VolDeck app recovery behavior tests passed")
    }

    @MainActor
    private static func assertRecoveryTarget(
        defaultOutputDevice: AudioOutputDeviceOption?,
        fallbackOutputDevice: AudioOutputDeviceOption?,
        expectedID: String?,
        scenario: String
    ) {
        let target = OutputHelperController.recoveryTarget(
            defaultOutputDevice: defaultOutputDevice,
            fallbackOutputDevice: fallbackOutputDevice
        )
        guard target?.id == expectedID else {
            let actualID = target?.id ?? "nil"
            let expectedID = expectedID ?? "nil"
            fputs("error: \(scenario): expected \(expectedID), got \(actualID)\n", stderr)
            Foundation.exit(1)
        }
    }
}
