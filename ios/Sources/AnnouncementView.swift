import SwiftUI

/// Preset announcements, and whatever the last one was.
///
/// Presets rather than a keyboard first: typing on a phone while holding a
/// camera is the thing this is meant to avoid. Free text is there underneath
/// for the case a preset does not cover.
struct AnnouncementBar: View {
    @EnvironmentObject private var comms: CommsClient
    @State private var custom = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 10) {
            if comms.isAnnouncing {
                Button(role: .destructive) {
                    Task { await comms.stopAnnouncement() }
                } label: {
                    Label("Stop announcement", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnnouncementPreset.all, id: \.self) { preset in
                            Button(preset) {
                                Task { await comms.announce(preset) }
                            }
                            .buttonStyle(.bordered)
                            .font(.callout)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                HStack(spacing: 8) {
                    TextField("Say something else…", text: $custom)
                        .textFieldStyle(.roundedBorder)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button("Say", action: send)
                        .buttonStyle(.borderedProminent)
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        let text = custom
        custom = ""
        typing = false
        Task { await comms.announce(text) }
    }
}

/// The last announcement, shown on every phone in the room.
struct AnnouncementBanner: View {
    let announcement: Announcement

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(announcement.text)
                .font(.headline)
                .foregroundStyle(.black)
            Text(announcement.sender.isEmpty ? "Announcement" : announcement.sender)
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.yellow, in: RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
