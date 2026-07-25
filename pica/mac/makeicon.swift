// PICA icon — black on white: an actual scrap of screenplay.
// At 128px and up it sets real Courier text at true screenplay indents — slug, action,
// character cue, dialogue. Below that the type would turn to mud, so it falls back to the
// same excerpt drawn as bars, keeping the silhouette identical at every size.
import AppKit
import CoreText
import Foundation

// the excerpt, as (indent in characters, text). Indents mirror real page margins.
let script: [(Int, String)] = [
    (0,  "INT. STAGE - NIGHT"),
    (0,  ""),
    (0,  "Lights up on an"),
    (0,  "empty room."),
    (0,  ""),
    (9,  "WRITER"),
    (5,  "Begin."),
]
let cols = 19          // characters across the measure

func courier(_ size: Double) -> CTFont {
    let candidates = ["../fonts/CourierPrime-Regular.ttf", "fonts/CourierPrime-Regular.ttf"]
    for p in candidates where FileManager.default.fileExists(atPath: p) {
        let url = URL(fileURLWithPath: p) as CFURL
        if let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
           let d = descs.first {
            return CTFontCreateWithFontDescriptor(d, size, nil)
        }
    }
    return CTFontCreateWithName("Menlo" as CFString, size, nil)
}

func render(size S: Int) -> CGImage {
    let s = Double(S)
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // white tile, macOS-ish rounded square
    let pad = s * 0.055
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let ground = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237,
                        cornerHeight: rect.width * 0.2237, transform: nil)
    ctx.addPath(ground)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    if S >= 32 {   // hairline so the tile still reads on a white background
        ctx.addPath(ground)
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.845, blue: 0.83, alpha: 1))
        ctx.setLineWidth(max(1, s * 0.006))
        ctx.strokePath()
    }

    let ink = CGColor(red: 0.078, green: 0.078, blue: 0.075, alpha: 1)
    let inset = S <= 40 ? 0.165 : 0.175
    let box = CGRect(x: s * inset, y: s * inset, width: s * (1 - inset * 2), height: s * (1 - inset * 2))
    let rowH = box.height / Double(script.count)
    let adv = box.width / Double(cols)          // one character cell

    if S >= 128 {
        // real type
        let font = courier(adv / 0.6001)        // Courier advance is 0.6em
        for (i, line) in script.enumerated() where !line.1.isEmpty {
            let x = box.minX + Double(line.0) * adv
            let y = box.maxY - Double(i) * rowH - rowH * 0.78
            let attr = NSAttributedString(string: line.1, attributes: [
                .font: font, .foregroundColor: NSColor(cgColor: ink)!,
            ])
            let ctLine = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(ctLine, ctx)
        }
    } else {
        // the same excerpt as bars, so small sizes keep the shape rather than a smudge
        let barH = max(1, (rowH * 0.42).rounded())
        ctx.setFillColor(ink)
        for (i, line) in script.enumerated() where !line.1.isEmpty {
            let x = box.minX + Double(line.0) * adv
            let w = Double(line.1.count) * adv
            let y = box.maxY - Double(i) * rowH - barH - rowH * 0.12
            ctx.fill(CGRect(x: x.rounded(), y: y.rounded(), width: max(2, w.rounded()), height: barH))
        }
    }
    return ctx.makeImage()!
}

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
    let rep = NSBitmapImageRep(cgImage: render(size: size))
    rep.size = NSSize(width: size, height: size)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(variants.count) sizes to \(out)")
