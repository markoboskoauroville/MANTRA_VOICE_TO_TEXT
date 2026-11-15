// v22 (Marko, 15.11.2026: "How will I know that my voice to text is now going through Frankfurt? ... I don't see anywhere the
// indication."): a small toast at the top right of the main screen for about 2 s after every take, saying the route:
// "Frankfurt · Groq turbo · 1.2 s" or "Direct — Frankfurt did not answer". It never takes focus and never blocks the mouse.
import AppKit

enum Toast {
    private static var panel: NSPanel?
    private static var gen = 0
    /// true when the last line is a Frankfurt one (green), false for direct (amber)
    static var good = true

    static func line(_ h: HearEngine, seconds: Double) -> String {
        let r = Hear.route ?? ""
        let t = String(format: "%.1f s", seconds)
        if r.hasPrefix("Frankfurt") { good = true; return "Frankfurt · \(h.spec.short) · \(t)" }
        good = false
        if r.hasPrefix("direct (Frankfurt") { return "Direct — Frankfurt did not answer · \(h.spec.short) · \(t)" }
        if r == "direct" { return "Direct — Frankfurt is off · \(h.spec.short) · \(t)" }
        if r == "this Mac" { return "This Mac · \(h.spec.short) · \(t)" }
        return "\(h.spec.short) · \(t)"
    }

    static func show(_ text: String, good: Bool, seconds: Double = 2.2) {
        DispatchQueue.main.async {
            gen += 1; let mine = gen
            panel?.orderOut(nil)
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 15, weight: .semibold); label.textColor = Host.ink
            label.setAccessibilityIdentifier("routeToast"); label.setAccessibilityLabel("Route: " + text)
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            dot.wantsLayer = true; dot.layer?.cornerRadius = 5; dot.layer?.backgroundColor = (good ? Host.green : Host.gold).cgColor
            let size = label.fittingSize
            let w = size.width + 54, h = size.height + 24
            let box = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            box.wantsLayer = true; box.layer?.cornerRadius = 14; box.layer?.backgroundColor = Host.bg.withAlphaComponent(0.96).cgColor
            box.layer?.borderWidth = 1.5; box.layer?.borderColor = (good ? Host.green : Host.gold).cgColor
            dot.frame.origin = NSPoint(x: 16, y: h / 2 - 5); label.frame = NSRect(x: 36, y: 12, width: size.width + 2, height: size.height)
            box.addSubview(dot); box.addSubview(label)
            let scr = NSScreen.screens.first ?? NSScreen.main!        // the MacBook screen (the menu bar's), never the BenQ by choice
            let vis = scr.visibleFrame
            let p = NSPanel(contentRect: NSRect(x: vis.maxX - w - 16, y: vis.maxY - h - 10, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .statusBar
            p.ignoresMouseEvents = true; p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = box; p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 1 })
            panel = p
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                guard mine == gen else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }, completionHandler: { if mine == gen { p.orderOut(nil) } })
            }
        }
    }
}
