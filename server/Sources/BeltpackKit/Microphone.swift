import AVFoundation
import Foundation

/// macOS microphone authorization.
///
/// Capturing the WING counts as microphone access under TCC. The catch that
/// costs an afternoon: *enumerating* devices never triggers the permission
/// prompt — it just silently returns devices with their names redacted. Only
/// an explicit request, or a real capture attempt, prompts. So the bridge asks
/// for permission up front rather than waiting to be told no.
public enum Microphone {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static var statusDescription: String {
        switch status {
        case .authorized: "granted"
        case .notDetermined: "not yet requested"
        case .denied: "denied"
        case .restricted: "restricted by policy"
        @unknown default: "unknown"
        }
    }

    /// Returns true when capture can proceed. Prints actionable guidance and
    /// returns false when it cannot.
    public static func ensureAccess() async -> Bool {
        switch status {
        case .authorized:
            return true

        case .notDetermined:
            FileHandle.standardError.write(Data("beltpack-bridge: requesting microphone access…\n".utf8))
            let granted = await requestAccess()
            if !granted {
                printDeniedGuidance()
            }
            return granted

        case .denied, .restricted:
            printDeniedGuidance()
            return false

        @unknown default:
            return false
        }
    }

    private static func printDeniedGuidance() {
        #if os(iOS)
        // On iOS the app has its own identity and Settings entry; there is no
        // terminal to blame.
        FileHandle.standardError.write(Data("Microphone access is \(statusDescription).\n".utf8))
        #else
        // A command-line tool has no bundle identity of its own, so macOS
        // attributes the request to whatever launched it. Grant it there.
        let terminal = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "your terminal"
        FileHandle.standardError.write(Data("""

        Microphone access is \(statusDescription).

        This is a command-line tool, so macOS attributes the request to the app
        that launched it — here, \(terminal). Enable it in:

          System Settings > Privacy & Security > Microphone

        then run this again. If the prompt never appeared at all, run it from
        Terminal.app directly rather than from an editor or an agent.

        """.utf8))
        #endif
    }
}
