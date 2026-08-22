import AppKit
import BeltpackKit
import Combine
import SwiftUI

/// App-level state: where the configuration came from, and a little glue
/// around the shared `BridgeController`.
@MainActor
final class HostModel: ObservableObject {
    @Published private(set) var envPath: String
    @Published private(set) var configError: String?

    let controller = BridgeController()

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
            controller.config = try Config.fromEnvFile(URL(fileURLWithPath: envPath))
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
        case .starting: "ellipsis"
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
        case let .failed(message): return "Failed: \(message)"
        case .stopped: return "Stopped"
        }
    }
}
