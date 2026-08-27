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
        guard let total = defaultOutputChannelCount() else {
            log.error("could not read the output device's channel count")
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

    private func defaultOutputChannelCount() -> Int? {
        guard let id = AudioDevices.currentDefaultOutput() else { return nil }
        return AudioDevices.list(.output).first { $0.id == id }?.channels
    }
}
#endif
