import Darwin
import Foundation

private struct HelperEvent: Codable {
    let event: String
    let state: String
    let pid: Int32
    let uptimeSeconds: Double
    let message: String?
    var bridgeName: String? = nil
    var capacityFrames: UInt32? = nil
    var channelCount: UInt32? = nil
    var bytesPerFrame: UInt32? = nil
    var sampleRate: UInt64? = nil
    var framesAvailable: UInt64? = nil
    var framesWritten: UInt64? = nil
    var framesRead: UInt64? = nil
    var framesDropped: UInt64? = nil
    var overrunFrames: UInt64? = nil
    var underrunFrames: UInt64? = nil
    var writeCalls: UInt64? = nil
    var readCalls: UInt64? = nil
    var lastWriteFrames: UInt64? = nil
    var lastReadFrames: UInt64? = nil
    var indexAnomalies: UInt64? = nil
}

private struct AudioBridgeHeader {
    var magic: UInt32
    var version: UInt32
    var headerBytes: UInt32
    var capacityFrames: UInt32
    var channelCount: UInt32
    var bytesPerFrame: UInt32
    var flags: UInt32
    var reserved: UInt32
    var sampleRate: UInt64
    var writeFrameIndex: UInt64
    var readFrameIndex: UInt64
    var totalFramesWritten: UInt64
    var totalFramesRead: UInt64
    var totalFramesDropped: UInt64
    var totalOverrunFrames: UInt64
    var totalUnderrunFrames: UInt64
    var totalWriteCalls: UInt64
    var totalReadCalls: UInt64
    var lastWriteFrames: UInt64
    var lastReadFrames: UInt64
    var lastHostTime: UInt64
    var totalIndexAnomalies: UInt64
}

private struct AudioBridgeStatus {
    let bridgeName: String
    let capacityFrames: UInt32
    let channelCount: UInt32
    let bytesPerFrame: UInt32
    let sampleRate: UInt64
    let framesAvailable: UInt64
    let framesWritten: UInt64
    let framesRead: UInt64
    let framesDropped: UInt64
    let overrunFrames: UInt64
    let underrunFrames: UInt64
    let writeCalls: UInt64
    let readCalls: UInt64
    let lastWriteFrames: UInt64
    let lastReadFrames: UInt64
    let indexAnomalies: UInt64
}

private enum AudioBridgeError: Error {
    case openFailed
    case statFailed
    case mapFailed
    case invalidHeader
}

private let audioBridgeMagic: UInt32 = 0x56444247
private let audioBridgeVersion: UInt32 = 1

@_silgen_name("shm_open")
private func cShmOpen(_ name: UnsafePointer<CChar>, _ oflag: CInt, _ mode: mode_t) -> CInt

@_silgen_name("open")
private func cOpen(_ path: UnsafePointer<CChar>, _ oflag: CInt, _ mode: mode_t) -> CInt

@_silgen_name("VolDeckAudioBridgeAtomicLoadUInt64")
private func cAtomicLoadUInt64(_ value: UnsafePointer<UInt64>) -> UInt64

@_silgen_name("VolDeckAudioBridgeAtomicStoreUInt64")
private func cAtomicStoreUInt64(_ value: UnsafeMutablePointer<UInt64>, _ newValue: UInt64)

@_silgen_name("VolDeckAudioBridgeAtomicFetchAddUInt64")
private func cAtomicFetchAddUInt64(_ value: UnsafeMutablePointer<UInt64>, _ amount: UInt64) -> UInt64

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

private func explicitAudioBridgeName() -> String? {
    let overrideName = ProcessInfo.processInfo.environment["VOLDECK_AUDIO_BRIDGE_SHM_NAME"]
    if let overrideName, overrideName.hasPrefix("/"), !overrideName.dropFirst().contains("/") {
        return overrideName
    }

    return nil
}

private func audioBridgeName() -> String {
    explicitAudioBridgeName() ?? "/com.peerapatj.voldeck.audio.bridge.v1"
}

private func audioBridgeFilePath() -> String? {
    if let filePath = ProcessInfo.processInfo.environment["VOLDECK_AUDIO_BRIDGE_FILE_PATH"], !filePath.isEmpty {
        return filePath
    }

    guard explicitAudioBridgeName() == nil else {
        return nil
    }

    return FileManager.default.temporaryDirectory
        .appendingPathComponent("com.peerapatj.voldeck", isDirectory: true)
        .appendingPathComponent("audio.bridge.v1")
        .path
}

private func atomicLoad(_ value: UnsafePointer<UInt64>) -> UInt64 {
    cAtomicLoadUInt64(value)
}

private func atomicStore(_ value: UnsafeMutablePointer<UInt64>, _ newValue: UInt64) {
    cAtomicStoreUInt64(value, newValue)
}

@discardableResult
private func atomicFetchAdd(_ value: UnsafeMutablePointer<UInt64>, _ amount: UInt64) -> UInt64 {
    cAtomicFetchAddUInt64(value, amount)
}

