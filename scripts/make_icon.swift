// Draws the Clackey logo with CoreGraphics and writes:
//   Resources/AppIcon.icns   (all macOS icon sizes)
//   docs/logo.png            (512 px, for the README)
//
//   swift scripts/make_icon.swift
//
// Design: a Space Black squircle, a black MacBook fn key (white "fn" + globe),
// and white sound waves coming off it.

import AppKit
import CoreGraphics
import Foundation


func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, in r: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([top, bottom]), start: CGPoint(x: r.midX, y: r.maxY),
                           end: CGPoint(x: r.midX, y: r.minY), options: [])
    ctx.restoreGState()
}

/// Draws the logo into a 1024×1024 coordinate space (origin bottom-left).
func drawLogo(_ ctx: CGContext) {
    // Space Black aluminium squircle (Apple grid: 824 pt body, ~185 pt corners, centered).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedRect(body, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, bodyPath, top: CGColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1),
         bottom: CGColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1), in: body)
    ctx.saveGState()
    ctx.addPath(roundedRect(body.insetBy(dx: 3, dy: 3), 182))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // MacBook-style key: low-profile black cap sitting in a slightly recessed well.
    let cx: CGFloat = 400, cy: CGFloat = 512
    let well = CGRect(x: cx - 190, y: cy - 190, width: 380, height: 380)
    ctx.saveGState()
    ctx.addPath(roundedRect(well, 64))
    ctx.setFillColor(CGColor(gray: 0.06, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    let key = well.insetBy(dx: 14, dy: 14).offsetBy(dx: 0, dy: 6)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: CGColor(gray: 0, alpha: 0.7))
    ctx.addPath(roundedRect(key, 54))
    ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, roundedRect(key, 54), top: CGColor(gray: 0.13, alpha: 1), bottom: CGColor(gray: 0.04, alpha: 1), in: key)
    // soft top-edge highlight, like light catching the key edge
    ctx.saveGState()
    ctx.addPath(roundedRect(key.insetBy(dx: 2, dy: 2), 52))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // The MacBook fn key: "fn" top-right, globe bottom-left, both white.
    let pad: CGFloat = 56
    let font = NSFont.systemFont(ofSize: 112, weight: .regular)
    let legend = NSAttributedString(string: "fn", attributes: [
        .font: font, .foregroundColor: NSColor(white: 0.96, alpha: 1),
    ])
    let line = CTLineCreateWithAttributedString(legend)
    let tb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: key.maxX - pad - tb.maxX, y: key.maxY - pad - tb.maxY)
    CTLineDraw(line, ctx)

    let globeSize: CGFloat = 118
    let config = NSImage.SymbolConfiguration(pointSize: globeSize, weight: .regular)
        .applying(.init(paletteColors: [NSColor(white: 0.96, alpha: 1)]))
    if let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        var rect = CGRect(origin: .zero, size: globe.size)
        if let cg = globe.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            let scale = globeSize / max(globe.size.width, globe.size.height)
            let size = CGSize(width: globe.size.width * scale, height: globe.size.height * scale)
            ctx.draw(cg, in: CGRect(x: key.minX + pad, y: key.minY + pad, width: size.width, height: size.height))
        }
    }

    // White sound waves, kept inside the squircle.
    ctx.saveGState()
    ctx.setLineCap(.round)
    let white = CGColor(gray: 0.97, alpha: 1)
    let origin = CGPoint(x: cx, y: cy)
    for (radius, width, alpha) in [(CGFloat(275), CGFloat(36), CGFloat(1.0)), (355, 34, 0.65), (432, 32, 0.35)] {
        ctx.setStrokeColor(white.copy(alpha: alpha)!)
        ctx.setLineWidth(width)
        ctx.addArc(center: origin, radius: radius, startAngle: -0.40, endAngle: 0.40, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawLogo(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try p.run()
p.waitUntilExit()

try fm.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try render(size: 512).write(to: root.appendingPathComponent("docs/logo.png"))
print("wrote \(icns.path) and docs/logo.png (exit \(p.terminationStatus))")
