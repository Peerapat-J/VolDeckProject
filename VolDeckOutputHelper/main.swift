import Darwin
import AudioToolbox
import CoreAudio
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
    var outputDeviceUID: String? = nil
    var outputDeviceName: String? = nil
    var playbackActive: Bool? = nil
}

private struct OutputDeviceListEvent: Codable {
    let event: String
    let state: String
    let pid: Int32
    let uptimeSeconds: Double
    let message: String?
    let devices: [OutputDeviceInfo]
}

private struct OutputDeviceInfo: Codable {
    let uid: String
    let name: String
    let isDefault: Bool
    let sampleRate: UInt64
    let channelCount: UInt32
}

private struct SelectedOutputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let sampleRate: UInt64
    let channelCount: UInt32
    let bufferFrameSize: UInt32
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

private enum OutputDeviceError: Error, CustomStringConvertible {
    case noDefaultOutput
    case noMatchingOutput(String)
    case unsupportedOutputFormat(String)
    case coreAudio(OSStatus, String)

    var description: String {
        switch self {
        case .noDefaultOutput:
            "No default output device is available"
        case .noMatchingOutput(let uid):
            "No output device matches UID \(uid)"
        case .unsupportedOutputFormat(let name):
            "Output device \(name) does not expose a Float32 playback format supported by this M3 slice"
        case .coreAudio(let status, let operation):
            "\(operation) failed with OSStatus \(status)"
        }
    }
}

private let audioBridgeMagic: UInt32 = 0x56444247
private let audioBridgeVersion: UInt32 = 1
private let systemDefaultOutputDeviceUID = "__system_default__"
private let volDeckOutputDeviceUID = "com.peerapatj.voldeck.output"

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

private func audioObjectPropertyDataSize(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyDataSize(\(selector))")
    }
    return dataSize
}

private func audioObjectDeviceIDProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value = AudioDeviceID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.stride)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(\(selector))")
    }
    return value
}

private func audioObjectUInt32Property(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    defaultValue: UInt32
) throws -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value = defaultValue
    var dataSize = UInt32(MemoryLayout<UInt32>.stride)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(\(selector))")
    }
    return value
}

private func audioObjectFloat64Property(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    defaultValue: Float64
) throws -> Float64 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value = defaultValue
    var dataSize = UInt32(MemoryLayout<Float64>.stride)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(\(selector))")
    }
    return value
}

private func audioObjectStringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(\(selector))")
    }
    guard let value else {
        throw OutputDeviceError.coreAudio(kAudioHardwareUnspecifiedError, "AudioObjectGetPropertyData(\(selector))")
    }
    return value.takeRetainedValue() as String
}

private func outputChannelCount(for deviceID: AudioDeviceID) throws -> UInt32 {
    let dataSize = try audioObjectPropertyDataSize(
        objectID: deviceID,
        selector: kAudioDevicePropertyStreamConfiguration,
        scope: kAudioDevicePropertyScopeOutput
    )
    guard dataSize >= UInt32(MemoryLayout<AudioBufferList>.stride) else {
        return 0
    }

    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(dataSize),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer {
        buffer.deallocate()
    }

    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableDataSize = dataSize
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &mutableDataSize, buffer)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(streamConfiguration)")
    }

    let audioBufferList = buffer.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
    return buffers.reduce(UInt32(0)) { partial, audioBuffer in
        partial + audioBuffer.mNumberChannels
    }
}

private func defaultOutputDeviceID() throws -> AudioDeviceID {
    let deviceID = try audioObjectDeviceIDProperty(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice
    )
    guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
        throw OutputDeviceError.noDefaultOutput
    }
    return deviceID
}

