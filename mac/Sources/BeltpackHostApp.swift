import BeltpackKit
import SwiftUI

@main
struct BeltpackHostApp: App {
    @StateObject private var model = HostModel()

    var body: some Scene {
        Window("Beltpack Host", id: "host") {
            HostView()
                .environmentObject(model)
                .frame(minWidth: 460, minHeight: 560)
                .task {
                    #if DEBUG
                    // Smoke-test hook, mirroring the iOS app's: lets the whole
                    // path be exercised without a human clicking Start.
                    if CommandLine.arguments.contains("-beltpack-autostart") {
                        await model.controller.start()
                    }
                    #endif
                }
        }
        .windowResizability(.contentMinSize)

        // A booth Mac runs this all service; the menu bar is where an
        // operator glances to check it is still up.
        MenuBarExtra("Beltpack", systemImage: model.menuBarSymbol) {
            Text(model.menuBarSummary)
            Divider()
            Button(model.controller.runState.isRunning ? "Stop" : "Start") {
                Task { await model.toggle() }
            }
            .disabled(model.controller.runState.isBusy || model.controller.config == nil)
            Divider()
            Button("Quit Beltpack Host") { NSApplication.shared.terminate(nil) }
        }
    }
}
