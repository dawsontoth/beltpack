import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var comms: CommsClient
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                StatusDial(state: comms.state, isTalking: comms.isTalking)
                statusText
                if isConnected {
                    LevelControls()
                        .environmentObject(comms)
                }

                if isConnected, Settings.talkMode.needsMicrophone, Settings.talkMode != .open {
                    TalkButton(
                        mode: Settings.talkMode,
                        isTalking: comms.isTalking,
                        onPress: { Task { await comms.startTalking() } },
                        onRelease: { Task { await comms.stopTalking() } },
                        onToggle: { Task { await comms.toggleTalking() } },
                    )
                }
                if comms.micDenied {
                    Text("Microphone access is off for Beltpack. Enable it in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if let reason = comms.micUnavailable {
                    Text("Listening only — \(reason)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if isConnected {
                    AnnouncementBar()
                        .environmentObject(comms)
                }

                Spacer()
                connectButton
            }
            .padding(28)
            .animation(.easeOut(duration: 0.2), value: comms.announcement)
            .navigationTitle("Beltpack")
            .toolbar {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        // On the NavigationStack, not its content: applied inside, the inset
        // lands above the navigation bar and rides over the status bar.
        .safeAreaInset(edge: .top) {
            if let announcement = comms.announcement {
                AnnouncementBanner(announcement: announcement)
                    .id(announcement.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch comms.state {
        case .idle:
            Text("Not connected").foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting…").foregroundStyle(.secondary)
        case .listening:
            VStack(spacing: 6) {
                Text(comms.isTalking ? "Talking" : "On comms")
                    .font(.headline)
                    .foregroundStyle(comms.isTalking ? .orange : .primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .reconnecting:
            Text("Reconnecting…").foregroundStyle(.orange)
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var connectButton: some View {
        Button {
            Task {
                if case .listening = comms.state {
                    await comms.disconnect()
                } else {
                    await comms.connect()
                }
            }
        } label: {
            Text(isConnected ? "Leave comms" : "Join comms")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(isConnected ? .red : .accentColor)
    }

    /// What a camera op actually wants to know at a glance: is the console
    /// feed live, and who else is on.
    private var detail: String {
        let others = comms.talkers.count - (comms.consoleIsLive ? 1 : 0)
        switch (comms.consoleIsLive, others) {
        case (false, _): return "Waiting for the console"
        case (true, 0): return "Console live"
        case (true, 1): return "Console live \u{00B7} 1 other position"
        case let (true, n): return "Console live \u{00B7} \(n) other positions"
        }
    }

    private var isConnected: Bool {
        if case .listening = comms.state { return true }
        return false
    }
}

/// A big, glanceable state indicator — this gets read in a dark booth,
/// often at arm's length.
private struct StatusDial: View {
    let state: CommsClient.State
    var isTalking = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.16))
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .overlay(Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(color))
            .frame(width: 180, height: 180)
            .animation(.easeInOut(duration: 0.2), value: color)
    }

    private var color: Color {
        if isTalking { return .orange }
        switch state {
        case .idle: return .secondary
        case .connecting, .reconnecting: return .orange
        case .listening: return .green
        case .failed: return .red
        }
    }

    private var symbol: String {
        if isTalking { return "mic.fill" }
        switch state {
        case .idle: return "headphones"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .listening: return "headphones.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// The talk control. Big, because it gets pressed by someone whose eyes are
/// on a camera rather than the phone, and haptic for the same reason.
private struct TalkButton: View {
    let mode: TalkMode
    let isTalking: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onToggle: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isTalking ? Color.orange : Color.secondary.opacity(0.22))
                .overlay(
                    Image(systemName: isTalking ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(isTalking ? Color.black : Color.secondary),
                )
                .frame(width: 128, height: 128)
                .scaleEffect(pressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .contentShape(Circle())
                .gesture(gesture)
                .accessibilityLabel(mode == .pushToTalk ? "Hold to talk" : "Talk")
                .accessibilityAddTraits(.isButton)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        switch mode {
        case .listenOnly: "Listening"
        case .pushToTalk: isTalking ? "Release to stop" : "Hold to talk"
        case .latch: isTalking ? "Tap to stop" : "Tap to talk"
        case .open: "Mic open"
        }
    }

    private var gesture: some Gesture {
        // minimumDistance 0 so it fires on touch-down rather than on a drag,
        // which is what makes press-and-talk feel immediate.
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                haptic(.rigid)
                if mode == .pushToTalk { onPress() }
            }
            .onEnded { _ in
                pressed = false
                haptic(.soft)
                switch mode {
                case .pushToTalk: onRelease()
                case .latch: onToggle()
                case .open, .listenOnly: break
                }
            }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// Personal trims. Every real beltpack has these, because one position always
/// wants the director louder and one always sits too close to their own mic.
private struct LevelControls: View {
    @EnvironmentObject private var comms: CommsClient
    @ObservedObject private var levels: AudioLevels

    @State private var listen = Settings.listenVolume
    @State private var mic = Settings.micGain

    init() {
        // Bound at init so the meters update without the parent redrawing.
        _levels = ObservedObject(wrappedValue: CommsClient.sharedLevels)
    }

    var body: some View {
        VStack(spacing: 16) {
            LevelRow(
                title: "You hear",
                systemImage: "speaker.wave.2.fill",
                value: $listen,
                level: levels.listen,
                onChange: { comms.setListenVolume($0) },
            )

            LevelRow(
                title: "They hear you",
                systemImage: "mic.fill",
                value: $mic,
                level: comms.isTalking ? levels.mic : 0,
                onChange: { comms.setMicGain($0) },
                // A meter that moves while muted would suggest you are live.
                dimmed: !comms.isTalking,
            )
        }
        .padding(.horizontal, 4)
    }
}

private struct LevelRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let level: Float
    let onChange: (Double) -> Void
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption)
                Text(title).font(.caption)
                Spacer()
                Text(value == 1 ? "unity" : String(format: "%+.0f dB", 20 * log10(max(value, 0.01))))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            Slider(value: $value, in: Settings.gainRange) { editing in
                if !editing { onChange(value) }
            }
            .onChange(of: value) { _, new in onChange(new) }

            Meter(level: level).opacity(dimmed ? 0.35 : 1)
        }
    }
}

/// A plain bar. Colour carries the warning, because in a dark booth at arm's
/// length that reads faster than a number.
private struct Meter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(colour)
                    .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.05), value: level)
    }

    private var colour: Color {
        switch level {
        case ..<0.7: .green
        case ..<0.92: .orange
        default: .red
        }
    }
}
