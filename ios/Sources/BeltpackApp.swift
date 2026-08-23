import BeltpackKit
import LiveKit
import SwiftUI

@main
struct BeltpackApp: App {
    @StateObject private var comms = CommsClient()
    @StateObject private var presets = PresetStore()
    /// Set when a scanned code carried everything except who is holding the
    /// phone, which is every code the host currently produces.
    @State private var needsName = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(comms)
                .environmentObject(presets)
                .onOpenURL(perform: scanned)
                .sheet(isPresented: $needsName) {
                    JoinAsView { name in
                        Settings.identity = name
                        needsName = false
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
                    // Drives the pairing path without a human tapping through
                    // the system's "Open in Beltpack?" prompt, which a script
                    // cannot reach.
                    if let index = CommandLine.arguments.firstIndex(of: "-beltpack-pair"),
                       index + 1 < CommandLine.arguments.count,
                       let url = URL(string: CommandLine.arguments[index + 1])
                    {
                        scanned(url)
                    }
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

    /// A scanned pairing code. Applied whole or not at all: `PairingLink`
    /// refuses anything half-configured.
    private func scanned(_ url: URL) {
        guard let link = PairingLink.parse(url) else { return }
        switch Settings.apply(link) {
        case .ready:
            Task { await comms.connect() }
        case .needsName:
            // Everything landed except who is holding the phone, so ask for
            // that one thing. Scanning used to succeed silently here and left
            // somebody on a screen that would not connect, with nothing saying
            // why.
            needsName = true
        case .unusable:
            // A name would not help, so do not ask for one. The settings
            // screen is where a bad server gets fixed.
            break
        }
    }
}
