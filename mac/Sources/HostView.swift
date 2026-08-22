import BeltpackKit
import SwiftUI

struct HostView: View {
    @EnvironmentObject private var model: HostModel
    @State private var showingPairing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    configSection
                    devicesSection
                    participantsSection
                }
                .padding(20)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StatusLamp(state: model.controller.runState)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if model.pairingLink != nil {
                Button {
                    showingPairing = true
                } label: {
                    Label("Pair", systemImage: "qrcode")
                }
                .help("Show a code for a volunteer to scan")
            }

            Button(model.controller.runState.isRunning ? "Stop" : "Start") {
                Task { await model.toggle() }
            }
            .keyboardShortcut(.return)
            .disabled(model.controller.runState.isBusy || model.controller.config == nil)
        }
        .padding(20)
        .sheet(isPresented: $showingPairing) {
            if let link = model.pairingLink {
                PairingView(link: link)
            }
        }
    }

    private var statusTitle: String {
        switch model.controller.runState {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "On air"
        case .failed: "Failed"
        }
    }

    private var statusDetail: String {
        switch model.controller.runState {
        case let .failed(message): message
        case .running:
            model.controller.config.map { "Publishing to \"\($0.room)\" at \($0.livekitURL)" } ?? ""
        default: model.configError ?? "Ready"
        }
    }

    // MARK: - Config

    private var configSection: some View {
        Section {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(model.envPath.isEmpty ? "No .env chosen" : model.envPath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(model.configError == nil ? Color.primary : Color.red)
                Spacer()
                Button("Choose…") { model.chooseEnvFile() }
                Button("Reload") { model.loadConfig() }
                    .disabled(model.envPath.isEmpty)
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        } header: {
            SectionHeader("Configuration")
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                DevicePicker(
                    label: "Console in",
                    systemImage: "waveform",
                    devices: model.controller.inputs,
                    selection: Binding(
                        get: { model.controller.selectedInput },
                        set: { model.controller.selectedInput = $0 },
                    ),
                    unit: "in",
                )

                DevicePicker(
                    label: "Return out",
                    systemImage: "speaker.wave.2",
                    devices: model.controller.outputs,
                    selection: Binding(
                        get: { model.controller.selectedOutput },
                        set: { model.controller.selectedOutput = $0 },
                    ),
                    unit: "out",
                )

                HStack(spacing: 8) {
                    Label("Microphone access: \(model.controller.micStatus)", systemImage: "mic")
                        .font(.caption)
                        .foregroundStyle(model.controller.micStatus == "granted" ? Color.secondary : Color.red)
                    Spacer()
                    if model.controller.micStatus != "granted" {
                        Button("Grant…") { Task { await model.controller.requestMicrophoneAccess() } }
                            .controlSize(.small)
                    }
                    Button("Refresh") { model.controller.refreshDevices() }
                        .controlSize(.small)
                }
            }
        } header: {
            SectionHeader("Audio devices")
        }
    }

    // MARK: - Participants

    private var participantsSection: some View {
        Section {
            if model.controller.participants.isEmpty {
                Text(model.controller.runState.isRunning
                    ? "No beltpacks connected."
                    : "Start the bridge to see who is on comms.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.controller.participants) { participant in
                        ParticipantRow(participant: participant)
                        if participant.id != model.controller.participants.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        } header: {
            SectionHeader("On comms", count: model.controller.participants.count)
        }
    }
}

// MARK: - Pieces

private struct SectionHeader: View {
    let title: String
    var count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }
}

private struct StatusLamp: View {
    let state: BridgeController.RunState

    var body: some View {
        Circle()
            .fill(color.opacity(0.2))
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color))
            .frame(width: 38, height: 38)
    }

    private var color: Color {
        switch state {
        case .stopped: .secondary
        case .starting: .orange
        case .running: .green
        case .failed: .red
        }
    }

    private var symbol: String {
        switch state {
        case .stopped: "pause.fill"
        case .starting: "ellipsis"
        case .running: "dot.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

private struct DevicePicker: View {
    let label: String
    let systemImage: String
    let devices: [AudioInput]
    @Binding var selection: AudioInput?
    let unit: String

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)

            Picker("", selection: $selection) {
                Text("None").tag(AudioInput?.none)
                ForEach(devices) { device in
                    // Channel count is how the console is spotted at a glance:
                    // a WING reports 48, everything else reports 1 or 2.
                    Text("\(device.name)  ·  \(device.channels) \(unit)")
                        .tag(AudioInput?.some(device))
                }
            }
            .labelsHidden()
        }
    }
}

private struct ParticipantRow: View {
    let participant: ParticipantInfo

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(participant.isSpeaking ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(participant.name)
                .font(.callout.weight(participant.isBridge ? .semibold : .regular))

            if participant.isBridge {
                Text("CONSOLE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            Spacer()

            Label(statusText, systemImage: statusSymbol)
                .labelStyle(.iconOnly)
                .foregroundStyle(statusColor)
                .help(statusText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var statusText: String {
        if !participant.publishesAudio { return "Listening only" }
        return participant.isMuted ? "Muted" : "Live"
    }

    private var statusSymbol: String {
        if !participant.publishesAudio { return "headphones" }
        return participant.isMuted ? "mic.slash.fill" : "mic.fill"
    }

    private var statusColor: Color {
        if !participant.publishesAudio { return .secondary }
        return participant.isMuted ? .secondary : .green
    }
}
