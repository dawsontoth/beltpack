import SwiftUI

@main
struct BeltpackWatchApp: App {
    @StateObject private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchTalkView()
                .environmentObject(link)
        }
    }
}
