import AppKit
import Foundation

@MainActor
final class OutputHelperController: ObservableObject {
    enum State: String {
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case stopping = "Stopping"
        case error = "Error"
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var processID: Int32?
    @Published private(set) var lastMessage: String = "Helper has not started"
    @Published private(set) var lastHeartbeat: Date?
    @Published private(set) var helperLocation: String = "Not resolved"
    @Published private(set) var recoveryStatus: String = "No recovery action needed"
    @Published private(set) var diagnosticsSummary: String = "No buffer diagnostics yet"

    private var process: Process?
    private var standardInput: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = ""
    private var expectedTermination = false
    private var terminationObserver: NSObjectProtocol?
    private var restartAfterTermination = false
    private var restartOutputDeviceUID: String?
    private let defaults: UserDefaults

    private enum RecoveryKeys {
        static let previousOutputDeviceID = "previousOutputDeviceID"
        static let previousOutputName = "previousOutputName"
    }

    var statusText: String {
        if let processID {
            return "\(state.rawValue) (pid \(processID))"
        }
        return state.rawValue
    }

    var canStart: Bool {
        process == nil && state != .starting && state != .running
    }

    var canStop: Bool {
        process != nil && state != .stopping
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.terminateForAppExit()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func start(outputDeviceUID: String? = nil) {
        guard canStart else {
            return
        }

        guard let helperURL = resolveHelperURL() else {
            state = .error
            processID = nil
            lastMessage = "VolDeckOutputHelper was not found. Build the helper target first."
            helperLocation = "Missing"
            return
        }

        let helperProcess = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        helperProcess.executableURL = helperURL
        var arguments = ["--run", "--play-through"]
        if let outputDeviceUID,
           outputDeviceUID != AudioOutputDeviceCatalog.systemDefaultOutputDeviceID {
            arguments.append(contentsOf: ["--output-device-uid", outputDeviceUID])
        }
        helperProcess.arguments = arguments
        helperProcess.standardOutput = outputPipe
        helperProcess.standardError = errorPipe
        helperProcess.standardInput = inputPipe

        state = .starting
        processID = nil
        lastMessage = "Starting helper"
        lastHeartbeat = nil
        helperLocation = helperURL.path
        expectedTermination = false
        rememberPreviousOutputForRecovery()
        standardInput = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.handleOutput(chunk)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.lastMessage = message.isEmpty ? "Helper wrote to stderr" : message
            }
        }

