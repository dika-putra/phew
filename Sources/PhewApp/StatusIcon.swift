import AppKit

/// The menu bar version of the logo: the prompt chevron and the cursor that curls like a breath.
/// A template image, so macOS draws it black or white to match the menu bar.
enum StatusIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let p = NSBezierPath()
            p.lineWidth = 2
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: 2, y: 3)); p.line(to: NSPoint(x: 7, y: 8)); p.line(to: NSPoint(x: 2, y: 13))
            p.move(to: NSPoint(x: 9, y: 15)); p.line(to: NSPoint(x: 14, y: 15))
            p.curve(to: NSPoint(x: 16, y: 10), controlPoint1: NSPoint(x: 18, y: 15), controlPoint2: NSPoint(x: 19, y: 11))
            NSColor.black.setStroke()
            p.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Phew"
        return image
    }
}
