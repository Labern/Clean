// INT./EXT. icon — black on white: the mark itself, set in the screenplay's own face.
// At 64px and up it is the spaced wordmark on one line — INT. / EXT. — his chosen form
// for the icon. Below that eleven characters turn to mud, so it falls back to the same
// mark wrapped where the slash breaks it: INT./ over EXT., bold, still the name.
import AppKit
import CoreText
import Foundation

func courier(_ size: Double, bold: Bool = false) -> CTFont {
    let file = bold ? "CourierPrime-Bold.ttf" : "CourierPrime-Regular.ttf"
    let candidates = ["../fonts/" + file, "fonts/" + file]
    for p in candidates where FileManager.default.fileExists(atPath: p) {
        let url = URL(fileURLWithPath: p) as CFURL
        if let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
           let d = descs.first {
            return CTFontCreateWithFontDescriptor(d, size, nil)
        }
    }
    return CTFontCreateWithName("Menlo" as CFString, size, nil)
}

func drawLine(_ ctx: CGContext, _ text: String, font: CTFont, ink: CGColor, centreX: Double, baselineY: Double) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: ink,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: centreX - width / 2, y: baselineY)
    CTLineDraw(line, ctx)
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
    let cx = s / 2, cy = s / 2

    if S >= 64 {
        // the mark, one line — eleven characters across the tile's measure
        let fs = rect.width / 11.0 * 1.55        // Courier advance ≈ 0.6em → fills ~84%
        let font = courier(fs, bold: true)
        drawLine(ctx, "INT. / EXT.", font: font, ink: ink, centreX: cx, baselineY: cy - fs * 0.29)
    } else {
        // small sizes: the mark wrapped at its own slash — INT./ over EXT.
        let fs = rect.width / 5.0 * 1.32
        let font = courier(fs, bold: true)
        drawLine(ctx, "INT./", font: font, ink: ink, centreX: cx, baselineY: cy + fs * 0.18)
        drawLine(ctx, "EXT.",  font: font, ink: ink, centreX: cx, baselineY: cy - fs * 0.82)
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
// …and one more, for the studio card: the same drawing with the Dock's clear padding
// cropped away and flattened onto white. On a card the padding is invisible and the
// tile's own hairline is too fine to read, so the card draws the border itself — but it
// can only do that if the tile goes all the way to the edge of the image.
let big = render(size: 512)
let pad = Int((512.0 * 0.055).rounded())
if let tile = big.cropping(to: CGRect(x: pad, y: pad, width: 512 - pad * 2, height: 512 - pad * 2)) {
    let W = tile.width, H = tile.height
    if let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: W, height: H))
        if let flat = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: flat)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(out)/../card-icon.png"))
        }
    }
}
print("wrote \(variants.count) sizes to \(out)")
