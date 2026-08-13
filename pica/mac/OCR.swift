// Reading a script that was never typed — only photographed.
//
// Most scripts arrive as a text PDF, or as a scan somebody has already run through an
// OCR engine (There Will Be Blood, LA Confidential): the words are in the file, sitting
// invisibly on top of the picture, and the importer reads them like any other text.
//
// The Hateful Eight is neither. It is 168 photographs of paper — JBIG2 images, two fonts
// in the whole document (the cover), not one letter of text anywhere. Nothing to read.
//
// So we read it ourselves. Every Mac has a text recogniser built into the system, and it
// is a good one; this renders each page big enough for it to be sure, recognises it, and
// hands back exactly what a PDF's own text layer would have handed back — a string, a
// position, and a width, in the page's own points. From there the importer cannot tell
// the difference, which is the whole point: one importer, one set of rules, no second
// pipeline that drifts away from the first.
import Foundation
import Vision
import CoreGraphics
import ImageIO

enum OCR {

    // Big enough that the recogniser stops guessing. Measured on The Hateful Eight,
    // page 4, against four readings that are unambiguous on the paper —
    //     2.2×  HAMMER CLICR · (0S)      2.6×  HAMMER CLICR
    //     4.0×  (O5)                     5.0×  every one of them right
    // — so it is 5. Rendering that big costs about a tenth of a second a page and the
    // page is thrown away the moment it has been read; being wrong lasts forever.
    static let scale: CGFloat = 5.0

    // The size the doubtful pages are looked at a second time.
    static let secondLook: CGFloat = 3.2

    // Each page is rendered at full size before it is recognised, so the whole fleet is
    // in memory at once. Six at a time keeps that under half a gigabyte and still uses
    // every core the recogniser can keep busy.
    static let lanes = 6

    /// Recognise the given 1-based pages of a PDF.
    /// Returns one dictionary per page, ready to be JSON-encoded for the page:
    ///   { "page": n, "width": W, "height": H, "items": [ {x, y, w, str} … ] }
    /// x/y/w are PDF points with y measured DOWN from the top of the page — the same
    /// space the importer already works in, so nothing downstream needs to know.
    static func recognise(data: Data, pages: [Int],
                          progress: ((Int, Int) -> Void)? = nil) -> [[String: Any]] {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else { return [] }

        var out = [Int: [String: Any]]()
        let lock = NSLock()
        var done = 0
        let total = pages.count

        // Several pages at once: recognition releases the CPU while the neural engine
        // works, so this scales nearly linearly, and the gate is what keeps the rendered
        // pages from piling up in memory faster than they are read.
        let gate = DispatchSemaphore(value: lanes)
        DispatchQueue.concurrentPerform(iterations: total) { i in
            gate.wait()
            defer { gate.signal() }
            let n = pages[i]
            var result: [String: Any]? = nil
            if let page = pdf.page(at: n) {
                result = read(page: page, number: n, scale: scale)
                // Where it is unsure, look again at a different size and keep whichever
                // reading it believes more. A photograph of type is not read the same way
                // twice: the size that turns "HAMMER CLICR" into "HAMMER CLICK" is also
                // the size that lost a character cue off the top of page 4, and the two
                // readings together lose neither.
                if let r = result, worstConfidence(r) < 0.6,
                   let second = read(page: page, number: n, scale: secondLook) {
                    result = merge(r, second)
                }
            }
            lock.lock()
            if let r = result { out[n] = r }
            done += 1
            progress?(done, total)
            lock.unlock()
        }
        return pages.compactMap { out[$0] }
    }

    // ── one page ───────────────────────────────────────────────────────────────────

    private static func items(_ page: [String: Any]) -> [[String: Any]] {
        page["items"] as? [[String: Any]] ?? []
    }

    private static func worstConfidence(_ page: [String: Any]) -> Double {
        items(page).map { ($0["conf"] as? Double) ?? 1 }.min() ?? 1
    }

