import SwiftUI

/// Asked once, immediately after a code is scanned.
///
/// The code carries the server and the passcode, so a name is the only thing
/// left — and it is the one thing the person holding out the code cannot know.
/// Without this the scan succeeds silently and the volunteer is left on a
/// screen that will not connect, with no indication that the missing piece is
/// four taps away under Settings.
struct JoinAsView: View {
    let onJoin: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    /// Positions, not people. This is what everyone else sees when the cue
    /// comes, and "Camera 2" is more use mid-service than "Amy" — the desk
    /// knows where Camera 2 is pointed.
    private static let positions = [
        "FOH", "Monitors", "Lighting", "Director",
        "Camera 1", "Camera 2", "Camera 3", "Stage", "Booth",
    ]

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            // Scrolls, and the button stays pinned. With the keyboard up there
            // is very little room left on a small phone, and the join button is
            // exactly the part that would be pushed off the bottom.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("You're paired. This is the name everyone else sees on comms.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("Camera 2", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .autocorrectionDisabled()
                            .submitLabel(.join)
                            .focused($focused)
                            .onSubmit(join)

                        // Tapping fills the field rather than joining outright:
                        // a mis-tap here puts the wrong name on the ring for
                        // everybody, and the join button is already right there.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(Self.positions, id: \.self) { position in
                                Button(position) { name = position }
                                    .buttonStyle(.bordered)
                                    .tint(trimmed == position ? .accentColor : .secondary)
                            }
                        }
                    }
                    .padding()
                }

                Button(action: join) {
                    Text("Join comms").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)
                .padding()
            }
            .navigationTitle("Who is this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // An escape hatch, not a dead end: the server and passcode
                    // are already saved, so Settings needs only the name.
                    Button("Not now") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func join() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onJoin(value)
    }
}
