import LiveKit
import SwiftUI

@main
struct BeltpackApp: App {
    @StateObject private var comms = CommsClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(comms)
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
