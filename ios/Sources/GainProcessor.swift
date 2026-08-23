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

    func audioProcessingInitialize(sampleRate _: Int, channels _: Int) {}
    func audioProcessingRelease() {}

    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        let gain = self.gain
        var peak: Float = 0

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
