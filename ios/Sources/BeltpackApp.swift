import BeltpackKit
import LiveKit
import SwiftUI

@main
struct BeltpackApp: App {
    @StateObject private var comms = CommsClient()
    @StateObject private var presets = PresetStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(comms)
                .environmentObject(presets)
                .onOpenURL { url in
                    // A scanned pairing code. Applied whole or not at all:
                    // PairingLink refuses anything half-configured.
                    guard let link = PairingLink.parse(url) else { return }
                    let ready = Settings.apply(link)
                    // Connect straight away when the code carried everything.
                    // A code without a name leaves the person on the settings
                    // screen with one field to fill rather than four.
                    if ready {
                        Task { await comms.connect() }
                    }
                }
                .task {
                    #if DEBUG
                    // Smoke-test hook: `simctl launch … -beltpack-autoconnect`
                    // joins without a human tapping, so the connect path can be
                    // exercised in a simulator or on CI.
                    if CommandLine.arguments.contains("-beltpack-autoconnect") {
                        await comms.connect()
                    }
                    // Fires an announcement without a human tap, so the
                    // send path can be exercised in a simulator.
                    if let index = CommandLine.arguments.firstIndex(of: "-beltpack-announce"),
                       index + 1 < CommandLine.arguments.count
                    {
                        try? await Task.sleep(for: .seconds(3))
                        await comms.announce(CommandLine.arguments[index + 1])
                    }
                    #endif
                }
        }
    }
}
