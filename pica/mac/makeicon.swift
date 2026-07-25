// PICA icon — black on white. The mark is a screenplay page reduced to its rhythm:
// full-measure action bars, a short centred character cue, indented dialogue.
// Renders every iconset size with size-appropriate detail, then `iconutil` makes the .icns.
import AppKit
import CoreGraphics
import Foundation

struct Bar { let x: Double; let w: Double; let unit: Int }   // x,w as fractions of the measure

// full rhythm — action, action / cue, dialogue, dialogue / action, action / cue, dialogue
let detailed: [Bar] = [
    .init(x: 0.00, w: 1.00, unit: 0),
    .init(x: 0.00, w: 0.78, unit: 1),
    .init(x: 0.41, w: 0.23, unit: 3),
    .init(x: 0.21, w: 0.58, unit: 4),
    .init(x: 0.21, w: 0.45, unit: 5),
    .init(x: 0.00, w: 1.00, unit: 7),
    .init(x: 0.00, w: 0.60, unit: 8),
    .init(x: 0.41, w: 0.23, unit: 10),
    .init(x: 0.21, w: 0.52, unit: 11),
]
let detailedUnits = 12

// reduced rhythm for small sizes — one action line, a cue, one dialogue line, one action line
let simple: [Bar] = [
    .init(x: 0.00, w: 1.00, unit: 0),
    .init(x: 0.38, w: 0.26, unit: 2),
    .init(x: 0.19, w: 0.62, unit: 3),
    .init(x: 0.00, w: 0.82, unit: 5),
]
let simpleUnits = 6

func render(size S: Int) -> CGImage {
    let s = Double(S)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // white ground, rounded like a macOS app icon, inset slightly so the shadow-less
    // square never touches the tile edge
    let pad = s * 0.055
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let radius = rect.width * 0.2237
    let ground = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(ground)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // a hairline keeps the white tile legible against a white background
    if S >= 32 {
        ctx.addPath(ground)
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.845, blue: 0.83, alpha: 1))
        ctx.setLineWidth(max(1, s * 0.006))
        ctx.strokePath()
    }

    let small = S <= 40
    let bars = small ? simple : detailed
    let units = small ? simpleUnits : detailedUnits

    // the text block: tighter margins when small so the bars stay thick enough to read
    let inset = small ? 0.175 : 0.215
    let box = CGRect(x: s * inset, y: s * inset, width: s * (1 - inset * 2), height: s * (1 - inset * 2))
    let unitH = box.height / Double(units)
    let barH = max(1, (unitH * (small ? 0.62 : 0.56)).rounded())

    ctx.setFillColor(CGColor(red: 0.078, green: 0.078, blue: 0.075, alpha: 1))
    for b in bars {
        let x = box.minX + b.x * box.width
        let w = b.w * box.width
        // unit 0 is the top line: flip, since CGContext origin is bottom-left
        let y = box.maxY - Double(b.unit) * unitH - barH
        let r = CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: barH)
        if S >= 128 {
            let rad = min(barH / 2, s * 0.006)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
            ctx.fillPath()
        } else {
            ctx.fill(r)
        }
    }
    return ctx.makeImage()!
}

// ---- write the iconset ----
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "PICA.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    let img = render(size: size)
    let url = URL(fileURLWithPath: "\(out)/\(name).png")
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: size, height: size)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
print("wrote \(variants.count) sizes to \(out)")
