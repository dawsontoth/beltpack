import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var comms: CommsClient
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                StatusDial(state: comms.state)
                statusText
                Spacer()
                connectButton
            }
            .padding(28)
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
                Text("On comms").font(.headline)
                Text(comms.talkers.isEmpty
                    ? "Waiting for the console"
                    : "\(comms.talkers.count) other position\(comms.talkers.count == 1 ? "" : "s")")
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

    private var isConnected: Bool {
        if case .listening = comms.state { return true }
        return false
    }
}

/// A big, glanceable state indicator — this gets read in a dark booth,
/// often at arm's length.
private struct StatusDial: View {
    let state: CommsClient.State

    var body: some View {
        Circle()
            .fill(color.opacity(0.16))
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .overlay(Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(color))
            .frame(width: 180, height: 180)
            .animation(.easeInOut(duration: 0.2), value: color)
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .connecting, .reconnecting: .orange
        case .listening: .green
        case .failed: .red
        }
    }

    private var symbol: String {
        switch state {
        case .idle: "headphones"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .listening: "headphones.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
