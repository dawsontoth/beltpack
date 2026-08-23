import Foundation
import SwiftUI

/// The announcement buttons, as something SwiftUI can watch.
///
/// They were read straight from UserDefaults, which persists fine but is not
/// observable: editing the list in Settings updated the store and left the
/// row on the main screen showing the old buttons until the app restarted.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [String]

    init() {
        presets = Settings.presets
    }

    func replace(with newValue: [String]) {
        Settings.presets = newValue
        // Read back rather than trusting the input: Settings trims and drops
        // empties, so the two would otherwise disagree about what was saved.
        presets = Settings.presets
    }

    func restoreDefaults() {
        Settings.resetPresets()
        presets = Settings.presets
    }
}