        helperProcess.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleTermination(process)
            }
        }

        do {
            try helperProcess.run()
            process = helperProcess
            processID = helperProcess.processIdentifier
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            standardInput = nil
            self.outputPipe = nil
            self.errorPipe = nil
            processID = nil
            state = .error
            lastMessage = "Could not start helper: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let process else {
            state = .stopped
            processID = nil
            lastMessage = "Helper is not running"
            return
        }

        expectedTermination = true
        state = .stopping
        lastMessage = "Stopping helper"

        if process.isRunning,
           let inputHandle = standardInput?.fileHandleForWriting,
           let command = #"{"command":"stop"}"#.appending("\n").data(using: .utf8) {
            try? inputHandle.write(contentsOf: command)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak process] in
            Task { @MainActor in
                guard let self, let process, self.process === process, process.isRunning else {
                    return
                }
                process.terminate()
            }
        }
    }

    func restart(outputDeviceUID: String? = nil) {
        if canStart {
            start(outputDeviceUID: outputDeviceUID)
            return
        }

        restartAfterTermination = true
        restartOutputDeviceUID = outputDeviceUID
        stop()
    }

    private func terminateForAppExit() {
        expectedTermination = true
        restartAfterTermination = false
        restartOutputDeviceUID = nil
        process?.terminate()
    }

    private func resolveHelperURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Helpers/VolDeckOutputHelper"),
            bundleURL.deletingLastPathComponent().appendingPathComponent("VolDeckOutputHelper"),
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func handleOutput(_ chunk: String) {
        outputBuffer += chunk

        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            return
        }

        do {
            let event = try JSONDecoder().decode(HelperEvent.self, from: data)
            processID = event.pid
            if let outputDeviceName = event.outputDeviceName, event.playbackActive == true {
                lastMessage = event.message ?? "Forwarding to \(outputDeviceName)"
            } else {
                lastMessage = event.message ?? event.event
            }
            if let diagnosticsSummary = event.diagnosticsSummary {
                self.diagnosticsSummary = diagnosticsSummary
            }

            switch event.state {
            case "starting":
                state = .starting
            case "running", "ok":
                state = .running
                lastHeartbeat = Date()
            case "stopping":
                state = .stopping
            case "error":
                state = .error
            default:
                break
            }
        } catch {
            lastMessage = line
        }
    }

    private func handleTermination(_ terminatedProcess: Process) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        terminatedProcess.standardOutput = nil
        terminatedProcess.standardError = nil
        terminatedProcess.standardInput = nil

        process = nil
        standardInput = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer = ""
        processID = nil

        if expectedTermination {
            state = .stopped
            lastMessage = "Helper stopped"
            recoveryStatus = "No recovery action needed"
        } else {
            state = .error
            let exitMessage = "Helper exited with status \(terminatedProcess.terminationStatus)"
            if lastMessage.isEmpty || lastMessage == "Starting helper" {
                lastMessage = exitMessage
            } else if !lastMessage.contains(exitMessage) {
                lastMessage = "\(lastMessage) (\(exitMessage))"
            }

            recoveryStatus = restorePreviousOutputAfterUnexpectedTermination()
            if !lastMessage.contains(recoveryStatus) {
                lastMessage = "\(lastMessage). \(recoveryStatus)"
            }
        }

        let shouldRestart = restartAfterTermination
        let nextOutputDeviceUID = restartOutputDeviceUID
        restartAfterTermination = false
        restartOutputDeviceUID = nil
        expectedTermination = false

        if shouldRestart {
            start(outputDeviceUID: nextOutputDeviceUID)
        }
    }

    private func rememberPreviousOutputForRecovery() {
        guard let outputDevice = AudioOutputDeviceCatalog.currentDefaultRealOutputDevice() else {
            defaults.removeObject(forKey: RecoveryKeys.previousOutputDeviceID)
            defaults.removeObject(forKey: RecoveryKeys.previousOutputName)
            recoveryStatus = "No real default output was available to remember"
            return
        }

        defaults.set(outputDevice.id, forKey: RecoveryKeys.previousOutputDeviceID)
        defaults.set(outputDevice.displayName, forKey: RecoveryKeys.previousOutputName)
        recoveryStatus = "Recovery target: \(outputDevice.displayName)"
    }

    private func restorePreviousOutputAfterUnexpectedTermination() -> String {
        guard let previousOutputID = defaults.string(forKey: RecoveryKeys.previousOutputDeviceID),
              !previousOutputID.isEmpty else {
            return "Helper failed. Open System Settings > Sound and choose a real output device."
        }

        let previousName = defaults.string(forKey: RecoveryKeys.previousOutputName) ?? previousOutputID
        do {
            let restoredDevice = try AudioOutputDeviceCatalog.setDefaultOutputDevice(id: previousOutputID)
            return "Restored output to \(restoredDevice.displayName)"
        } catch {
            return "Could not restore \(previousName): \(error.localizedDescription). Open System Settings > Sound and choose a real output device."
        }
    }
}

private struct HelperEvent: Decodable {
    let event: String
    let state: String
    let pid: Int32
    let message: String?
    let sampleRate: UInt64?
    let framesAvailable: UInt64?
    let overrunFrames: UInt64?
    let underrunFrames: UInt64?
    let estimatedBufferLatencyMilliseconds: Double?
    let outputDeviceName: String?
    let outputDeviceSampleRate: UInt64?
    let playbackActive: Bool?

    var diagnosticsSummary: String? {
        var parts = [String]()
        if let estimatedBufferLatencyMilliseconds {
            parts.append(String(format: "latency %.1f ms", estimatedBufferLatencyMilliseconds))
        }
        if let framesAvailable {
            parts.append("\(framesAvailable) frame(s) buffered")
        }
        if let underrunFrames {
            parts.append("\(underrunFrames) underrun frame(s)")
        }
        if let overrunFrames {
            parts.append("\(overrunFrames) overrun frame(s)")
        }
        if let sampleRate, let outputDeviceSampleRate {
            parts.append("bridge \(sampleRate) Hz / output \(outputDeviceSampleRate) Hz")
        } else if let sampleRate {
            parts.append("bridge \(sampleRate) Hz")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}
