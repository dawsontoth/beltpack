import AVFAudio
import Foundation
import OSLog

/// Synthesises speech and feeds it into the outgoing microphone track.
///
/// The awkward part: WebRTC captures from the device microphone, not from an
/// arbitrary buffer, so there is no "publish this audio" call to reach for.
/// What there is, is the capture post-processing hook — the same one the gain
/// trim uses. While an announcement is playing, its samples are written over
/// the microphone's, so the announcement goes out on the track that already
/// exists rather than needing a second one.
///
/// Speech is rendered to buffers up front rather than spoken aloud, so nothing
/// comes out of the phone's own speaker and back into its microphone.
final class SpeechInjector: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "org.beltpack", category: "speech")

    private let lock = NSLock()
    private var pending: [Float] = []
    private var cursor = 0
    private var targetSampleRate: Double = 48000

    /// True while there is audio left to send.
    var isSpeaking: Bool {
        lock.lock(); defer { lock.unlock() }
        return cursor < pending.count
    }

    func setOutputSampleRate(_ rate: Double) {
        lock.lock(); targetSampleRate = rate; lock.unlock()
    }

    /// Renders `text` and queues it. Replaces anything already queued: a second
    /// announcement means the first is no longer what somebody wants said.
    func speak(_ text: String, voice: AVSpeechSynthesisVoice? = nil) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        // Slightly quicker than default: this is a cue, not a reading.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05

        let samples = await render(utterance, to: currentSampleRate())
        enqueue(samples)

        log.notice("queued \(samples.count) samples for \"\(text, privacy: .public)\"")
    }

    /// Both wrapped in synchronous helpers: NSLock cannot be taken across an
    /// await, and taking it inside one is a compile error rather than a
    /// runtime surprise.
    private func currentSampleRate() -> Double {
        lock.lock(); defer { lock.unlock() }
        return targetSampleRate
    }

    private func enqueue(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        pending = samples
        cursor = 0
    }

    func stop() {
        lock.lock()
        pending = []
        cursor = 0
        lock.unlock()
    }

    /// Fills `frames` of `channel` with queued speech. Returns how many frames
    /// were written, so the caller can silence the rest of the microphone
    /// buffer rather than letting room noise bleed under the announcement.
    func drain(into samples: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard cursor < pending.count else { return 0 }

        let available = min(frames, pending.count - cursor)
        for index in 0 ..< available {
            samples[index] = pending[cursor + index]
        }
        cursor += available
        if cursor >= pending.count {
            pending = []
            cursor = 0
        }
        return available
    }

    // MARK: - Rendering

    private func render(_ utterance: AVSpeechUtterance, to sampleRate: Double) async -> [Float] {
        await withCheckedContinuation { continuation in
            var collected: [Float] = []
            var converter: AVAudioConverter?
            var finished = false

            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                // A zero-length buffer is how AVSpeechSynthesizer says it is done.
                guard pcm.frameLength > 0 else {
                    guard !finished else { return }
                    finished = true
                    continuation.resume(returning: collected)
                    return
                }

                // The synthesiser picks its own rate and format; WebRTC wants
                // ours. Converting here keeps the realtime path free of it.
                guard let output = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sampleRate,
                    channels: 1,
                    interleaved: false,
                ) else { return }

                if converter == nil {
                    converter = AVAudioConverter(from: pcm.format, to: output)
                }
                guard let converter else { return }

                let ratio = sampleRate / pcm.format.sampleRate
                let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1024
                guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }

                var supplied = false
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, status in
                    if supplied {
                        status.pointee = .noDataNow
                        return nil
                    }
                    supplied = true
                    status.pointee = .haveData
                    return pcm
                }

                if let channel = converted.floatChannelData?[0] {
                    collected.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
                }
            }
        }
    }
}
