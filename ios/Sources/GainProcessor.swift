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

        // An announcement takes over the buffer rather than mixing with it.
        // Mixing would put room noise and whoever is nearby underneath a cue
        // that is meant to be unambiguous.
        if let speech, speech.isSpeaking {
            for channel in 0 ..< audioBuffer.channels {
                let samples = audioBuffer.rawBuffer(for: channel)
                let written = speech.drain(into: samples, frames: audioBuffer.frames)
                // Silence whatever the microphone had in the rest of the
                // buffer, so the tail of an announcement is not room tone.
                for index in written ..< audioBuffer.frames { samples[index] = 0 }
                for index in 0 ..< audioBuffer.frames {
                    peak = max(peak, abs(samples[index]))
                }
            }
            let scale = peak > 2 ? peak / 32768 : peak
            store.reportMic(min(scale, 1))
            return
        }

        for channel in 0 ..< audioBuffer.channels {
            let samples = audioBuffer.rawBuffer(for: channel)
            for index in 0 ..< audioBuffer.frames {
                let value = samples[index] * gain
                samples[index] = value
                peak = max(peak, abs(value))
            }
        }

        // WebRTC's processing buffers are float but not always normalised to
        // ±1: some paths carry int16-scaled values. Rather than assume, infer
        // the scale from the signal itself so the meter is right either way.
        let normalised = peak > 2 ? peak / 32768 : peak
        let level = min(normalised, 1)

        switch path {
        case .capture: store.reportMic(level)
        case .render: store.reportListen(level)
        }
    }
}
