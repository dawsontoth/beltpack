import BeltpackKit
import SwiftUI

/// Shows this phone's pairing code so another one can scan it.
///
/// Pairing from the booth Mac means walking to the booth. Pairing from a phone
/// that is already on comms means holding it out to whoever just arrived,
/// which is what actually happens before a service.
struct PairAnotherView: View {
    private var link: PairingLink? {
        let server = Settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let passcode = Settings.passcode
        guard !server.isEmpty, !passcode.isEmpty else { return nil }
        // Deliberately without an identity: the other phone is a different
        // position and needs its own name.
        return PairingLink(server: server, passcode: passcode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let link, let url = link.appURL, let image = QRCode.cgImage(for: url.absoluteString) {
                    Text("Point another iPhone's camera at this.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 280)
                        // A code needs a light field around it to scan, whatever
                        // appearance the phone is in.
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))

                    Text("They will still need to enter their own position name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Label(
                        "This code contains the passcode. Anyone who photographs it is on comms.",
                        systemImage: "exclamationmark.triangle",
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)

                    if let web = link.webURL {
                        Text("Android: \(web.absoluteString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ContentUnavailableView(
                        "Not paired yet",
                        systemImage: "qrcode",
                        description: Text("Set a server and passcode first, then this phone can pair others."),
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle("Pair another phone")
        .navigationBarTitleDisplayMode(.inline)
    }
}
