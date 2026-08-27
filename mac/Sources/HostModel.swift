import AppKit
import BeltpackKit
import Combine
import OSLog
import SwiftUI

/// App-level state: where the configuration came from, and a little glue
/// around the shared `BridgeController`.
@MainActor
final class HostModel: ObservableObject {
    @Published private(set) var envPath: String
    @Published private(set) var configError: String?

    let controller = BridgeController()
    private var control: ControlServer?
    /// Every reason the control panel might not be up goes here as well as to
    /// configError. configError is only visible behind the menu bar icon, and a
    /// booth Mac is usually not being watched when it comes up — so a browser
    /// that will not connect had no way to explain itself after the fact.
    private let log = Logger(subsystem: "org.beltpack", category: "host")

    private var cancellables: Set<AnyCancellable> = []
    private static let envPathKey = "beltpack.envPath"

    init() {
        envPath = UserDefaults.standard.string(forKey: Self.envPathKey) ?? Self.guessEnvPath() ?? ""
        // Re-publish the controller's changes so views observing the model
        // also update; SwiftUI does not do this transitively.
        controller.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        loadConfig()
        startControlServer()

        // A booth machine is meant to come up on its own after a power cut;
        // waiting for someone to press Start defeats the point.
        if controller.config != nil {
            Task { await controller.start() }
        }
    }

    /// Serves the management page. Without a passcode there is nothing to
    /// gate it with, so it stays off rather than opening unauthenticated
    /// control of the console to the whole VLAN.
    private func startControlServer() {
        guard let config = controller.config else {
            log.error("control panel not started: no config loaded from \(self.envPath, privacy: .public)")
            return
        }
        guard let passcode = config.adminPasscode, passcode.count >= 8 else {
            configError = "Set BELTPACK_ADMIN_PASSCODE (8+ characters) to enable the control panel."
            log.error("control panel not started: BELTPACK_ADMIN_PASSCODE missing or under 8 characters")
            return
        }

        let server = ControlServer(port: config.adminPort, passcode: passcode, controller: controller)
        do {
            try server.start()
            control = server
            log.notice("control panel listening on 127.0.0.1:\(config.adminPort, privacy: .public)")
        } catch {
            configError = "Control panel could not start: \(error.localizedDescription)"
            log.error("control panel failed to bind port \(config.adminPort, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    var adminURL: URL? {
        guard control != nil, let port = controller.config?.adminPort else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    /// Try the obvious places before asking. Most people run this from a
    /// checkout in their home directory.
    private static func guessEnvPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Code/beltpack/.env"),
            home.appendingPathComponent("beltpack/.env"),
            home.appendingPathComponent("Developer/beltpack/.env"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    func chooseEnvFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose your beltpack .env file"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        envPath = url.path
        UserDefaults.standard.set(envPath, forKey: Self.envPathKey)
        loadConfig()
    }

    func loadConfig() {
        guard !envPath.isEmpty else {
            configError = "No .env chosen yet."
            controller.config = nil
            return
        }
        do {
            let url = URL(fileURLWithPath: envPath)
            controller.config = try Config.fromEnvFile(url)
            // So the control panel can write a change back to the same file it
            // was read from, rather than only holding it until the next launch.
            controller.envURL = url
            controller.adoptConfig()
            configError = nil
            preselectFromConfig()
        } catch {
            controller.config = nil
            configError = error.localizedDescription
        }
    }

    /// Honour the hints already in .env so the pickers open on the right
    /// devices rather than making the operator find them again.
    private func preselectFromConfig() {
        guard let config = controller.config else { return }
        if let match = controller.inputs.first(where: {
            $0.name.localizedCaseInsensitiveContains(config.inputDeviceHint)
        }) {
            controller.selectedInput = match
        }
        if let hint = config.outputDeviceHint,
           let match = controller.outputs.first(where: { $0.name.localizedCaseInsensitiveContains(hint) })
        {
            controller.selectedOutput = match
        }
    }

    /// Nil until .env carries both halves; the pairing button hides rather
    /// than offering a code that would not work.
    var pairingLink: PairingLink? {
        guard let config = controller.config,
              let server = config.clientURL,
              let passcode = config.passcode
        else { return nil }
        return PairingLink(server: server, passcode: passcode)
    }

    func toggle() async {
        if controller.runState.isRunning {
            await controller.stop()
        } else {
            await controller.start()
        }
    }

    var menuBarSymbol: String {
        switch controller.runState {
        case .running: "dot.radiowaves.left.and.right"
        case .starting, .reconnecting: "ellipsis"
        case .failed: "exclamationmark.triangle"
        case .stopped: "pause"
        }
    }

    var menuBarSummary: String {
        switch controller.runState {
        case .running:
            let others = controller.participants.filter { !$0.isBridge }.count
            return others == 1 ? "On air, 1 beltpack" : "On air, \(others) beltpacks"
        case .starting: return "Starting…"
        case .reconnecting: return "Reconnecting…"
        case let .failed(message): return "Failed: \(message)"
        case .stopped: return "Stopped"
        }
    }
}
