#if os(macOS)
import AVFoundation
import AudioToolbox
import LiveKit
import OSLog

/// Picks which channel of a multichannel interface carries comms.
///
/// A WING puts 48 inputs and 48 outputs down one USB cable. WebRTC has no
/// notion of a channel: it captures "the default input device" and renders to
/// "the default output device", which in practice means the first channels —
/// and on a console those are usually already spoken for by something else.
///
/// LiveKit runs its audio through an AVAudioEngine and lets an observer see
/// that engine before anything is connected to it. The HAL audio units under
/// the engine's input and output nodes each accept a channel map, which is the
/// supported way to say "channel 42 is the one I mean". Nothing else in the
/// graph has to change, so this stays out of the way of the SDK's own observer.
public final class ChannelSelection: AudioEngineObserver, @unchecked Sendable {
    public var next: (any AudioEngineObserver)?

    /// 1-based, matching what the console prints on its own screen. Nil leaves
    /// the channel alone, which is the old behaviour exactly.
    private let inputChannel: Int?
    private let outputChannel: Int?
    private let log = Logger(subsystem: "org.beltpack", category: "channels")

    public init(inputChannel: Int? = nil, outputChannel: Int? = nil) {
        self.inputChannel = inputChannel
        self.outputChannel = outputChannel
    }

    public var isActive: Bool { inputChannel != nil || outputChannel != nil }

    public func engineDidCreate(_ engine: AVAudioEngine) -> Int {
        // Before the engine connects anything: a channel map changes how many
        // channels the unit reports, and the connection formats are derived
        // from that.
        applyInput(engine)
        applyOutput(engine)
        return next?.engineDidCreate(engine) ?? 0
    }

    // MARK: - Input

    private func applyInput(_ engine: AVAudioEngine) {
        guard let channel = inputChannel else { return }
        guard let unit = engine.inputNode.audioUnit else {
            log.error("no input audio unit — cannot select channel \(channel, privacy: .public)")
            return
        }

        // Asking for a channel the device does not have is not a refusal from
        // Core Audio: the property is accepted, the node's format becomes
        // something the engine cannot connect, and AVAudioEngine throws an
        // NSException from inside LiveKit's own observer. That is not catchable
        // from Swift, so the app dies — and with the agent restarting it, dies
        // over and over with only a flicker in the menu bar to show for it.
        //
        // The console is powered down between services, so a missing device is
        // an ordinary state here rather than a fault. Leave the channel alone
        // and let the default path run: comms on the wrong channel is worth
        // saying out loud, but it is not worth taking the Mac down for.
        guard let total = channelCount(.input), total > 0 else {
            log.error("no input device to select channel \(channel, privacy: .public) on — is the console powered on?")
            return
        }
        guard channel <= total else {
            log.error("input channel \(channel, privacy: .public) but the device has only \(total, privacy: .public)")
            return
        }

        // Output scope, element 1: one entry per channel coming out of the
        // unit, each holding the device channel that feeds it. One entry, so
        // comms is mono — which is what a headset ring is.
        var map: [Int32] = [Int32(channel - 1)]
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            1,
            &map,
            UInt32(MemoryLayout<Int32>.size * map.count),
        )

        if status == noErr {
            log.notice("capturing device input channel \(channel, privacy: .public)")
        } else {
            log.error("could not select input channel \(channel, privacy: .public): OSStatus \(status, privacy: .public)")
        }
    }

    // MARK: - Output

    private func applyOutput(_ engine: AVAudioEngine) {
        guard let channel = outputChannel else { return }
        guard let unit = engine.outputNode.audioUnit else {
            log.error("no output audio unit — cannot select channel \(channel, privacy: .public)")
            return
        }
        guard let total = channelCount(.output), total > 0 else {
            log.error("no output device to select channel \(channel, privacy: .public) on")
            return
        }
        guard channel <= total else {
            log.error("output channel \(channel, privacy: .public) but the device has only \(total, privacy: .public)")
            return
        }

        // Input scope, element 0: one entry per *device* channel, holding which
        // of our channels feeds it. -1 is silence, so every other channel on the
        // console is left untouched rather than being written over with quiet.
        var map = [Int32](repeating: -1, count: total)
        map[channel - 1] = 0
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Input,
            0,
            &map,
            UInt32(MemoryLayout<Int32>.size * map.count),
        )

        if status == noErr {
            log.notice("returning phone audio on device output channel \(channel, privacy: .public) of \(total, privacy: .public)")
        } else {
            log.error("could not select output channel \(channel, privacy: .public): OSStatus \(status, privacy: .public)")
        }
    }

    /// What the device the engine will actually use has, which is the system
    /// default — not whatever was picked in the UI, since those can differ
    /// while a device is coming or going.
    private func channelCount(_ direction: AudioDirection) -> Int? {
        let id = direction == .input
            ? AudioDevices.currentDefaultInput()
            : AudioDevices.currentDefaultOutput()
        guard let id else { return nil }
        return AudioDevices.list(direction).first { $0.id == id }?.channels
    }
}
#endif
