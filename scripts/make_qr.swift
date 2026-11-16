// Writes docs/qr.png: a QR code for the Clackey demo page, made with Core Image (no dependencies).
// After writing, it reads the image back with Core Image's QR detector to confirm it scans.
//
//   swift scripts/make_qr.swift [url]

import AppKit
import CoreImage

let url = CommandLine.arguments.dropFirst().first ?? "https://aakocval.github.io/clackey/"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("docs/qr.png")

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(url.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let code = filter.outputImage!                       // 1 px per module, includes a quiet zone

// Scale up with hard edges so it stays crisp.
let scale: CGFloat = 16
let scaled = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
// White margin of 4 modules so phones scan it reliably, even on GitHub's dark theme.
let margin = scale * 3
let canvas = scaled.extent.insetBy(dx: -margin, dy: -margin)
let framed = scaled.composited(over: CIImage(color: .white).cropped(to: canvas))
let context = CIContext()
let cg = context.createCGImage(framed, from: canvas)!
let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
try png.write(to: out)

// Verify it decodes to exactly the URL.
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context,
                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let decoded = (detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString
guard decoded == url else {
    FileHandle.standardError.write("QR check failed: decoded \(decoded ?? "nothing")\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(out.path) (\(cg.width)px), scans to \(url)")
