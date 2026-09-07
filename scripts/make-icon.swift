import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.98, green: 0.62, blue: 0.29, alpha: 1),
    NSColor(srgbRed: 0.90, green: 0.33, blue: 0.24, alpha: 1),
])!
gradient.draw(in: rect, angle: -60)
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
if let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { r in
        symbol.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}
image.unlockFocus()
let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
