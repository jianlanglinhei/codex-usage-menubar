import AppKit
import SwiftUI

@main
struct CupRenderingChecks {
    @MainActor
    static func main() throws {
        func render(_ value: Int) -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: QuotaCup(remaining: value).frame(width: 100, height: 140))
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Cup did not render") }
            return NSBitmapImageRep(cgImage: image)
        }
        func isCoffee(_ image: NSBitmapImageRep, y: Int) -> Bool {
            let color = image.colorAt(x: 100, y: y * 2)!.usingColorSpace(.deviceRGB)!
            return color.greenComponent < 0.7 && color.redComponent > 0.7
        }
        let empty = render(0), quarter = render(25), seventyFive = render(75), eightyOne = render(81), full = render(100)
        // Probe the rendered liquid itself, clear of the face, border and scale.
        precondition(!isCoffee(empty, y: 95), "0% must be empty")
        precondition(isCoffee(quarter, y: 110) && !isCoffee(quarter, y: 80), "25% must fill only the bottom quarter")
        precondition(!isCoffee(seventyFive, y: 53) && isCoffee(eightyOne, y: 53), "81% must visibly sit above the 75% mark")
        precondition(isCoffee(full, y: 40), "100% must reach the top mark")
        precondition(render(-10).tiffRepresentation == empty.tiffRepresentation, "Negative values must clamp to empty")
        precondition(render(120).tiffRepresentation == full.tiffRepresentation, "Values over 100 must clamp to full")
        func status(_ value: Int?, stale: Bool = false) -> Data {
            let icon = quotaImage(remaining: value, stale: stale)
            precondition(icon.size == NSSize(width: 18, height: 20))
            return icon.tiffRepresentation!
        }
        precondition(status(0) != status(40) && status(40) != status(100), "Menu cup must follow the live quota")
        precondition(status(nil) != status(0), "Unknown quota must remain distinct from empty")
        precondition(status(40) != status(40, stale: true), "Stale cup must be faded")
        precondition(status(100) == status(120), "Menu cup cannot overfill")
        let gallery = HStack(spacing: 16) {
            ForEach([0, 25, 75, 81, 100], id: \.self) { value in
                VStack {
                    QuotaCup(remaining: value).frame(width: 108, height: 146)
                    Text("\(value)%").foregroundColor(.black)
                }
            }
        }.padding(16).background(Color.white)
        let renderer = ImageRenderer(content: gallery)
        renderer.scale = 2
        if CommandLine.arguments.count > 1, let image = renderer.cgImage {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("PASS cup rendering: empty, partial, 75/81 distinction, full, bounds; menu cup live, unknown, stale")
    }
}
