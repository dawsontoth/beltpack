#if os(macOS)

import Foundation
import OSLog

/// The management control plane.
///
/// Audio capture has to happen in this process — no browser can open a Core
/// Audio device — but everything around it is just state an operator wants to
/// see and change. Exposing that over HTTP means the booth Mac can be driven
/// from a phone at the back of the room instead of from its own keyboard.
public final class ControlServer: @unchecked Sendable {
    private let controller: BridgeController
    private let passcode: String
    private let server: HTTPServer
    private let log = Logger(subsystem: "org.beltpack", category: "control")

    public init(port: UInt16, passcode: String, controller: BridgeController) {
        self.controller = controller
        self.passcode = passcode

        server = HTTPServer(port: port)
        server.onRequest = { [weak self] request in
            guard let self else { return .notFound }
            return await self.handle(request)
        }
    }

    public func start() throws { try server.start() }
    public func stop() { server.stop() }

    // MARK: - Routing

    private func handle(_ request: HTTPServer.Request) async -> HTTPServer.Response {
        // The page itself is not secret; every call that reads state or changes
        // anything is. A volunteer stumbling onto the URL sees a passcode
        // prompt and nothing else.
        if request.path == "/" || request.path == "/admin" {
            return .text(AdminPage.html, type: "text/html; charset=utf-8")
        }

        guard authorised(request) else {
            return .json(["error": "unauthorised"], status: 401)
        }

        switch (request.method, request.path) {
        case ("GET", "/admin/status"):
            return await .json(status())
        case ("POST", "/admin/start"):
            await controller.start()
            return await .json(status())
        case ("POST", "/admin/stop"):
            await controller.stop()
            return await .json(status())
        case ("POST", "/admin/devices"):
            return await selectDevices(request)
        case ("GET", "/admin/pair"):
            return await pairing()
        default:
            return .notFound
        }
    }

    /// Constant-time, so the passcode cannot be recovered by timing.
    private func authorised(_ request: HTTPServer.Request) -> Bool {
        guard let supplied = request.header("x-beltpack-admin") else { return false }
        let a = Array(supplied.utf8), b = Array(passcode.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    // MARK: - Payloads

    private struct DeviceDTO: Encodable {
        let uid: String
        let name: String
        let channels: Int
        let selected: Bool
    }

    private struct ParticipantDTO: Encodable {
        let id: String
        let name: String
        let isMuted: Bool
        let isSpeaking: Bool
        let publishesAudio: Bool
        let isBridge: Bool
    }

    private struct StatusDTO: Encodable {
        let state: String
        let message: String?
        let room: String?
        let url: String?
        let micStatus: String
        let canPair: Bool
        let inputs: [DeviceDTO]
        let outputs: [DeviceDTO]
        let participants: [ParticipantDTO]
    }

    private struct PairingDTO: Encodable {
        let appURL: String?
        let webURL: String?
        let appSVG: String?
        let webSVG: String?
    }

    private struct DeviceSelection: Decodable {
        let input: String?
        let output: String?
    }

    @MainActor
    private func status() -> StatusDTO {
        let state: String
        var message: String?
        switch controller.runState {
        case .stopped: state = "stopped"
        case .starting: state = "starting"
        case .running: state = "running"
        case .reconnecting: state = "reconnecting"
        case let .failed(reason):
            state = "failed"
            message = reason
        }

        func map(_ devices: [AudioInput], selected: AudioInput?) -> [DeviceDTO] {
            devices.map {
                DeviceDTO(uid: $0.uid, name: $0.name, channels: $0.channels, selected: $0.uid == selected?.uid)
            }
        }

        return StatusDTO(
            state: state,
            message: message,
            room: controller.config?.room,
            url: controller.config?.livekitURL,
            micStatus: controller.micStatus,
            canPair: controller.config?.clientURL != nil && controller.config?.passcode != nil,
            inputs: map(controller.inputs, selected: controller.selectedInput),
            outputs: map(controller.outputs, selected: controller.selectedOutput),
            participants: controller.participants.map {
                ParticipantDTO(
                    id: $0.id, name: $0.name, isMuted: $0.isMuted,
                    isSpeaking: $0.isSpeaking, publishesAudio: $0.publishesAudio, isBridge: $0.isBridge,
                )
            },
        )
    }

    private func selectDevices(_ request: HTTPServer.Request) async -> HTTPServer.Response {
        guard let selection = request.json(DeviceSelection.self) else {
            return .json(["error": "expected {input?, output?} by device uid"], status: 400)
        }

        return await MainActor.run {
            if let uid = selection.input, let device = controller.inputs.first(where: { $0.uid == uid }) {
                controller.selectedInput = device
                log.notice("input re-patched to \(device.name, privacy: .public)")
            }
            if let uid = selection.output, let device = controller.outputs.first(where: { $0.uid == uid }) {
                controller.selectedOutput = device
                log.notice("output re-patched to \(device.name, privacy: .public)")
            }
            return HTTPServer.Response.json(status())
        }
    }

    private func pairing() async -> HTTPServer.Response {
        let link: PairingLink? = await MainActor.run {
            guard let config = controller.config,
                  let server = config.clientURL,
                  let passcode = config.passcode
            else { return nil }
            return PairingLink(server: server, passcode: passcode)
        }

        guard let link else {
            return .json(["error": "set BELTPACK_CLIENT_URL and BELTPACK_PASSCODE to pair"], status: 400)
        }

        return .json(PairingDTO(
            appURL: link.appURL?.absoluteString,
            webURL: link.webURL?.absoluteString,
            appSVG: link.appURL.flatMap { QRCode.svg(for: $0.absoluteString) },
            webSVG: link.webURL.flatMap { QRCode.svg(for: $0.absoluteString) },
        ))
    }
}

#endif
