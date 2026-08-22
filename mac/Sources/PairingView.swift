import BeltpackKit
import SwiftUI

/// Shows the pairing codes a volunteer scans, so nobody types a server address
/// or a passcode into a phone by hand.
struct PairingView: View {
    let link: PairingLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Pair a beltpack").font(.title3.weight(.semibold))
                Text("Point a phone camera at the code for its platform.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                // Two codes, because one cannot serve both: the app scheme
                // opens the native app, the https form opens the web client.
                CodeCard(title: "iPhone", subtitle: "Opens the app", url: link.appURL)
                CodeCard(title: "Android", subtitle: "Opens in the browser", url: link.webURL)
            }

            Label(
                "These codes contain the passcode. Treat a printed one as a key — anyone who photographs it is on comms.",
                systemImage: "exclamationmark.triangle",
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: 420)
            .fixedSize(horizontal: false, vertical: true)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}

private struct CodeCard: View {
    let title: String
    let subtitle: String
    let url: URL?

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            if let url, let image = QRCode.cgImage(for: url.absoluteString) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 190, height: 190)
                    // A code needs a light field around it to scan reliably,
                    // regardless of the app's appearance.
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 210, height: 210)
                    .overlay(Text("Unavailable").font(.caption).foregroundStyle(.secondary))
            }
        }
    }
}