private func outputDeviceInfos() throws -> [OutputDeviceInfo] {
    let systemObject = AudioObjectID(kAudioObjectSystemObject)
    let dataSize = try audioObjectPropertyDataSize(
        objectID: systemObject,
        selector: kAudioHardwarePropertyDevices
    )
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    guard deviceCount > 0 else {
        return []
    }

    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableDataSize = dataSize
    var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: deviceCount)
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &mutableDataSize, &deviceIDs)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(devices)")
    }

    let defaultID = try? defaultOutputDeviceID()
    return try deviceIDs.compactMap { deviceID in
        let channelCount = try outputChannelCount(for: deviceID)
        guard channelCount > 0 else {
            return nil
        }

        let uid = try audioObjectStringProperty(objectID: deviceID, selector: kAudioDevicePropertyDeviceUID)
        guard uid != volDeckOutputDeviceUID else {
            return nil
        }

        let name = try audioObjectStringProperty(objectID: deviceID, selector: kAudioObjectPropertyName)
        let sampleRate = try audioObjectFloat64Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyNominalSampleRate,
            defaultValue: Float64(0)
        )
        return OutputDeviceInfo(
            uid: uid,
            name: name,
            isDefault: defaultID == deviceID,
            sampleRate: UInt64(sampleRate.rounded()),
            channelCount: channelCount
        )
    }.sorted { lhs, rhs in
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private func selectedOutputDevice(uid requestedUID: String?) throws -> SelectedOutputDevice {
    let requestedUID = requestedUID == systemDefaultOutputDeviceUID ? nil : requestedUID
    let deviceInfos = try outputDeviceInfos()
    let selectedInfo: OutputDeviceInfo

    if let requestedUID, !requestedUID.isEmpty {
        guard let matchingInfo = deviceInfos.first(where: { $0.uid == requestedUID }) else {
            throw OutputDeviceError.noMatchingOutput(requestedUID)
        }
        selectedInfo = matchingInfo
    } else {
        guard let defaultInfo = deviceInfos.first(where: \.isDefault) else {
            throw OutputDeviceError.noDefaultOutput
        }
        selectedInfo = defaultInfo
    }

    let dataSize = try audioObjectPropertyDataSize(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDevices
    )
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableDataSize = dataSize
    var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: deviceCount)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &mutableDataSize, &deviceIDs)
    guard status == noErr else {
        throw OutputDeviceError.coreAudio(status, "AudioObjectGetPropertyData(devices)")
    }

    guard let deviceID = try deviceIDs.first(where: {
        try audioObjectStringProperty(objectID: $0, selector: kAudioDevicePropertyDeviceUID) == selectedInfo.uid
    }) else {
        throw OutputDeviceError.noMatchingOutput(selectedInfo.uid)
    }

    let bufferFrameSize = try audioObjectUInt32Property(
        objectID: deviceID,
        selector: kAudioDevicePropertyBufferFrameSize,
        defaultValue: UInt32(512)
    )
    return SelectedOutputDevice(
        id: deviceID,
        uid: selectedInfo.uid,
        name: selectedInfo.name,
        sampleRate: selectedInfo.sampleRate,
        channelCount: selectedInfo.channelCount,
        bufferFrameSize: max(128, bufferFrameSize)
    )
}

