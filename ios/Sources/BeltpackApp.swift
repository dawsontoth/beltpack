import BeltpackKit
import LiveKit
import SwiftUI

@main
struct BeltpackApp: App {
    @StateObject private var comms = CommsClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(comms)
                .onOpenURL { url in
                    // A scanned pairing code. Applied whole or not at all:
                    // PairingLink refuses anything half-configured.
                    guard let link = PairingLink.parse(url) else { return }
                    Settings.serverURL = link.server
                    Settings.passcode = link.passcode
                    if let identity = link.identity, !identity.isEmpty {
                        Settings.identity = identity
                    }
                    Task {
                        if Settings.isConfigured { await comms.connect() }
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
                    #endif
                }
        }
    }
}