private func emit(
    event: String,
    state: String,
    uptime: TimeInterval = 0,
    message: String? = nil,
    bridgeStatus: AudioBridgeStatus? = nil
) {
    let payload = HelperEvent(
        event: event,
        state: state,
        pid: getpid(),
        uptimeSeconds: uptime,
        message: message,
        bridgeName: bridgeStatus?.bridgeName,
        capacityFrames: bridgeStatus?.capacityFrames,
        channelCount: bridgeStatus?.channelCount,
        bytesPerFrame: bridgeStatus?.bytesPerFrame,
        sampleRate: bridgeStatus?.sampleRate,
        framesAvailable: bridgeStatus?.framesAvailable,
        framesWritten: bridgeStatus?.framesWritten,
        framesRead: bridgeStatus?.framesRead,
        framesDropped: bridgeStatus?.framesDropped,
        overrunFrames: bridgeStatus?.overrunFrames,
        underrunFrames: bridgeStatus?.underrunFrames,
        writeCalls: bridgeStatus?.writeCalls,
        readCalls: bridgeStatus?.readCalls,
        lastWriteFrames: bridgeStatus?.lastWriteFrames,
        lastReadFrames: bridgeStatus?.lastReadFrames,
        indexAnomalies: bridgeStatus?.indexAnomalies
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

private func readAudioBridge(consumeFrameLimit: UInt64? = nil) throws -> AudioBridgeStatus {
    let name = audioBridgeName()
    let filePath = audioBridgeFilePath()
    let descriptor: CInt
    if let filePath {
        descriptor = filePath.withCString { cOpen($0, O_RDWR | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR)) }
    } else {
        descriptor = name.withCString { cShmOpen($0, O_RDWR, mode_t(S_IRUSR | S_IWUSR)) }
    }
    guard descriptor != -1 else {
        throw AudioBridgeError.openFailed
    }
    defer {
        close(descriptor)
    }

    var statBuffer = stat()
    guard fstat(descriptor, &statBuffer) == 0, statBuffer.st_size >= MemoryLayout<AudioBridgeHeader>.stride else {
        throw AudioBridgeError.statFailed
    }

    let mapSize = Int(statBuffer.st_size)
    let mapping = mmap(nil, mapSize, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
    guard mapping != MAP_FAILED, let mapping else {
        throw AudioBridgeError.mapFailed
    }
    defer {
        munmap(mapping, mapSize)
    }

    let header = mapping.assumingMemoryBound(to: AudioBridgeHeader.self)
    guard header.pointee.magic == audioBridgeMagic,
          header.pointee.version == audioBridgeVersion,
          Int(header.pointee.headerBytes) >= MemoryLayout<AudioBridgeHeader>.stride else {
        throw AudioBridgeError.invalidHeader
    }

    let headerBytes = Int(header.pointee.headerBytes)
    let bytesPerFrame = Int(header.pointee.bytesPerFrame)
    let capacityFrameCount = Int(header.pointee.capacityFrames)
    guard bytesPerFrame > 0,
          capacityFrameCount > 0,
          mapSize >= headerBytes + (capacityFrameCount * bytesPerFrame) else {
        throw AudioBridgeError.invalidHeader
    }

    var writeFrameIndex = withUnsafePointer(to: &header.pointee.writeFrameIndex) { atomicLoad($0) }
    var readFrameIndex = withUnsafePointer(to: &header.pointee.readFrameIndex) { atomicLoad($0) }
    let capacityFrames = UInt64(header.pointee.capacityFrames)
    var framesAvailable = writeFrameIndex >= readFrameIndex ? writeFrameIndex - readFrameIndex : 0
    if framesAvailable > capacityFrames {
        framesAvailable = capacityFrames
        readFrameIndex = writeFrameIndex - capacityFrames
        withUnsafeMutablePointer(to: &header.pointee.readFrameIndex) { atomicStore($0, readFrameIndex) }
    }

    if let consumeFrameLimit {
        let framesToRead = min(framesAvailable, consumeFrameLimit)
        if framesToRead > 0 {
            // This probe copies from mapping/readFrameIndex into scratch only to
            // exercise framesToRead * bytesPerFrame movement without exposing
            // audio contents.
            var scratch = Data(count: Int(framesToRead) * bytesPerFrame)
            scratch.withUnsafeMutableBytes { destination in
                guard let destinationBase = destination.baseAddress else {
                    return
                }

                let firstRingFrame = Int(readFrameIndex % capacityFrames)
                let firstFrameCount = min(Int(framesToRead), capacityFrameCount - firstRingFrame)
                let firstByteCount = firstFrameCount * bytesPerFrame
                let sourceBase = mapping.advanced(by: headerBytes + (firstRingFrame * bytesPerFrame))
                memcpy(destinationBase, sourceBase, firstByteCount)

                let remainingFrameCount = Int(framesToRead) - firstFrameCount
                if remainingFrameCount > 0 {
                    memcpy(destinationBase.advanced(by: firstByteCount), mapping.advanced(by: headerBytes), remainingFrameCount * bytesPerFrame)
                }
            }

            withUnsafeMutablePointer(to: &header.pointee.readFrameIndex) { atomicStore($0, readFrameIndex + framesToRead) }
            _ = withUnsafeMutablePointer(to: &header.pointee.totalFramesRead) { atomicFetchAdd($0, framesToRead) }
        }

        if consumeFrameLimit > framesToRead {
            _ = withUnsafeMutablePointer(to: &header.pointee.totalUnderrunFrames) { atomicFetchAdd($0, consumeFrameLimit - framesToRead) }
        }

        _ = withUnsafeMutablePointer(to: &header.pointee.totalReadCalls) { atomicFetchAdd($0, 1) }
        withUnsafeMutablePointer(to: &header.pointee.lastReadFrames) { atomicStore($0, framesToRead) }
        writeFrameIndex = withUnsafePointer(to: &header.pointee.writeFrameIndex) { atomicLoad($0) }
        readFrameIndex = withUnsafePointer(to: &header.pointee.readFrameIndex) { atomicLoad($0) }
        framesAvailable = writeFrameIndex >= readFrameIndex ? writeFrameIndex - readFrameIndex : 0
    }

    return AudioBridgeStatus(
        bridgeName: filePath ?? name,
        capacityFrames: header.pointee.capacityFrames,
        channelCount: header.pointee.channelCount,
        bytesPerFrame: header.pointee.bytesPerFrame,
        sampleRate: withUnsafePointer(to: &header.pointee.sampleRate) { atomicLoad($0) },
        framesAvailable: framesAvailable,
        framesWritten: withUnsafePointer(to: &header.pointee.totalFramesWritten) { atomicLoad($0) },
        framesRead: withUnsafePointer(to: &header.pointee.totalFramesRead) { atomicLoad($0) },
        framesDropped: withUnsafePointer(to: &header.pointee.totalFramesDropped) { atomicLoad($0) },
        overrunFrames: withUnsafePointer(to: &header.pointee.totalOverrunFrames) { atomicLoad($0) },
        underrunFrames: withUnsafePointer(to: &header.pointee.totalUnderrunFrames) { atomicLoad($0) },
        writeCalls: withUnsafePointer(to: &header.pointee.totalWriteCalls) { atomicLoad($0) },
        readCalls: withUnsafePointer(to: &header.pointee.totalReadCalls) { atomicLoad($0) },
        lastWriteFrames: withUnsafePointer(to: &header.pointee.lastWriteFrames) { atomicLoad($0) },
        lastReadFrames: withUnsafePointer(to: &header.pointee.lastReadFrames) { atomicLoad($0) },
        indexAnomalies: withUnsafePointer(to: &header.pointee.totalIndexAnomalies) { atomicLoad($0) }
    )
}

private func emitAudioBridgeStatus(consumeFrameLimit: UInt64? = nil) -> Int32 {
    do {
        let status = try readAudioBridge(consumeFrameLimit: consumeFrameLimit)
        let message: String
        if let consumeFrameLimit {
            message = "Read up to \(consumeFrameLimit) frame(s) from VolDeck audio bridge"
        } else {
            message = "VolDeck audio bridge is available"
        }
        emit(event: "buffer", state: "ok", message: message, bridgeStatus: status)
        return 0
    } catch {
        emit(event: "buffer", state: "error", message: "VolDeck audio bridge is not available: \(error)")
        return 65
    }
}

private func unlinkAudioBridge() -> Int32 {
    if let filePath = audioBridgeFilePath() {
        if unlink(filePath) == 0 || errno == ENOENT {
            emit(event: "buffer", state: "ok", message: "VolDeck audio bridge was unlinked")
            return 0
        }
    } else if shm_unlink(audioBridgeName()) == 0 || errno == ENOENT {
        emit(event: "buffer", state: "ok", message: "VolDeck audio bridge was unlinked")
        return 0
    }

    emit(event: "buffer", state: "error", message: "Could not unlink VolDeck audio bridge")
    return 66
}

private func runHelper() -> Int32 {
    let stopFlag = StopFlag()
    let startedAt = Date()

    Thread.detachNewThread {
        while true {
            guard let line = readLine() else {
                stopFlag.requestStop()
                break
            }

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

if arguments.contains("--buffer-status") {
    exit(emitAudioBridgeStatus())
}

if arguments.contains("--buffer-unlink") {
    exit(unlinkAudioBridge())
}

if let readIndex = arguments.firstIndex(of: "--buffer-read-once") {
    let nextIndex = arguments.index(after: readIndex)
    let requestedFrames: UInt64
    if nextIndex < arguments.endIndex {
        let token = arguments[nextIndex]
        guard let parsedFrames = UInt64(token) else {
            emit(event: "buffer", state: "error", message: "Invalid --buffer-read-once frame count: \(token)")
            exit(64)
        }

        requestedFrames = parsedFrames
    } else {
        requestedFrames = 256
    }

    exit(emitAudioBridgeStatus(consumeFrameLimit: requestedFrames))
}

if arguments.isEmpty || arguments.contains("--run") {
    exit(runHelper())
}

emit(event: "status", state: "error", message: "Unsupported arguments: \(arguments.joined(separator: " "))")
exit(64)
