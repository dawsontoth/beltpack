import CoreImage
import Foundation
import Testing

@testable import BeltpackKit

@Suite("QRCode")
struct QRCodeTests {
    /// Reads a generated code back with CoreImage's detector. Generating
    /// something that merely looks like a QR is not the same as generating one
    /// that scans, and only a decode proves the difference.
    private func decode(_ matrix: [[Bool]]) -> String? {
        let size = matrix.count
        var pixels = [UInt8](repeating: 0, count: size * size)
        for (y, row) in matrix.enumerated() {
            for (x, dark) in row.enumerated() {
                pixels[y * size + x] = dark ? 0 : 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent,
              )
        else { return nil }

        // Scale up: the detector will not resolve a matrix at one pixel per module.
        let scaled = CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: scaled) as? [CIQRCodeFeature]
        return features?.first?.messageString
    }

    @Test("a generated code actually decodes back to the same text")
    func roundTrip() throws {
        let link = PairingLink(server: "http://172.16.1.41:7883", passcode: "9qmbutqe38", identity: "Camera 2")
        let text = try #require(link.appURL).absoluteString

        let matrix = try #require(QRCode.matrix(for: text))
        #expect(matrix.count == matrix[0].count, "a QR matrix is square")
        #expect(decode(matrix) == text)
    }

    @Test("survives a long https pairing URL")
    func longURL() throws {
        let link = PairingLink(server: "https://comms.trinity-community-church.org", passcode: "a-fairly-long-passcode-value")
        let text = try #require(link.webURL).absoluteString
        let matrix = try #require(QRCode.matrix(for: text))
        #expect(decode(matrix) == text)
    }

    @Test("terminal rendering has a quiet zone and halves the line count")
    func rendering() throws {
        let matrix = try #require(QRCode.matrix(for: "beltpack://join?server=a&passcode=b"))
        let quiet = 3
        let text = QRCode.terminalRendering(matrix, quietZone: quiet)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }

        let paddedRows = matrix.count + quiet * 2
        #expect(lines.count == (paddedRows + 1) / 2)
        // The first line is entirely quiet zone, so it carries no dark modules.
        #expect(!lines[0].contains("\u{2588}"))
    }
}
