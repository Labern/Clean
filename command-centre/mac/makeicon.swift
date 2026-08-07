// makeicon.swift — renders the app icon straight into an .iconset directory.
//   swiftc -O makeicon.swift -o makeicon && ./makeicon build/App.iconset
// The command wall itself: a room's plan drawn in box-rule, with the five stars
// laid across the top the way they run across the top bar of the app. No image
// assets — the icon is code, so it is diffable and always regenerable.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green:   CGFloat((hex >>  8) & 0xff) / 255.0,
            blue:    CGFloat( hex        & 0xff) / 255.0, alpha: a)
}

func star(_ ctx: CGContext, center: CGPoint, r: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    for i in 0..<10 {
        let radius = i % 2 == 0 ? r : r * 0.42
        let a = CGFloat(i) * .pi / 5 - .pi / 2
        let pt = CGPoint(x: center.x + cos(a) * radius, y: center.y - sin(a) * radius)
        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
    }
    path.closeSubpath()
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
}

func render(_ S: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // ── the tile ──
    let inset = S * 0.075
    let tile = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: S * 0.196, cornerHeight: S * 0.196, transform: nil))
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(0x1a1638), rgb(0x302b63), rgb(0x0e0b1a)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    let glow = CGGradient(colorsSpace: cs,
                          colors: [rgb(0xaf87ff, 0.38), rgb(0xaf87ff, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.5, y: S * 0.42), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.5, y: S * 0.42), endRadius: S * 0.46, options: [])

    // ── the five stars, across the top, in the house gradient ──
    let colors: [CGColor] = [rgb(0x5fd7af), rgb(0x87d7d7), rgb(0xaf87ff), rgb(0xd787ff), rgb(0xff87ff)]
    let gap = S * 0.115
    for (i, c) in colors.enumerated() {
        star(ctx, center: CGPoint(x: S * 0.5 + (CGFloat(i) - 2) * gap, y: S * 0.705),
             r: S * 0.052, color: c)
    }

    // ── the room below: a plan of the wall, the desk and the table ──
    let stroke = max(S * 0.022, 1)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.square)

    let room = CGRect(x: S * 0.255, y: S * 0.235, width: S * 0.49, height: S * 0.335)
    ctx.setStrokeColor(rgb(0x875fd7))
    ctx.stroke(room)

    // the command wall — a solid gold rule along the top of the room
    ctx.setStrokeColor(rgb(0xffd75f))
    ctx.setLineWidth(stroke * 1.5)
    ctx.move(to: CGPoint(x: room.minX, y: room.maxY - stroke))
    ctx.addLine(to: CGPoint(x: room.maxX, y: room.maxY - stroke))
    ctx.strokePath()

    // the table and the desk — two filled blocks inside the plan
    ctx.setFillColor(rgb(0x87d7d7, 0.9))
    ctx.fill(CGRect(x: room.minX + S * 0.055, y: room.minY + S * 0.155,
                    width: S * 0.175, height: S * 0.07))
    ctx.setFillColor(rgb(0x5fd7af, 0.75))
    ctx.fill(CGRect(x: room.minX + S * 0.275, y: room.minY + S * 0.055,
                    width: S * 0.145, height: S * 0.06))

    // the threshold — a gap in the bottom wall, drawn as a break in teal
    ctx.setStrokeColor(rgb(0x0e0b1a))
    ctx.setLineWidth(stroke * 2.4)
    ctx.move(to: CGPoint(x: room.midX - S * 0.055, y: room.minY))
    ctx.addLine(to: CGPoint(x: room.midX + S * 0.055, y: room.minY))
    ctx.strokePath()

    ctx.restoreGState()
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
