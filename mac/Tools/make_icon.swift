// Draws the app icon in code: a microphone in the stripe's dark, sound coming in green, and three lines of text going
// out, the last one shorter, which is the whole app: you speak, it writes. The version sits under it (version-visible.md).
//   swift Tools/make_icon.swift <out.iconset> <version>
import AppKit

let out = CommandLine.arguments[1]
let version = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let u = s / 100
        let green = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 1)
        let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1)
        let light = NSColor(calibratedWhite: 0.85, alpha: 1)
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4 * u, y: 4 * u, width: 92 * u, height: 92 * u), xRadius: 20 * u, yRadius: 20 * u).fill()

        // the microphone
        amber.setFill()
        NSBezierPath(roundedRect: NSRect(x: 18 * u, y: 46 * u, width: 16 * u, height: 32 * u), xRadius: 8 * u, yRadius: 8 * u).fill()
        amber.setStroke()
        let cup = NSBezierPath()
        cup.appendArc(withCenter: NSPoint(x: 26 * u, y: 56 * u), radius: 13 * u, startAngle: 200, endAngle: 340)
        cup.move(to: NSPoint(x: 26 * u, y: 43 * u)); cup.line(to: NSPoint(x: 26 * u, y: 35 * u))
        cup.move(to: NSPoint(x: 19 * u, y: 35 * u)); cup.line(to: NSPoint(x: 33 * u, y: 35 * u))
        cup.lineWidth = 3.5 * u; cup.lineCapStyle = .round; cup.stroke()

        // the sound coming in
        green.setStroke()
        for i in 1...2 {
            let w = NSBezierPath()
            w.appendArc(withCenter: NSPoint(x: 38 * u, y: 62 * u), radius: CGFloat(5 + i * 5) * u, startAngle: -40, endAngle: 40)
            w.lineWidth = 3 * u; w.lineCapStyle = .round; w.stroke()
        }

        // the text going out
        light.setFill()
        for (i, len) in [30, 30, 18].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 56 * u, y: CGFloat(70 - i * 12) * u, width: CGFloat(len) * u, height: 5 * u),
                         xRadius: 2.5 * u, yRadius: 2.5 * u).fill()
        }

        if s >= 32 {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15 * u, weight: .semibold), .foregroundColor: light]
            let t = NSAttributedString(string: "v\(version)", attributes: attrs)
            let w = t.size()
            t.draw(at: NSPoint(x: (s - w.width) / 2, y: 11 * u))
        }
        return true
    }
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
