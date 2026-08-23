import Foundation
import LiveKit

/// Live signal levels for the meters.
///
/// Updated from the audio processing hooks, which run on a realtime thread, so
/// values are stashed without locking and republished on the main actor at a
/// rate a person can actually read.
@MainActor
final class AudioLevels: ObservableObject {
    @Published private(set) var mic: Float = 0
    @Published private(set) var listen: Float = 0

    private let raw = LevelStore()
    private var ticker: Task<Void, Never>?

    init() {
        // 20 Hz: fast enough to look live, slow enough not to thrash SwiftUI.
        // A Task rather than a Timer, so teardown does not have to reach a
        // non-Sendable object from a nonisolated deinit.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                await self.sample()
            }
        }
    }

    func stop() { ticker?.cancel() }

    nonisolated var store: LevelStore { raw }

    private func sample() {
        // Fast attack, slow release — a meter that drops instantly is unreadable.
        mic = smooth(mic, towards: raw.takeMic())
        listen = smooth(listen, towards: raw.takeListen())
    }

    private func smooth(_ current: Float, towards target: Float) -> Float {
        target > current ? target : current * 0.75 + target * 0.25
    }
}

/// Plain shared storage between the realtime audio threads and the UI. Only
/// ever holds the loudest value seen since the last read, so a brief peak is
/// never missed between samples.
final class LevelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var micPeak: Float = 0
    private var listenPeak: Float = 0

    func reportMic(_ value: Float) {
        lock.lock(); micPeak = max(micPeak, value); lock.unlock()
    }

    func reportListen(_ value: Float) {
        lock.lock(); listenPeak = max(listenPeak, value); lock.unlock()
    }

    func takeMic() -> Float {
        lock.lock(); defer { micPeak = 0; lock.unlock() }; return micPeak
    }

    func takeListen() -> Float {
        lock.lock(); defer { listenPeak = 0; lock.unlock() }; return listenPeak
    }
}
