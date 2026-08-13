// node/test-side access to the same recogniser the app uses: ocr-cli <pdf> [out.json] [maxPages]
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let data = try! Data(contentsOf: URL(fileURLWithPath: a[1]))
let out = a.count > 2 ? a[2] : "-"
guard let prov = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(prov) else { exit(1) }
let n = a.count > 3 ? min(Int(a[3])!, pdf.numberOfPages) : pdf.numberOfPages
let t0 = Date()
let json = OCR.json(data: data, pages: Array(1...n)) { d, t in
  if d % 20 == 0 { FileHandle.standardError.write("  \(d)/\(t)\n".data(using: .utf8)!) }
}
FileHandle.standardError.write("ocr \(n) pages in \(Int(Date().timeIntervalSince(t0)*1000))ms\n".data(using: .utf8)!)
if out == "-" { print(json) } else { try! json.write(toFile: out, atomically: true, encoding: .utf8) }
