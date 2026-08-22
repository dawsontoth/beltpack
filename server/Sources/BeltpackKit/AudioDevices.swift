#if os(macOS)

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
public struct AudioInput: Sendable, Equatable, Identifiable, Hashable {
    public let id: AudioObjectID
    public let name: String
    public let uid: String
    public let channels: Int
}

public enum AudioDirection: Sendable {
    case input
    case output

    var scope: AudioObjectPropertyScope {
        switch self {
        case .input: kAudioObjectPropertyScopeInput
        case .output: kAudioObjectPropertyScopeOutput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input: kAudioHardwarePropertyDefaultInputDevice
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        }
    }

    public var label: String {
        switch self {
        case .input: "input"
        case .output: "output"
        }
    }
}

public enum AudioDevices {
    // MARK: - Enumeration

    public static func list(_ direction: AudioDirection = .input) -> [AudioInput] {
        allDeviceIDs().compactMap { id in
            let channels = channelCount(id, direction)
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
    public static func select(matching hint: String, direction: AudioDirection = .input) throws -> AudioInput {
        let devices = list(direction)
        let needle = hint.lowercased()
        let matches = devices.filter { $0.name.lowercased().contains(needle) }

        switch matches.count {
        case 0: throw AudioDeviceError.notFound(hint: hint, available: devices)
        case 1: break
        default: throw AudioDeviceError.ambiguous(hint: hint, matches: matches)
        }

        let device = matches[0]
        try setDefault(device, direction: direction)
        return device
    }

    public static func currentDefaultOutput() -> AudioObjectID? {
        currentDefault(.output)
    }

    public static func currentDefaultInput() -> AudioObjectID? {
        currentDefault(.input)
    }

    private static func currentDefault(_ direction: AudioDirection) -> AudioObjectID? {
        var addr = defaultDeviceAddress(direction)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else {
            return nil
        }
        return id
    }

    public static func setDefault(_ device: AudioInput, direction: AudioDirection = .input) throws {
        var addr = defaultDeviceAddress(direction)
        var id = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &id,
        )
        guard status == noErr else {
            throw AudioDeviceError.couldNotSelect(name: device.name, direction: direction, status: status)
        }
    }

    // MARK: - Core Audio plumbing

    // Computed, not stored: Core Audio wants an inout pointer, and a stored
    // static var is global mutable state under Swift 6 concurrency.
    private static func defaultDeviceAddress(_ direction: AudioDirection) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
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

    private static func channelCount(_ id: AudioObjectID, _ direction: AudioDirection) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: direction.scope,
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

public enum AudioDeviceError: LocalizedError {
    case notFound(hint: String, available: [AudioInput])
    case ambiguous(hint: String, matches: [AudioInput])
    case couldNotSelect(name: String, direction: AudioDirection, status: OSStatus)

    public var errorDescription: String? {
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
        case let .couldNotSelect(name, direction, status):
            return "Could not make \"\(name)\" the default \(direction.label) (Core Audio status \(status))."
        }
    }
}

#endif
