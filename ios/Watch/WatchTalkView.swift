import SwiftUI
import WatchKit

/// The whole screen is the button.
///
/// This gets pressed by someone with both hands on a camera who is looking at
/// a shot, not at their wrist. So: no small controls, no Digital Crown, no
/// precision required — press anywhere.
struct WatchTalkView: View {
    @EnvironmentObject private var link: WatchLink
    @State private var pressed = false
    /// True when the wrist is down and the display is dimmed. The app is still
    /// frontmost and still being updated — it just must not sit there at full
    /// brightness for an hour.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var snapshot: CommsSnapshot { link.snapshot }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(foreground)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(foreground)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(foreground.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }
            .scaleEffect(pressed ? 0.94 : 1)
            // Animating a dimmed screen is spend for something nobody is
            // looking at.
            .animation(isLuminanceReduced ? nil : .easeOut(duration: 0.1), value: pressed)
        }
        .contentShape(Rectangle())
        .gesture(gesture)
        .onAppear { link.refresh() }
    }

    // MARK: - Interaction

    private var gesture: some Gesture {
        // minimumDistance 0 so it fires on touch-down: hold-to-talk has to feel
        // immediate, and a drag threshold would swallow a quick press.
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed, snapshot.canTalk else { return }
                pressed = true
                WKInterfaceDevice.current().play(.start)
                if snapshot.mode == .pushToTalk { link.send(.startTalking) }
            }
            .onEnded { _ in
                guard pressed else { return }
                pressed = false
                WKInterfaceDevice.current().play(.stop)
                switch snapshot.mode {
                case .pushToTalk: link.send(.stopTalking)
                case .latch: link.send(.toggleTalking)
                case .open, .listenOnly: break
                }
            }
    }

    // MARK: - Appearance

    private var background: Color {
        // A live mic still has to be obvious with the wrist down — that is the
        // state most worth noticing — but not at full brightness.
        if snapshot.isTalking { return isLuminanceReduced ? Color.orange.opacity(0.4) : .orange }
        if !link.isReachable || !snapshot.isConnected { return .black }
        return Color(white: isLuminanceReduced ? 0.06 : 0.11)
    }

    private var foreground: Color {
        // Black on dimmed orange is unreadable; the dark background takes white.
        snapshot.isTalking && !isLuminanceReduced ? .black : .white
    }

    private var symbol: String {
        if !link.isReachable { return "iphone.slash" }
        if !snapshot.isConnected { return "headphones" }
        return snapshot.isTalking ? "mic.fill" : "mic.slash.fill"
    }

    private var title: String {
        if !link.isReachable { return "No phone" }
        if !snapshot.isConnected { return "Off comms" }
        return snapshot.isTalking ? "Talking" : "Hold"
    }

    private var subtitle: String {
        // Every branch says what to do about it, rather than only what is wrong.
        if let error = link.lastError { return error }
        if !link.isReachable { return "Open Beltpack on your phone" }
        if !snapshot.isConnected { return snapshot.status }
        switch snapshot.mode {
        case .pushToTalk: return snapshot.isTalking ? "Release to stop" : "Hold to talk"
        case .latch: return snapshot.isTalking ? "Tap to stop" : "Tap to talk"
        case .open: return "Mic is open"
        case .listenOnly: return "Listening only"
        }
    }
}