private func emit(
    event: String,
    state: String,
    uptime: TimeInterval = 0,
    message: String? = nil,
    bridgeStatus: AudioBridgeStatus? = nil,
    outputDevice: SelectedOutputDevice? = nil,
    playbackActive: Bool? = nil
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
        indexAnomalies: bridgeStatus?.indexAnomalies,
        outputDeviceUID: outputDevice?.uid,
        outputDeviceName: outputDevice?.name,
        playbackActive: playbackActive
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

private func emitOutputDevices(_ devices: [OutputDeviceInfo], message: String) {
    let payload = OutputDeviceListEvent(
        event: "outputDevices",
        state: "ok",
        pid: getpid(),
        uptimeSeconds: 0,
        message: message,
        devices: devices
    )

    outputLock.lock()
    defer { outputLock.unlock() }

    do {
        let data = try encoder.encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        let fallback = #"{"event":"outputDevices","state":"error","message":"encode failed"}"# + "\n"
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

private final class AudioBridgePlaybackReader {
    private let descriptor: CInt
    private let mapping: UnsafeMutableRawPointer
    private let mapSize: Int
    private let header: UnsafeMutablePointer<AudioBridgeHeader>
    private let frames: UnsafeMutableRawPointer

    let bridgeName: String
    let channelCount: UInt32
    let bytesPerFrame: UInt32
    let sampleRate: UInt64
    let capacityFrames: UInt32

    init() throws {
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

        var statBuffer = stat()
        guard fstat(descriptor, &statBuffer) == 0, statBuffer.st_size >= MemoryLayout<AudioBridgeHeader>.stride else {
            close(descriptor)
            throw AudioBridgeError.statFailed
        }

        let mapSize = Int(statBuffer.st_size)
        guard let mapping = mmap(nil, mapSize, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0), mapping != MAP_FAILED else {
            close(descriptor)
            throw AudioBridgeError.mapFailed
        }

        let header = mapping.assumingMemoryBound(to: AudioBridgeHeader.self)
        guard header.pointee.magic == audioBridgeMagic,
              header.pointee.version == audioBridgeVersion,
              Int(header.pointee.headerBytes) >= MemoryLayout<AudioBridgeHeader>.stride else {
            munmap(mapping, mapSize)
            close(descriptor)
            throw AudioBridgeError.invalidHeader
        }

        let headerBytes = Int(header.pointee.headerBytes)
        let bytesPerFrame = Int(header.pointee.bytesPerFrame)
        let capacityFrameCount = Int(header.pointee.capacityFrames)
        guard header.pointee.channelCount == 2,
              header.pointee.bytesPerFrame == UInt32(MemoryLayout<Float32>.stride * 2),
              bytesPerFrame > 0,
              capacityFrameCount > 0,
              mapSize >= headerBytes + (capacityFrameCount * bytesPerFrame) else {
            munmap(mapping, mapSize)
            close(descriptor)
            throw AudioBridgeError.invalidHeader
        }

        self.descriptor = descriptor
        self.mapping = mapping
        self.mapSize = mapSize
        self.header = header
        self.frames = mapping.advanced(by: headerBytes)
        self.bridgeName = filePath ?? name
        self.channelCount = header.pointee.channelCount
        self.bytesPerFrame = header.pointee.bytesPerFrame
        self.sampleRate = withUnsafePointer(to: &header.pointee.sampleRate) { atomicLoad($0) }
        self.capacityFrames = header.pointee.capacityFrames
    }

    deinit {
        munmap(mapping, mapSize)
        close(descriptor)
    }

    func readInterleavedFloat32(into destination: UnsafeMutablePointer<Float32>, requestedFrames: UInt32) -> UInt32 {
        guard requestedFrames > 0 else {
            return 0
        }

        var writeFrameIndex = withUnsafePointer(to: &header.pointee.writeFrameIndex) { atomicLoad($0) }
        var readFrameIndex = withUnsafePointer(to: &header.pointee.readFrameIndex) { atomicLoad($0) }
        let capacity = UInt64(capacityFrames)
        var framesAvailable = writeFrameIndex >= readFrameIndex ? writeFrameIndex - readFrameIndex : 0
        if framesAvailable > capacity {
            framesAvailable = capacity
            readFrameIndex = writeFrameIndex - capacity
            withUnsafeMutablePointer(to: &header.pointee.readFrameIndex) { atomicStore($0, readFrameIndex) }
        }

        let framesToRead = UInt32(min(framesAvailable, UInt64(requestedFrames)))
        if framesToRead > 0 {
            let firstRingFrame = Int(readFrameIndex % capacity)
            let firstFrameCount = min(Int(framesToRead), Int(capacityFrames) - firstRingFrame)
            let firstSampleCount = firstFrameCount * Int(channelCount)
            let source = frames
                .advanced(by: firstRingFrame * Int(bytesPerFrame))
                .assumingMemoryBound(to: Float32.self)
            destination.update(from: source, count: firstSampleCount)

            let remainingFrameCount = Int(framesToRead) - firstFrameCount
            if remainingFrameCount > 0 {
                let remainingSampleCount = remainingFrameCount * Int(channelCount)
                let wrappedSource = frames.assumingMemoryBound(to: Float32.self)
                destination.advanced(by: firstSampleCount).update(from: wrappedSource, count: remainingSampleCount)
            }

            withUnsafeMutablePointer(to: &header.pointee.readFrameIndex) {
                atomicStore($0, readFrameIndex + UInt64(framesToRead))
            }
            _ = withUnsafeMutablePointer(to: &header.pointee.totalFramesRead) {
                atomicFetchAdd($0, UInt64(framesToRead))
            }
        }

        if requestedFrames > framesToRead {
            _ = withUnsafeMutablePointer(to: &header.pointee.totalUnderrunFrames) {
                atomicFetchAdd($0, UInt64(requestedFrames - framesToRead))
            }
        }

        _ = withUnsafeMutablePointer(to: &header.pointee.totalReadCalls) { atomicFetchAdd($0, 1) }
        withUnsafeMutablePointer(to: &header.pointee.lastReadFrames) { atomicStore($0, UInt64(framesToRead)) }

        writeFrameIndex = withUnsafePointer(to: &header.pointee.writeFrameIndex) { atomicLoad($0) }
        readFrameIndex = withUnsafePointer(to: &header.pointee.readFrameIndex) { atomicLoad($0) }
        if writeFrameIndex < readFrameIndex {
            _ = withUnsafeMutablePointer(to: &header.pointee.totalIndexAnomalies) { atomicFetchAdd($0, 1) }
        }

        return framesToRead
    }
}

private let audioQueueOutputCallback: AudioQueueOutputCallback = { userData, queue, buffer in
    guard let userData else {
        return
    }

    let engine = Unmanaged<OutputPlaybackEngine>.fromOpaque(userData).takeUnretainedValue()
    engine.fillAndEnqueue(queue: queue, buffer: buffer)
}

private final class OutputPlaybackEngine {
    let outputDevice: SelectedOutputDevice
    private let bridgeReader: AudioBridgePlaybackReader
    private var queue: AudioQueueRef?
    private let bufferFrames: UInt32
    private let bufferByteCount: UInt32
    private var stopRequested: UInt64 = 0
    private var playbackFailure: UInt64 = 0

    init(outputDevice: SelectedOutputDevice, bridgeReader: AudioBridgePlaybackReader) throws {
        self.outputDevice = outputDevice
        self.bridgeReader = bridgeReader
        self.bufferFrames = min(max(outputDevice.bufferFrameSize, 128), 2048)
        self.bufferByteCount = bufferFrames * bridgeReader.bytesPerFrame

        var format = AudioStreamBasicDescription(
            mSampleRate: Float64(bridgeReader.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bridgeReader.bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bridgeReader.bytesPerFrame,
            mChannelsPerFrame: bridgeReader.channelCount,
            mBitsPerChannel: UInt32(MemoryLayout<Float32>.stride * 8),
            mReserved: 0
        )

        var createdQueue: AudioQueueRef?
        let queueStatus = AudioQueueNewOutput(
            &format,
            audioQueueOutputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &createdQueue
        )
        guard queueStatus == noErr, let createdQueue else {
            throw OutputDeviceError.coreAudio(queueStatus, "AudioQueueNewOutput")
        }

        var deviceUID = Unmanaged.passRetained(outputDevice.uid as CFString)
        defer {
            deviceUID.release()
        }
        let propertySize = UInt32(MemoryLayout<Unmanaged<CFString>>.stride)
        let deviceStatus = AudioQueueSetProperty(
            createdQueue,
            kAudioQueueProperty_CurrentDevice,
            &deviceUID,
            propertySize
        )
        guard deviceStatus == noErr else {
            AudioQueueDispose(createdQueue, true)
            throw OutputDeviceError.coreAudio(deviceStatus, "AudioQueueSetProperty(CurrentDevice)")
        }

        queue = createdQueue
    }

    deinit {
        stop()
    }

    func start() throws {
        guard let queue else {
            throw OutputDeviceError.coreAudio(-1, "AudioQueueStart")
        }

        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            let allocateStatus = AudioQueueAllocateBuffer(queue, bufferByteCount, &buffer)
            guard allocateStatus == noErr, let buffer else {
                throw OutputDeviceError.coreAudio(allocateStatus, "AudioQueueAllocateBuffer")
            }
            fillAndEnqueue(queue: queue, buffer: buffer)
        }

        let startStatus = AudioQueueStart(queue, nil)
        guard startStatus == noErr else {
            throw OutputDeviceError.coreAudio(startStatus, "AudioQueueStart")
        }
    }

    func stop() {
        requestStop()
        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            self.queue = nil
        }
    }

    func fillAndEnqueue(queue: AudioQueueRef, buffer: AudioQueueBufferRef) {
        guard !isStopRequested else {
            return
        }

        let framesRequested = bufferFrames
        let sampleCount = Int(framesRequested * bridgeReader.channelCount)
        let audioData = buffer.pointee.mAudioData.assumingMemoryBound(to: Float32.self)
        let framesRead = bridgeReader.readInterleavedFloat32(into: audioData, requestedFrames: framesRequested)

        if framesRead < framesRequested {
            let firstSilentSample = Int(framesRead * bridgeReader.channelCount)
            let silentSampleCount = sampleCount - firstSilentSample
            if silentSampleCount > 0 {
                memset(audioData.advanced(by: firstSilentSample), 0, silentSampleCount * MemoryLayout<Float32>.stride)
            }
        }

        buffer.pointee.mAudioDataByteSize = bufferByteCount
        let enqueueStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        if enqueueStatus != noErr {
            requestFailure()
        }
    }

    var didFail: Bool {
        withUnsafePointer(to: &playbackFailure) { atomicLoad($0) != 0 }
    }

    private var isStopRequested: Bool {
        withUnsafePointer(to: &stopRequested) { atomicLoad($0) != 0 }
    }

    private func requestStop() {
        withUnsafeMutablePointer(to: &stopRequested) { atomicStore($0, 1) }
    }

    private func requestFailure() {
        withUnsafeMutablePointer(to: &playbackFailure) { atomicStore($0, 1) }
        requestStop()
    }
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

private func errorMessage(_ error: Error) -> String {
    return String(describing: error)
}

private func emitOutputDeviceList() -> Int32 {
    do {
        let devices = try outputDeviceInfos()
        emitOutputDevices(devices, message: "Available output devices")
        return 0
    } catch {
        emit(event: "outputDevices", state: "error", message: "Could not enumerate output devices: \(errorMessage(error))")
        return 65
    }
}

private func runHelper(playThrough: Bool = false, outputDeviceUID: String? = nil) -> Int32 {
    let stopFlag = StopFlag()
    let startedAt = Date()
    var playbackEngine: OutputPlaybackEngine?
    var activeOutputDevice: SelectedOutputDevice?
    var lastWaitMessage: String?

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

    if playThrough {
        emit(event: "status", state: "running", message: "Waiting for VolDeck audio bridge", playbackActive: false)
    } else {
        emit(event: "status", state: "running", message: "VolDeck output helper running")
    }

    while !stopFlag.isRequested {
        if playThrough, playbackEngine == nil {
            do {
                let outputDevice = try selectedOutputDevice(uid: outputDeviceUID)
                let bridgeReader = try AudioBridgePlaybackReader()
                let engine = try OutputPlaybackEngine(outputDevice: outputDevice, bridgeReader: bridgeReader)
                try engine.start()
                activeOutputDevice = outputDevice
                playbackEngine = engine
                lastWaitMessage = nil
                emit(
                    event: "status",
                    state: "running",
                    message: "Forwarding VolDeck audio to \(outputDevice.name)",
                    outputDevice: outputDevice,
                    playbackActive: true
                )
            } catch {
                let waitMessage = "Waiting for output pass-through: \(errorMessage(error))"
                if waitMessage != lastWaitMessage {
                    lastWaitMessage = waitMessage
                    emit(event: "status", state: "running", message: waitMessage, playbackActive: false)
                }
            }
        }

        Thread.sleep(forTimeInterval: 1.0)
        if let playbackEngine, playbackEngine.didFail {
            playbackEngine.stop()
            emit(
                event: "status",
                state: "error",
                uptime: Date().timeIntervalSince(startedAt),
                message: "Output pass-through stopped after AudioQueue enqueue failed",
                outputDevice: activeOutputDevice,
                playbackActive: false
            )
            return 65
        }

        if !stopFlag.isRequested {
            emit(
                event: "heartbeat",
                state: "running",
                uptime: Date().timeIntervalSince(startedAt),
                outputDevice: activeOutputDevice,
                playbackActive: playbackEngine != nil
            )
        }
    }

    playbackEngine?.stop()
    emit(
        event: "status",
        state: "stopping",
        uptime: Date().timeIntervalSince(startedAt),
        message: "Stop requested",
        outputDevice: activeOutputDevice,
        playbackActive: false
    )
    return 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
let outputDeviceUID: String?
if let outputDeviceIndex = arguments.firstIndex(of: "--output-device-uid") {
    let nextIndex = arguments.index(after: outputDeviceIndex)
    guard nextIndex < arguments.endIndex, !arguments[nextIndex].hasPrefix("--") else {
        emit(event: "status", state: "error", message: "Missing value for --output-device-uid")
        exit(64)
    }
    outputDeviceUID = arguments[nextIndex]
} else {
    outputDeviceUID = ProcessInfo.processInfo.environment["VOLDECK_OUTPUT_DEVICE_UID"]
}

if arguments.contains("--health-check") {
    emit(event: "health", state: "ok", message: "VolDeck output helper is available")
    exit(0)
}

if arguments.contains("--list-output-devices") {
    exit(emitOutputDeviceList())
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
    exit(runHelper(playThrough: arguments.contains("--play-through"), outputDeviceUID: outputDeviceUID))
}

emit(event: "status", state: "error", message: "Unsupported arguments: \(arguments.joined(separator: " "))")
exit(64)
