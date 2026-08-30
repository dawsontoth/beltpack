import Foundation

/// The one place that knows what a sample means and how to draw it.
///
/// Shared by the phone's meters and the console feed's, because a level that
/// reads differently in two places is worse than no level at all.
public enum AudioMeter {
    /// WebRTC's processing buffers are float but carry int16-range values —
    /// ±32768, not ±1.
    ///
    /// This used to be inferred from the signal, and inferring it is what made
    /// a meter wander with every microphone muted: silence is a
    /// least-significant-bit of dither, and a buffer whose peak is 1 cannot be
    /// told from full-scale float audio by peak alone. Guessing "float" there
    /// draws the noise floor 90 dB too high.
    public static let fullScale: Float = 32768

    /// Maps RMS onto a meter scale in decibels rather than linearly.
    ///
    /// A linear meter reads nearly full on ordinary speech and tells you
    /// nothing; -60 dBFS to 0 is the range a person can judge a level against.
    public static func level(rms: Float) -> Float {
        guard rms > 0.00001 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 60) / 60, 0), 1)
    }

    /// Gain is set in decibels because that is how consoles are set, and stored
    /// as a multiplier because that is what a sample gets multiplied by.
    public static func gain(decibels: Double) -> Float {
        Float(pow(10, decibels / 20))
    }

    public static func decibels(gain: Float) -> Double {
        guard gain > 0 else { return -.infinity }
        return 20 * log10(Double(gain))
    }
}
