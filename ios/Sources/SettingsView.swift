import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = Settings.serverURL
    @State private var identity = Settings.identity
    @State private var passcode = Settings.passcode

    var body: some View {
        NavigationStack {
            Form {
                Section("Your position") {
                    TextField("Name, e.g. Camera 2", text: $identity)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section("Comms server") {
                    TextField("https://comms.example.org", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passcode", text: $passcode)
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
                        Settings.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
                        Settings.identity = identity.trimmingCharacters(in: .whitespaces)
                        Settings.passcode = passcode
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
