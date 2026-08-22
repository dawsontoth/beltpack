import CoreImage
import Foundation

/// QR rendering via CoreImage, so there is no dependency to keep current.
public enum QRCode {
    /// A square matrix of modules, `true` meaning dark.
    public static func matrix(for text: String) -> [[Bool]]? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        // Medium correction: enough to survive a printed sheet going scruffy
        // without inflating the code so much it stops scanning across a room.
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let image = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let grey = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { return nil }

        grey.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (0 ..< height).map { row in
            (0 ..< width).map { column in pixels[row * width + column] < 128 }
        }
    }

    /// A scaled bitmap, for showing a code on screen.
    ///
    /// Nearest-neighbour on purpose: interpolating a QR softens the module
    /// edges and makes it harder to scan, which is the opposite of the point.
    public static func cgImage(for text: String, scale: CGFloat = 10) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(scaled, from: scaled.extent)
    }

    /// An SVG of the code, for embedding in a page without encoding an image
    /// or shipping a JavaScript QR library to the browser.
    public static func svg(for text: String, quietZone: Int = 3) -> String? {
        guard let matrix = matrix(for: text) else { return nil }
        let size = matrix.count + quietZone * 2

        var paths = ""
        for (y, row) in matrix.enumerated() {
            for (x, dark) in row.enumerated() where dark {
                paths += "M\(x + quietZone) \(y + quietZone)h1v1h-1z"
            }
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(size) \(size)" \
        shape-rendering="crispEdges" role="img" aria-label="Pairing code">\
        <rect width="\(size)" height="\(size)" fill="#fff"/>\
        <path d="\(paths)" fill="#000"/></svg>
        """
    }

    /// Renders to text using half-block characters, two module rows per line,
    /// so a code fits in a terminal window and survives an SSH session.
    ///
    /// Colours are forced rather than inherited: a scanner needs dark modules
    /// on a light field, and most booth terminals are the other way round.
    public static func terminalRendering(_ matrix: [[Bool]], quietZone: Int = 3) -> String {
        guard !matrix.isEmpty else { return "" }

        let width = matrix[0].count + quietZone * 2
        let padded =
            Array(repeating: [Bool](repeating: false, count: width), count: quietZone)
            + matrix.map { Array(repeating: false, count: quietZone) + $0 + Array(repeating: false, count: quietZone) }
            + Array(repeating: [Bool](repeating: false, count: width), count: quietZone)

        let reset = "\u{1b}[0m"
        let lightOnDark = "\u{1b}[107m\u{1b}[30m" // white background, black glyphs

        var out = ""
        var row = 0
        while row < padded.count {
            let top = padded[row]
            let bottom = row + 1 < padded.count ? padded[row + 1] : [Bool](repeating: false, count: width)

            out += lightOnDark
            for column in 0 ..< width {
                switch (top[column], bottom[column]) {
                case (true, true): out += "\u{2588}"   // full block
                case (true, false): out += "\u{2580}"  // upper half
                case (false, true): out += "\u{2584}"  // lower half
                case (false, false): out += " "
                }
            }
            out += reset + "\n"
            row += 2
        }
        return out
    }
}
