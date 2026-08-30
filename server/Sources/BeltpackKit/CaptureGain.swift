#if os(macOS)
import Foundation
import LiveKit

/// Trims the console feed on its way in, and measures it.
///
/// A feed that arrives soft is worth fixing here rather than on every phone.
/// This runs before Opus, so it amplifies the signal; a phone turning itself up
/// afterwards amplifies what the encoder made of a quiet signal along with it.
/// It is also one control instead of one per volunteer.
public final class CaptureGain: NSObject, AudioCustomProcessingDelegate, @unchecked Sendable {
    // Touched from the audio thread on every buffer and from the main actor
    // whenever the control panel moves the slider.
    private let lock = NSLock()
    private var _gain: Float
    private var _level: Float = 0

    public init(gain: Float = 1) {
        _gain = gain
    }

    public var gain: Float {
        get { lock.lock(); defer { lock.unlock() }; return _gain }
        set { lock.lock(); _gain = newValue; lock.unlock() }
    }

    /// 0…1 on a dBFS scale, for a meter.
    ///
    /// A decaying peak rather than the last buffer's level: buffers arrive
    /// every 10 ms and the panel reads this a few times a second, so a plain
    /// instantaneous value would show whichever moment the poll happened to
    /// land on and miss the peaks entirely — which is the opposite of what a
    /// meter is for when you are setting a trim.
    public var level: Float {
        lock.lock(); defer { lock.unlock() }; return _level
    }

    /// Per buffer, so about 1.5 seconds from full scale to nothing. Fast
    /// enough to follow speech, slow enough to be seen.
    private static let decay: Float = 0.985

    public var audioProcessingName: String { "beltpack.console" }

    public func audioProcessingInitialize(sampleRate _: Int, channels _: Int) {}
    public func audioProcessingRelease() {}

    public func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        let gain = self.gain
        var sumOfSquares: Float = 0
        var counted = 0

        for channel in 0 ..< audioBuffer.channels {
            let samples = audioBuffer.rawBuffer(forChannel: channel)
            for index in 0 ..< audioBuffer.frames {
                let value = samples[index] * gain
                samples[index] = value
                sumOfSquares += value * value
            }
            counted += audioBuffer.frames
        }

        guard counted > 0 else { return }
        let rms = (sumOfSquares / Float(counted)).squareRoot() / AudioMeter.fullScale
        let level = AudioMeter.level(rms: rms)
        lock.lock()
        _level = max(level, _level * Self.decay)
        lock.unlock()
    }
}
#endif
