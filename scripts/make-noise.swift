import AppKit

// Writes a tileable grain image for EmberWall. Grey noise around mid-grey so that an
// overlay blend at low opacity only breaks up gradient banding. Usage: swift make-noise.swift out.png
let size = 256
var rng = SystemRandomNumberGenerator()
var pixels = [UInt8](repeating: 0, count: size * size)
for i in pixels.indices {
    // Sum of two uniforms: a soft triangular distribution centred on 128.
    let a = Int.random(in: 0...255, using: &rng)
    let b = Int.random(in: 0...255, using: &rng)
    pixels[i] = UInt8((a + b) / 2)
}
let data = Data(pixels)
let provider = CGDataProvider(data: data as CFData)!
let image = CGImage(
    width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
)!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) (\(png.count) bytes)")
