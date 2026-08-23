import Foundation
import LiveKit

/// Applies a personal gain trim and measures the level.
///
/// Installed as WebRTC's capture *post*-processing hook, which is the right
/// place for a user trim: it runs after echo cancellation and noise
/// suppression, so turning yourself up does not also turn up what those were
/// trying to remove.
final class GainProcessor: NSObject, AudioCustomProcessingDelegate, @unchecked Sendable {
    enum Path { case capture, render }

    private let path: Path
    private let store: LevelStore
    private let lock = NSLock()
    private var _gain: Float

    /// Only set on the capture path. While it has audio queued, its samples
    /// replace the microphone's entirely.
    var speech: SpeechInjector?

    /// What full scale means in these buffers, used both for metering and for
    /// writing speech in at the right level. WebRTC's processing buffers are
    /// float but carry int16-range values — ±32768, not ±1.
    ///
    /// This used to be inferred from the signal, and inferring it is what
    /// produced a meter that wandered with every microphone muted. Silence is
    /// not silent: it is a least-significant-bit of dither. A buffer whose peak
    /// is 1 is indistinguishable by peak alone from full-scale float audio, so
    /// the guess concluded "float", divided by 1 instead of 32768, and painted
    /// the noise floor 90 dB too high. It latched, so it stayed wrong for the
    /// rest of the session and tracked nothing.
    ///
    /// No float-scaled path was ever actually observed. Every symptom that
    /// motivated the guess — speech written at ±1 coming out inaudible, a meter
    /// pegged red — was an int16 buffer being read as float. So this is a
    /// constant. If a float path does turn up, the meter reads low, which is
    /// obvious and harmless, rather than reading high on nothing.
    private static let fullScale: Float = 32768

    init(path: Path, store: LevelStore, gain: Float = 1) {
        self.path = path
        self.store = store
        _gain = gain
    }

    var gain: Float {
        get { lock.lock(); defer { lock.unlock() }; return _gain }
        set { lock.lock(); _gain = newValue; lock.unlock() }
    }

    var audioProcessingName: String { path == .capture ? "beltpack.mic" : "beltpack.listen" }

    func audioProcessingInitialize(sampleRate: Int, channels _: Int) {
        // The synthesiser has to render at whatever rate WebRTC is running,
        // and that is only known once processing starts.
        speech?.setOutputSampleRate(Double(sampleRate))
    }
    func audioProcessingRelease() {}

    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        let gain = self.gain
        var sumOfSquares: Float = 0
        var counted = 0

        // An announcement takes over the buffer rather than mixing with it.
        // Mixing would put room noise and whoever is nearby underneath a cue
        // that is meant to be unambiguous.
        let speaking = speech?.isSpeaking == true

        for channel in 0 ..< audioBuffer.channels {
            let samples = audioBuffer.rawBuffer(for: channel)

            if speaking, let speech {
                let written = speech.drain(into: samples, frames: audioBuffer.frames)
                // The synthesiser produces ±1; the buffer expects int16
                // range. Without this the announcement is technically present
                // and entirely inaudible.
                for index in 0 ..< written { samples[index] *= Self.fullScale }
                // Silence whatever the microphone had in the rest of the
                // buffer, so the tail of an announcement is not room tone.
                for index in written ..< audioBuffer.frames { samples[index] = 0 }
            }

            for index in 0 ..< audioBuffer.frames {
                let value = speaking ? samples[index] : samples[index] * gain
                if !speaking { samples[index] = value }
                sumOfSquares += value * value
            }
            counted += audioBuffer.frames
        }

        let rms = counted > 0 ? (sumOfSquares / Float(counted)).squareRoot() / Self.fullScale : 0

        switch path {
        case .capture: store.reportMic(Self.meterLevel(rms))
        case .render: store.reportListen(Self.meterLevel(rms))
        }
    }

    /// Maps RMS onto a meter scale in decibels rather than linearly.
    ///
    /// A linear peak meter reads nearly full on ordinary speech and tells you
    /// nothing; -60 dBFS to 0 is the range a person can actually judge a level
    /// against.
    static func meterLevel(_ rms: Float) -> Float {
        guard rms > 0.00001 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
