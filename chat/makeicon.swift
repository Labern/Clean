// makeicon.swift — renders the app icon straight into an .iconset directory.
//   swiftc -O makeicon.swift -o makeicon && ./makeicon build/App.iconset
// A speech bubble with a terminal block cursor inside it, on the PARADOX
// purple-black gradient: chat and terminal in one mark. No image assets, no
// Photoshop step — the icon is code, so it is diffable and always regenerable.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green:   CGFloat((hex >>  8) & 0xff) / 255.0,
            blue:    CGFloat( hex        & 0xff) / 255.0, alpha: 1)
}

func render(_ S: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // ── the tile: an Apple-ish squircle with a diagonal gradient ──
    let inset = S * 0.075
    let tile = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let squircle = CGPath(roundedRect: tile, cornerWidth: S * 0.196, cornerHeight: S * 0.196, transform: nil)
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(0x1a1638), rgb(0x302b63), rgb(0x14102b)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

    // a soft violet glow behind the mark, so the tile is not flat
    let glow = CGGradient(colorsSpace: cs,
                          colors: [CGColor(srgbRed: 0.686, green: 0.529, blue: 1, alpha: 0.42),
                                   CGColor(srgbRed: 0.686, green: 0.529, blue: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.5, y: S * 0.6), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.5, y: S * 0.6), endRadius: S * 0.44, options: [])
    ctx.restoreGState()

    // ── the speech bubble ──
    let stroke = max(S * 0.042, 1)
    let bub = CGRect(x: S * 0.235, y: S * 0.335, width: S * 0.53, height: S * 0.375)
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: bub, cornerWidth: S * 0.10, cornerHeight: S * 0.10)
    // the tail, hanging off the bottom-left
    bubble.move(to:    CGPoint(x: bub.minX + S * 0.10, y: bub.minY + stroke * 0.4))
    bubble.addLine(to: CGPoint(x: bub.minX + S * 0.075, y: bub.minY - S * 0.115))
    bubble.addLine(to: CGPoint(x: bub.minX + S * 0.235, y: bub.minY + stroke * 0.4))
    bubble.closeSubpath()

    ctx.setLineWidth(stroke)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0xaf87ff))            // --violet
    ctx.addPath(bubble)
    ctx.strokePath()

    // ── the block cursor inside ──
    ctx.setFillColor(rgb(0x87d7d7))              // --teal
    ctx.fill(CGRect(x: bub.minX + S * 0.095, y: bub.midY - S * 0.085,
                    width: S * 0.075, height: S * 0.17))
    // two shorter "typed" bars beside it, to read as text at small sizes
    ctx.setFillColor(CGColor(srgbRed: 0.812, green: 0.792, blue: 0.902, alpha: 0.85))
    ctx.fill(CGRect(x: bub.minX + S * 0.205, y: bub.midY - S * 0.020,
                    width: S * 0.215, height: S * 0.048))
    ctx.fill(CGRect(x: bub.minX + S * 0.205, y: bub.midY - S * 0.098,
                    width: S * 0.135, height: S * 0.048))

    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

for base in [16, 32, 128, 256, 512] {
    write(render(CGFloat(base)),     "icon_\(base)x\(base).png")
    write(render(CGFloat(base * 2)), "icon_\(base)x\(base)@2x.png")
}
print("wrote \(outDir)")
