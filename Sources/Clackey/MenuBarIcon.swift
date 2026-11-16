import AppKit

/// The menu bar icon: a tiny outlined MacBook fn key ("fn" top-right, globe bottom-left),
/// matching the app logo. Drawn as a template image so macOS tints it for light/dark menu
/// bars and dims it when sounds are off.
enum MenuBarIcon {
    static func fnKey() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let key = NSRect(x: 1.25, y: 1.25, width: 15.5, height: 15.5)
            let outline = NSBezierPath(roundedRect: key, xRadius: 3.6, yRadius: 3.6)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()

            // "fn", top-right
            let fn = NSAttributedString(string: "fn", attributes: [
                .font: NSFont.systemFont(ofSize: 6.6, weight: .bold),
                .foregroundColor: NSColor.black,
            ])
            let fs = fn.size()
            fn.draw(at: NSPoint(x: key.maxX - fs.width - 1.9, y: key.maxY - fs.height - 0.9))

            // globe, bottom-left
            let config = NSImage.SymbolConfiguration(pointSize: 5.0, weight: .semibold)
            if let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let g = globe.size
                globe.draw(in: NSRect(x: key.minX + 2.2, y: key.minY + 2.2, width: g.width, height: g.height))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clackey"
        return image
    }
}
