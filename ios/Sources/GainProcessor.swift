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

    /// WebRTC's processing buffers are float, but carry int16-range values on
    /// most paths rather than ±1. That is the documented convention, so it is
    /// the default rather than something to be discovered — synthesised speech
    /// written in at ±1 into an int16-range buffer comes out 90 dB down, which
    /// is silence with extra steps.
    ///
    /// It is still checked against the signal, because not every path agrees:
    /// a buffer carrying real audio that never exceeds ±1 is float-scaled.
    private var usesInt16Scale = true
    private var scaleObserved = false

    /// What full scale means in this buffer, used both for metering and for
    /// writing speech in at the right level.
    private var fullScale: Float { usesInt16Scale ? 32768 : 1 }

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
        var peak: Float = 0
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
                // The synthesiser produces ±1; the buffer expects whatever
                // this path uses. Without this the announcement is technically
                // present and entirely inaudible.
                let scale = fullScale
                if scale != 1 {
                    for index in 0 ..< written { samples[index] *= scale }
                }
                // Silence whatever the microphone had in the rest of the
                // buffer, so the tail of an announcement is not room tone.
                for index in written ..< audioBuffer.frames { samples[index] = 0 }
            }

            for index in 0 ..< audioBuffer.frames {
                let value = speaking ? samples[index] : samples[index] * gain
                if !speaking { samples[index] = value }
                let magnitude = abs(value)
                peak = max(peak, magnitude)
                sumOfSquares += value * value
            }
            counted += audioBuffer.frames
        }

        // Decide once, and only on a buffer that actually carries signal:
        // silence tells you nothing about scale, and announcements overwrite
        // the buffer so they cannot be used to judge it either.
        if !speaking, !scaleObserved, peak > 0.001 {
            usesInt16Scale = peak > 1
            scaleObserved = true
        }
        let rms = counted > 0 ? (sumOfSquares / Float(counted)).squareRoot() / fullScale : 0

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
    private static func meterLevel(_ rms: Float) -> Float {
        guard rms > 0.00001 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
