import AppKit
import BeltpackKit
import SwiftUI

@main
struct BeltpackHostApp: App {
    @StateObject private var model = HostModel()

    var body: some Scene {
        // No window: everything an operator needs is on the management page,
        // which they can open from a phone at the back of the room rather than
        // from this machine's keyboard. The menu bar is the local surface.
        MenuBarExtra("Beltpack", systemImage: model.menuBarSymbol) {
            Text(model.menuBarSummary)

            if let url = model.adminURL {
                Divider()
                Button("Open control panel…") { NSWorkspace.shared.open(url) }
                Button("Copy control panel address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }

            Divider()
            Button(model.controller.runState.isRunning ? "Stop" : "Start") {
                Task { await model.toggle() }
            }
            .disabled(model.controller.runState.isBusy || model.controller.config == nil)

            Button("Reload configuration") { model.loadConfig() }

            Divider()
            Button("Quit Beltpack Host") { NSApplication.shared.terminate(nil) }
        }
    }
}
