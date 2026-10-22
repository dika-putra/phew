// Draws the Phew logo: App/AppIcon.icns and docs/banner-{light,dark}.png.
// Run from the repo root: swift scripts/make-icons.swift
import AppKit

let bg = NSColor(srgbRed: 0x1E / 255, green: 0x22 / 255, blue: 0x29 / 255, alpha: 1)
let mint = NSColor(srgbRed: 0x7C / 255, green: 0xF5 / 255, blue: 0xC8 / 255, alpha: 1)

/// The logo on a 128x128 grid (y down), as in the chosen concept I.
func drawLogo() {
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 128, height: 128), xRadius: 28, yRadius: 28).fill(with: bg)
    func stroke(_ width: CGFloat, _ alpha: CGFloat, _ build: (NSBezierPath) -> Void) {
        let p = NSBezierPath()
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        build(p)
        mint.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }
    stroke(8, 1) { p in
        p.move(to: NSPoint(x: 30, y: 46)); p.line(to: NSPoint(x: 54, y: 64)); p.line(to: NSPoint(x: 30, y: 82))
    }
    stroke(8, 1) { p in
        p.move(to: NSPoint(x: 62, y: 86)); p.line(to: NSPoint(x: 82, y: 86))
        p.curve(to: NSPoint(x: 92, y: 68), controlPoint1: NSPoint(x: 96, y: 86), controlPoint2: NSPoint(x: 100, y: 74))
        p.curve(to: NSPoint(x: 84, y: 74), controlPoint1: NSPoint(x: 86, y: 64), controlPoint2: NSPoint(x: 80, y: 70))
    }
    stroke(5, 0.6) { p in
        p.move(to: NSPoint(x: 88, y: 50)); p.line(to: NSPoint(x: 104, y: 50))
        p.move(to: NSPoint(x: 94, y: 38)); p.line(to: NSPoint(x: 108, y: 38))
    }
}

extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}

/// Renders into a bitmap of `width` x `height` pixels with a flipped (y down) context.
func png(width: Int, height: Int, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    ctx.cgContext.translateBy(x: 0, y: CGFloat(height))
    ctx.cgContext.scaleBy(x: 1, y: -1)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func logo(at origin: CGPoint, size: CGFloat) {
    let t = NSAffineTransform()
    t.translateX(by: origin.x, yBy: origin.y)
    t.scale(by: size / 128)
    NSGraphicsContext.saveGraphicsState()
    t.concat()
    drawLogo()
    NSGraphicsContext.restoreGraphicsState()
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appending(path: "Phew-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        // macOS icon grid: the artwork fills the central 824 of 1024, the rest stays transparent.
        let inset = CGFloat(px) * 100 / 1024
        let data = png(width: px, height: px) { logo(at: CGPoint(x: inset, y: inset), size: CGFloat(px) - 2 * inset) }
        try data.write(to: iconset.appending(path: "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "App/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

// Banner 1280x320 pt, written at 2x.
for dark in [false, true] {
    let data = png(width: 2560, height: 640) {
        let t = NSAffineTransform()
        t.scale(by: 2)
        t.concat()
        (dark ? NSColor(srgbRed: 0x0D / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1) : .white).setFill()
        NSRect(x: 0, y: 0, width: 1280, height: 320).fill()
        logo(at: CGPoint(x: 64, y: 64), size: 192)
        let word: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 96, weight: .semibold),
            .foregroundColor: dark ? NSColor.white : bg,
        ]
        let tag: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28),
            .foregroundColor: dark ? NSColor(srgbRed: 0x91 / 255, green: 0x98 / 255, blue: 0xA1 / 255, alpha: 1)
                : NSColor(srgbRed: 0x57 / 255, green: 0x60 / 255, blue: 0x6A / 255, alpha: 1),
        ]
        ("phew" as NSString).draw(at: NSPoint(x: 304, y: 72), withAttributes: word)
        ("Free up disk space from dev caches, builds, and SDKs on macOS." as NSString)
            .draw(at: NSPoint(x: 308, y: 206), withAttributes: tag)
    }
    try data.write(to: URL(fileURLWithPath: "docs/banner-\(dark ? "dark" : "light").png"))
}
print("wrote App/AppIcon.icns, docs/banner-light.png, docs/banner-dark.png")
