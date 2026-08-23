import SwiftUI

/// Edits the announcement buttons.
///
/// Every room has its own shorthand, and a preset nobody would say is just a
/// button in the way. Kept short deliberately: these get pressed by somebody
/// holding a camera, and a long phrase stops being a cue.
struct PresetsEditor: View {
    @State private var presets = Settings.presets
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { preset in
                    Text(preset)
                }
                .onDelete { presets.remove(atOffsets: $0); save() }
                .onMove { presets.move(fromOffsets: $0, toOffset: $1); save() }

                if presets.isEmpty {
                    Text("No presets. The text field on the main screen still works.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Buttons")
            } footer: {
                Text("Swipe to delete, drag to reorder. Order is the order they appear.")
            }

            Section("Add") {
                HStack {
                    TextField("Something short", text: $draft)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(trimmed.isEmpty || presets.contains(trimmed))
                }
            }

            Section {
                Button("Restore defaults") {
                    Settings.resetPresets()
                    presets = Settings.presets
                }
            }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmed.isEmpty, !presets.contains(trimmed) else { return }
        presets.append(trimmed)
        draft = ""
        typing = false
        save()
    }

    private func save() {
        Settings.presets = presets
    }
}
