import Testing
import UIKit
import SwiftUI
@testable import Icons

@Suite("Icon designer")
@MainActor
struct IconDesignerTests {
    private func shelf() -> (IconShelf, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "icons-\(UUID().uuidString)")
        return (IconShelf(folder: folder), folder)
    }

    private func square(_ side: Int, alpha: CGFloat = 1) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            UIColor.red.withAlphaComponent(alpha).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// The page and the outlines it draws both have to be in the app.
    @Test func theDesignerShipsInTheApp() throws {
        let page = try #require(DesignerBoard.page)
        let outlines = page.deletingLastPathComponent().appending(path: "logos.js")
        #expect(FileManager.default.fileExists(atPath: outlines.path(percentEncoded: false)))
        #expect(try String(contentsOf: page, encoding: .utf8).contains("window.D="))
    }

    @Test func aSavedIconIsKeptAndCanBeRemoved() throws {
        let (first, folder) = shelf()
        let icon = try first.add(png: square(64), title: "MARK", recipe: "{}")
        #expect(icon.id.count == 8)
        #expect(icon.asset == "AppIcon-Custom-\(icon.id)")
        #expect(first.picture(icon) != nil)

        let reopened = IconShelf(folder: folder)
        #expect(reopened.icons == [icon])

        reopened.wanted = icon.id
        reopened.remove(icon)
        #expect(reopened.icons.isEmpty)
        #expect(reopened.wanted.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reopened.file(icon).path(percentEncoded: false)))
        reopened.wanted = ""
    }

    /// An app icon must be exactly 1024px with no alpha channel, and the right way up.
    @Test func picturesAreFlattenedForAnIcon() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let source = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format).pngData { context in
            UIColor.red.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))      // top half
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 150, width: 300, height: 150))    // bottom half
        }
        let flat = try #require(IconShelf.flatten(source))
        let image = try #require(UIImage(data: flat)?.cgImage)
        #expect(image.width == 1024)
        #expect(image.height == 1024)
        #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))

        // Read one pixel near the top and one near the bottom.
        var bytes = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let bitmap = try #require(CGContext(data: buffer.baseAddress, width: 1024, height: 1024, bitsPerComponent: 8,
                                                bytesPerRow: 1024 * 4, space: space,
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        let top = 100 * 1024 * 4 + 512 * 4, bottom = 900 * 1024 * 4 + 512 * 4
        #expect(bytes[top] > 100 && bytes[top + 2] < 30, "the top should still be red")
        #expect(bytes[bottom + 2] > 200 && bytes[bottom] < 30, "the bottom should still be blue")
    }

    @Test func thePagesAnswerIsReadAsAPicture() {
        let png = square(8)
        #expect(IconShelf.decode(dataURL: "data:image/png;base64," + png.base64EncodedString()) == png)
        #expect(IconShelf.decode(dataURL: "data:image/jpeg;base64,AAAA") == nil)
        #expect(IconShelf.decode(dataURL: "nonsense") == nil)
    }

    /// Only icons the build was made with can be worn.
    @Test func knowsWhichIconsABuildCarries() {
        let info: [String: Any] = ["CFBundleIcons": ["CFBundleAlternateIcons": ["AppIcon-Kana": 1, "AppIcon-Custom-ab12cd34": 1]]]
        #expect(IconShelf.installed(in: info) == ["AppIcon-Kana", "AppIcon-Custom-ab12cd34"])
        #expect(IconShelf.installed(in: [:]).isEmpty)
        #expect(IconShelf.installed(in: nil).isEmpty)
    }

    /// The export folder holds exactly the icons on the phone.
    @Test func deletedIconsLeaveTheExportFolder() {
        let strays = IconShelf.strays(in: ["a.png", "b.png", "notes.txt"], keeping: ["a.png"])
        #expect(strays == ["b.png"])
    }
}

/// No white on white or black on black: every ink must read on the ground and the surfaces.
@Suite("Theme")
@MainActor
struct ThemeTests {
    private func luminance(_ colour: Color, _ style: UIUserInterfaceStyle) -> Double {
        let resolved = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { let c = Double(c); return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let x = luminance(a, style), y = luminance(b, style)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: [0, 1])
    func inksReadOnTheirGrounds(_ which: Int) {
        let t = [Theme.standard, Theme.paradox][which]
        for style in [UIUserInterfaceStyle.dark, .light] {
            for ground in [t.ground, t.surface, t.surface2] {
                #expect(contrast(t.head, ground, style) >= 4.5)
                #expect(contrast(t.body, ground, style) >= 4.5)
                #expect(contrast(t.muted, ground, style) >= 3)
            }
            #expect(contrast(t.onHead, t.head, style) >= 4.5)
        }
    }
}
