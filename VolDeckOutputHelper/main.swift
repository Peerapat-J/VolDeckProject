import Darwin
import Foundation

private struct HelperEvent: Codable {
    let event: String
    let state: String
    let pid: Int32
    let uptimeSeconds: Double
    let message: String?
}

private final class StopFlag {
    private let lock = NSLock()
    private var stopped = false

    func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var isRequested: Bool {
        lock.lock()
        let value = stopped
        lock.unlock()
        return value
    }
}

private let encoder = JSONEncoder()
private let outputLock = NSLock()

private func emit(event: String, state: String, uptime: TimeInterval = 0, message: String? = nil) {
    let payload = HelperEvent(
        event: event,
        state: state,
        pid: getpid(),
        uptimeSeconds: uptime,
        message: message
    )

    outputLock.lock()
    defer { outputLock.unlock() }

    do {
        let data = try encoder.encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        let fallback = #"{"event":"error","state":"error","message":"encode failed"}"# + "\n"
        if let data = fallback.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

private func runHelper() -> Int32 {
    let stopFlag = StopFlag()
    let startedAt = Date()

    Thread.detachNewThread {
        while let line = readLine() {
            if line.contains(#""stop""#) {
                stopFlag.requestStop()
                break
            }
        }
    }

    emit(event: "status", state: "starting", message: "VolDeck output helper starting")
    emit(event: "status", state: "running", message: "VolDeck output helper running")

    while !stopFlag.isRequested {
        Thread.sleep(forTimeInterval: 1.0)
        if !stopFlag.isRequested {
            emit(event: "heartbeat", state: "running", uptime: Date().timeIntervalSince(startedAt))
        }
    }

    emit(event: "status", state: "stopping", uptime: Date().timeIntervalSince(startedAt), message: "Stop requested")
    return 0
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--health-check") {
    emit(event: "health", state: "ok", message: "VolDeck output helper is available")
    exit(0)
}

if arguments.isEmpty || arguments.contains("--run") {
    exit(runHelper())
}

emit(event: "status", state: "error", message: "Unsupported arguments: \(arguments.joined(separator: " "))")
exit(64)
