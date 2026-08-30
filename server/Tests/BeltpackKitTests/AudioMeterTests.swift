import Foundation
import Testing

@testable import BeltpackKit

/// The maths both the phones and the console feed draw their meters from.
@Suite("AudioMeter")
struct AudioMeterTests {
    /// The regression the phone meters were built around: a muted channel is
    /// not zeros, it is a least-significant-bit of dither. Read at int16 scale
    /// that is about -96 dBFS and must show nothing.
    @Test("dither on a muted channel reads as silence")
    func ditherIsSilent() {
        #expect(AudioMeter.level(rms: 0.5 / AudioMeter.fullScale) == 0)
        #expect(AudioMeter.level(rms: 0) == 0)
    }

    @Test("speech lands mid-scale and full scale is the top")
    func usefulRange() {
        let speech = AudioMeter.level(rms: 0.1) // -20 dBFS
        #expect(speech > 0.6)
        #expect(speech < 0.72)
        #expect(AudioMeter.level(rms: 1) == 1)
        // Inter-sample peaks can exceed 0 dBFS; the meter must not run off.
        #expect(AudioMeter.level(rms: 4) == 1)
    }

    @Test("unity is 0 dB in both directions")
    func unity() {
        #expect(AudioMeter.gain(decibels: 0) == 1)
        #expect(AudioMeter.decibels(gain: 1) == 0)
    }

    @Test("decibels convert to the multiplier a sample is multiplied by")
    func conversions() {
        // +6 dB is a doubling, which is the check anyone would do by hand.
        #expect(abs(AudioMeter.gain(decibels: 6) - 2) < 0.01)
        #expect(abs(AudioMeter.gain(decibels: -6) - 0.5) < 0.01)
        #expect(abs(AudioMeter.gain(decibels: 20) - 10) < 0.01)
    }

    @Test("whole decibels round-trip across the range the panel offers")
    func roundTrips() {
        for decibels in stride(from: -24.0, through: 24.0, by: 1) {
            let gain = AudioMeter.gain(decibels: decibels)
            #expect(abs(AudioMeter.decibels(gain: gain) - decibels) < 0.001)
        }
    }

    /// Silence has no decibel value. Returning something finite would put a
    /// real-looking number on a slider that means "off".
    @Test("silence has no finite decibel value")
    func silenceIsNotFinite() {
        #expect(AudioMeter.decibels(gain: 0) == -.infinity)
    }
}
