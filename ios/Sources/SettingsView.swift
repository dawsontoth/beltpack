import AVFAudio
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var comms: CommsClient

    @State private var serverURL = Settings.serverURL
    @State private var identity = Settings.identity
    @State private var passcode = Settings.passcode
    @State private var talkMode = Settings.talkMode
    @State private var muteTone = Settings.muteTone
    @State private var outputMode = Settings.outputMode
    @State private var micInput = Settings.micInput.stored
    @State private var inputs: [AVAudioSessionPortDescription] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Your position") {
                    TextField("Name, e.g. Camera 2", text: $identity)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("192.168.1.50  or  comms.yourchurch.org", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passcode", text: $passcode)
                } header: {
                    Text("Comms server")
                } footer: {
                    // Forgiving, but never silently: show exactly what the
                    // typed address resolved to.
                    if serverURL.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("An address or a name is enough \u{2014} http, https and the port are worked out for you.")
                    } else if let resolved = ServerAddress.normalize(serverURL) {
                        Text("Connects to \(resolved.absoluteString)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Can't make sense of that address.")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("Speaker", selection: $outputMode) {
                        ForEach(AudioOutputMode.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Listening")
                } footer: {
                    Text(outputMode.detail)
                }

                Section {
                    Picker("When to transmit", selection: $talkMode) {
                        ForEach(TalkMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Microphone", selection: $micInput) {
                        Text("Off").tag(MicInput.offValue)
                        Text("Automatic").tag(MicInput.automaticValue)
                        ForEach(inputs, id: \.uid) { port in
                            Text(port.portName).tag(port.uid)
                        }
                    }
                    Toggle("Mute tone", isOn: $muteTone)
                } header: {
                    Text("Talking")
                } footer: {
                    Text(microphoneFooter)
                }

                Section {
                    NavigationLink("Announcement buttons") { PresetsEditor() }
                    NavigationLink("Pair another phone") { PairAnotherView() }
                }

                Section {
                    Text("You need to be on the comms Wi-Fi for this to connect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { inputs = AudioRouting.availableInputs() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Settings.serverURL = ServerAddress.normalize(serverURL)?.absoluteString
                            ?? serverURL.trimmingCharacters(in: .whitespaces)
                        Settings.identity = identity.trimmingCharacters(in: .whitespaces)
                        Settings.passcode = passcode
                        Settings.talkMode = talkMode
                        Settings.outputMode = outputMode
                        Settings.micInput = MicInput(stored: micInput)
                        Settings.muteTone = muteTone
                        comms.applyMuteTonePreference()
                        comms.applyRoutingPreferences()
                        dismiss()
                        // Apply immediately: someone switching mode
                        // mid-service should not have to rejoin.
                        Task { await comms.applyTalkModeChange() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private extension SettingsView {
    var microphoneFooter: String {
        var lines: [String] = []

        switch MicInput(stored: micInput) {
        case .off:
            lines.append("Never listens. No talking and no microphone indicator, and Bluetooth stays in high quality the whole time.")
        case .automatic:
            lines.append("Whatever iOS picks, which usually means a connected headset — and that drops both directions to call quality while you are on comms.")
        case let .port(uid):
            let port = AudioRouting.port(matching: uid)
            lines.append(port.map(AudioRouting.isBluetooth) == true
                ? "A Bluetooth microphone drops both directions to call quality while you are on comms."
                : "Keeps the earbuds in high quality, but you talk into the phone.")
        }

        lines.append(muteTone
            ? "iOS plays a tone each time the microphone mutes and unmutes."
            : "Silent muting. The orange microphone indicator stays lit while you are on comms, because the mic is armed and waiting.")

        return lines.joined(separator: "\n\n")
    }
}
