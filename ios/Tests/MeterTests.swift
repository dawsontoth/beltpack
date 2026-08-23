import Foundation
import Testing

@testable import Beltpack

/// What the meters are allowed to claim.
///
/// These are written against normalised RMS — the value after dividing by full
/// scale — because that division is where the meter went wrong in practice.
@Suite("Meter")
struct MeterTests {
    /// The regression that prompted all of this: every microphone muted, and
    /// the "you hear" meter still wandering around.
    ///
    /// A muted channel is not zeros, it is a least-significant-bit of dither.
    /// Read at int16 scale that is about -96 dBFS and must show nothing. Read
    /// as though the buffer were float-scaled it is -6 dBFS — a meter most of
    /// the way up, moving, on no audio at all.
    @Test("dither on a muted channel reads as silence")
    func ditherIsSilent() {
        let ditherRMS: Float = 0.5 // half an LSB, in int16 units

        #expect(GainProcessor.meterLevel(ditherRMS / 32768) == 0)

        // The same samples under the old assumption, to keep the size of the
        // mistake on the record rather than in a commit message.
        #expect(GainProcessor.meterLevel(ditherRMS) > 0.85)
    }

    @Test("true silence reads as silence")
    func silenceIsSilent() {
        #expect(GainProcessor.meterLevel(0) == 0)
    }

    /// -60 dBFS is the bottom of the scale, so anything quieter pins at zero
    /// rather than going negative.
    @Test("below the floor pins at zero")
    func belowFloorPins() {
        #expect(GainProcessor.meterLevel(0.0001) == 0)
        #expect(GainProcessor.meterLevel(0.00001) == 0)
    }

    @Test("speech lands in the middle of the scale")
    func speechIsMidScale() {
        // -20 dBFS: an ordinary talking level.
        let level = GainProcessor.meterLevel(0.1)
        #expect(level > 0.6)
        #expect(level < 0.72)
    }

    @Test("full scale is the top, and nothing exceeds it")
    func fullScaleIsTheTop() {
        #expect(GainProcessor.meterLevel(1) == 1)
        // Inter-sample peaks can exceed 0 dBFS; the meter must not run off.
        #expect(GainProcessor.meterLevel(4) == 1)
    }
}
