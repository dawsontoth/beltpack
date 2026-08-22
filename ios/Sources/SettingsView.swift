import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var comms: CommsClient

    @State private var serverURL = Settings.serverURL
    @State private var identity = Settings.identity
    @State private var passcode = Settings.passcode
    @State private var micMode = Settings.micMode
    @State private var talkMode = Settings.talkMode

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
                    Picker("When to transmit", selection: $talkMode) {
                        ForEach(TalkMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Microphone", selection: $micMode) {
                        ForEach(MicMode.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Talking")
                } footer: {
                    Text(micMode.detail)
                }

                Section {
                    Text("You need to be on the comms Wi-Fi for this to connect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Settings.serverURL = ServerAddress.normalize(serverURL)?.absoluteString
                            ?? serverURL.trimmingCharacters(in: .whitespaces)
                        Settings.identity = identity.trimmingCharacters(in: .whitespaces)
                        Settings.passcode = passcode
                        Settings.micMode = micMode
                        Settings.talkMode = talkMode
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
