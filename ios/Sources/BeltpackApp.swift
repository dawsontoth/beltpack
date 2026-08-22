import LiveKit
import SwiftUI

@main
struct BeltpackApp: App {
    @StateObject private var comms = CommsClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(comms)
        }
    }
}
