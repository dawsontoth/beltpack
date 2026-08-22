import CoreAudio
import Foundation

/// Core Audio device enumeration and selection.
///
/// This deliberately does not use LiveKit's `AudioManager.inputDevices`. On
/// macOS that returns a single nameless placeholder regardless of what is
/// actually attached, which makes it useless both for showing an operator
/// their options and for picking one. Core Audio answers directly.
///
/// Selection works by setting the *system default input device*, because the
/// WebRTC audio device module captures the default. On a dedicated booth Mac
/// that is the right trade; the bridge logs the change so it is never a
/// surprise.
struct AudioInput: Sendable, Equatable {
    let id: AudioObjectID
    let name: String
    let uid: String
    let channels: Int
}

enum AudioDevices {
    // MARK: - Enumeration

    static func list() -> [AudioInput] {
        allDeviceIDs().compactMap { id in
            let channels = inputChannelCount(id)
            guard channels > 0 else { return nil }
            return AudioInput(
                id: id,
                name: stringProperty(id, kAudioObjectPropertyName) ?? "(unnamed)",
                uid: stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "",
                channels: channels,
            )
        }
    }

    // MARK: - Selection

    /// Case-insensitive substring match against the device name, so "wing"
    /// finds "WING 48ch". Matching more than one device is an error rather
    /// than a coin flip — on a console feed, capturing the wrong thing is
    /// worse than refusing to start.
    static func select(matching hint: String) throws -> AudioInput {
        let devices = list()
        let needle = hint.lowercased()
        let matches = devices.filter { $0.name.lowercased().contains(needle) }

        switch matches.count {
        case 0: throw AudioDeviceError.notFound(hint: hint, available: devices)
        case 1: break
        default: throw AudioDeviceError.ambiguous(hint: hint, matches: matches)
        }

        let device = matches[0]
        try setDefaultInput(device)
        return device
    }

    static func currentDefaultInput() -> AudioObjectID? {
        var addr = defaultInputAddress
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else {
            return nil
        }
        return id
    }

    static func setDefaultInput(_ device: AudioInput) throws {
        var addr = defaultInputAddress
        var id = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &id,
        )
        guard status == noErr else {
            throw AudioDeviceError.couldNotSelect(name: device.name, status: status)
        }
    }

    // MARK: - Core Audio plumbing

    // Computed, not stored: Core Audio wants an inout pointer, and a stored
    // static var is global mutable state under Swift 6 concurrency.
    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func inputChannelCount(_ id: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain,
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment,
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

enum AudioDeviceError: LocalizedError {
    case notFound(hint: String, available: [AudioInput])
    case ambiguous(hint: String, matches: [AudioInput])
    case couldNotSelect(name: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .notFound(hint, available):
            let list = available.isEmpty
                ? "  (none — is the WING powered on, and the USB cable in a direct port rather than a hub?)"
                : available.map { "  - \($0.name)  (\($0.channels) in)" }.joined(separator: "\n")
            return """
            No input device matching "\(hint)".
            Available inputs:
            \(list)
            """
        case let .ambiguous(hint, matches):
            let list = matches.map { "  - \($0.name)" }.joined(separator: "\n")
            return """
            "\(hint)" matches more than one device:
            \(list)
            Make BELTPACK_INPUT_DEVICE more specific.
            """
        case let .couldNotSelect(name, status):
            return "Could not make \"\(name)\" the default input (Core Audio status \(status))."
        }
    }
}
