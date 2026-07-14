// Build-time icon generator — run on macOS via:  swift IconGen.swift AppIcon.iconset
// Draws the GestureDeck icon (dark gradient squircle, teal ring, raised hand)
// at every size iconutil needs. Not part of the app target.
//
// Renders into an explicit NSBitmapImageRep at exact pixel dimensions —
// NSImage.lockFocus() renders at the screen's backing scale (2x on Retina),
// which produces wrongly-sized PNGs that iconutil rejects.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = NSSize(width: px, height: px)
    let inset = CGFloat(px) * 0.05
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    let radius = CGFloat(px) * 0.22
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.36, alpha: 1),
        NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.09, alpha: 1),
    ])?.draw(in: squircle, angle: -60)

    NSColor(calibratedRed: 0.37, green: 0.92, blue: 0.83, alpha: 0.85).setStroke()
    squircle.lineWidth = max(1, CGFloat(px) * 0.015)
    squircle.stroke()

    let emoji = "🖐" as NSString
    let attrs: [NSAttributedString.Key: Any] =
        [.font: NSFont.systemFont(ofSize: CGFloat(px) * 0.52)]
    let s = emoji.size(withAttributes: attrs)
    emoji.draw(at: NSPoint(x: (size.width - s.width) / 2,
                           y: (size.height - s.height) / 2), withAttributes: attrs)

    ctx.flushGraphics()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var failures = 0
for (name, px) in entries {
    if let data = render(px: px) {
        try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    } else {
        failures += 1
        FileHandle.standardError.write("FAILED: \(name)\n".data(using: .utf8)!)
    }
}
if failures > 0 { exit(1) }
print("icons → \(outDir)")