    /// Two readings of the same page, line by line: whichever read a given row of type
    /// more confidently supplies that row, and a row only one of them saw is kept.
    /// Both readings measure the same paper, so their coordinates are directly comparable.
    private static func merge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        func rows(_ p: [String: Any]) -> [(y: Double, items: [[String: Any]])] {
            var out = [(y: Double, items: [[String: Any]])]()
            for it in items(p) {
                let y = (it["y"] as? Double) ?? 0
                if let i = out.firstIndex(where: { abs($0.y - y) <= 5 }) { out[i].items.append(it) }
                else { out.append((y, [it])) }
            }
            return out.sorted { $0.y < $1.y }
        }
        let ra = rows(a), rb = rows(b)
        var kept = [[String: Any]]()
        var usedB = Set<Int>()
        for row in ra {
            let match = rb.enumerated().first { abs($0.element.y - row.y) <= 5 }
            guard let m = match else { kept += row.items; continue }
            usedB.insert(m.offset)
            let ca = row.items.map { ($0["conf"] as? Double) ?? 1 }.min() ?? 1
            let cb = m.element.items.map { ($0["conf"] as? Double) ?? 1 }.min() ?? 1
            kept += (cb > ca ? m.element.items : row.items)
        }
        for (i, row) in rb.enumerated() where !usedB.contains(i) { kept += row.items }
        kept.sort {
            let ay = ($0["y"] as? Double) ?? 0, by = ($1["y"] as? Double) ?? 0
            if abs(ay - by) > 3 { return ay < by }
            return (($0["x"] as? Double) ?? 0) < (($1["x"] as? Double) ?? 0)
        }
        var out = a
        out["items"] = kept
        return out
    }

    private static func read(page: CGPDFPage, number: Int, scale: CGFloat) -> [String: Any]? {
        let box = page.getBoxRect(.mediaBox)
        // A page can be stored rotated; render it the way it is meant to be seen, or
        // every x and y comes back on its side.
        let rot = page.rotationAngle % 360
        let turned = rot == 90 || rot == 270
        let ptW = turned ? box.height : box.width
        let ptH = turned ? box.width : box.height
        guard ptW > 1, ptH > 1 else { return nil }

        let pxW = Int((ptW * scale).rounded())
        let pxH = Int((ptH * scale).rounded())
        // Colour, not grey, even though the paper is black and white: the same page
        // rendered grey came back missing a character cue and a whole word, and cost
        // two more misread lines. It is more memory for a page that lives half a second.
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Paper is white. Without this the page is drawn onto black and the recogniser
        // sees a photograph of nothing.
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        // A scan is a bilevel image — every pixel is pure black or pure white. Dropped
        // straight onto the grid it comes out jagged, and the recogniser reads jagged
        // type badly: it turned CLICK into CLICR, BEHIND into BERIND, and lost a whole
        // character cue off the top of a page. Smoothing the image on the way down puts
        // grey back into the strokes, and all three come back right.
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.mediaBox,
                                                 rect: CGRect(x: 0, y: 0, width: ptW, height: ptH),
                                                 rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        // A screenplay is full of names, dialect and shouted capitals — MAJ.WARREN,
        // "gonna'", O.B. Language correction "fixes" those into ordinary English and
        // quietly rewrites the script, so it stays off.
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        if #available(macOS 13.0, *) { req.automaticallyDetectsLanguage = false }
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([req]) }
        catch { return nil }

        var items = [[String: Any]]()
        for obs in (req.results ?? []) {
            guard let cand = obs.topCandidates(1).first else { continue }
            let s = cand.string
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let b = obs.boundingBox               // normalised, origin bottom-left
            let x = b.minX * ptW
            let w = b.width * ptW
            // The recogniser's box hugs the ink. Its bottom edge is the descender line
            // where there are descenders and the baseline where there are none, so it
            // is pulled up by a fixed fraction of the type size: consistent beats exact,
            // because the importer measures the SPACING of the rows, not their absolute
            // height, and an offset every line shares cancels out.
            let bottom = (1 - b.minY) * ptH
            let charW = w / CGFloat(max(s.count, 1))
            let size = charW / 0.6                // Courier advances 0.6 of its point size
            let y = bottom - size * 0.16

            items.append([
                "x": Double(round(x * 100) / 100),
                "y": Double(round(y * 100) / 100),
                "w": Double(round(w * 100) / 100),
                "str": s,
                "conf": Double(round(Double(cand.confidence) * 100) / 100),
                "h": Double(round(b.height * ptH * 100) / 100),
            ])
        }
        // ONE ROW, ONE BASELINE.
        // The recogniser often breaks a single typed line into two — "Rock 'fore it" and
        // "catches us." — and gives the two halves baselines a point apart. The importer
        // groups items into lines by their y, so a point of disagreement leaves the second
        // half standing alone in the middle of the page, belonging to no column: a hundred
        // of this script's lines arrived cut in half that way. They were typed on one row,
        // so they are given one row's y.
        items.sort { (($0["y"] as? Double) ?? 0) < (($1["y"] as? Double) ?? 0) }
        var i = 0
        while i < items.count {
            let y0 = (items[i]["y"] as? Double) ?? 0
            var j = i
            while j + 1 < items.count, (((items[j + 1]["y"] as? Double) ?? 0) - y0) <= 4 { j += 1 }
            let ys = (i...j).map { (items[$0]["y"] as? Double) ?? 0 }.sorted()
            let mid = ys[ys.count / 2]
            for k in i...j { items[k]["y"] = mid }
            i = j + 1
        }
        // Reading order: down the page, then across. Recognition returns roughly this
        // already, but "roughly" is how a cue ends up under its own dialogue.
        items.sort {
            let ay = $0["y"] as! Double, by = $1["y"] as! Double
            if abs(ay - by) > 3 { return ay < by }
            return ($0["x"] as! Double) < ($1["x"] as! Double)
        }
        return ["page": number, "width": Double(ptW), "height": Double(ptH), "items": items]
    }

    /// JSON for the page, or "[]".
    static func json(data: Data, pages: [Int], progress: ((Int, Int) -> Void)? = nil) -> String {
        let arr = recognise(data: data, pages: pages, progress: progress)
        guard let d = try? JSONSerialization.data(withJSONObject: arr, options: []),
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }
}
