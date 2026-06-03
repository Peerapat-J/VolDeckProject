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

    private var process: Process?
    private var standardInput: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = ""
    private var expectedTermination = false
    private var terminationObserver: NSObjectProtocol?

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

    init() {
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

    private func terminateForAppExit() {
        expectedTermination = true
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

        if expectedTermination || terminatedProcess.terminationStatus == 0 {
            state = .stopped
            lastMessage = "Helper stopped"
        } else {
            state = .error
            let exitMessage = "Helper exited with status \(terminatedProcess.terminationStatus)"
            if lastMessage.isEmpty || lastMessage == "Starting helper" {
                lastMessage = exitMessage
            } else if !lastMessage.contains(exitMessage) {
                lastMessage = "\(lastMessage) (\(exitMessage))"
            }
        }

        expectedTermination = false
    }
}

private struct HelperEvent: Decodable {
    let event: String
    let state: String
    let pid: Int32
    let message: String?
    let outputDeviceName: String?
    let playbackActive: Bool?
}
