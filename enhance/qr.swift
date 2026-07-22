// QR generator — native CoreImage, zero dependencies.
// usage: swift qr.swift "<text>" <out.png>
import Foundation
import CoreImage

let args = CommandLine.arguments
guard args.count == 3, let data = args[1].data(using: .utf8) else {
    FileHandle.standardError.write("usage: swift qr.swift <text> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(data, forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 14, y: 14))
let ctx = CIContext()
try! ctx.writePNGRepresentation(of: image, to: URL(fileURLWithPath: args[2]),
    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
