import AppKit
import ApplicationServices

// v65, Marko, 22.11.2026: "this, what we call SpectralAnalyzer, needs to be on the screen when I'm entering the text. So where
// is the cursor? Blob comes to that screen."
//
// Which screen the bottom ellipse belongs on: the screen where the text will be typed. Each rule falls to the next when it gives
// nothing: (a) the insertion point of the focused text element (AXSelectedTextRange + AXBoundsForRange), (b) the frame of that
// focused element, (c) the focused window of the front app, (d) the screen with the mouse (the LAST fallback only).
// Accessibility reports top-left based points of the primary screen; AppKit is bottom-left: y = primaryHeight - y - height.
enum FocusScreen {
    /// AX rectangle (origin top-left of the primary screen) to an AppKit rectangle (origin bottom-left of the primary screen)
    static func appKitRect(fromAX r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.minY - r.height, width: r.width, height: r.height)
    }

    /// the index of the screen holding the rectangle's centre, else the one with the biggest overlap
    static func screenIndex(of r: CGRect, frames: [CGRect]) -> Int? {
        let c = CGPoint(x: r.midX, y: r.midY)
        if let i = frames.firstIndex(where: { $0.contains(c) }) { return i }
        var best: (Int, CGFloat)?
        for (i, f) in frames.enumerated() {
            let x = f.intersection(r)
            let a = x.isNull ? 0 : x.width * x.height
            if a > 0, a > (best?.1 ?? 0) { best = (i, a) }
        }
        return best?.0
    }

    private static func rect(_ el: AXUIElement, pos: String = kAXPositionAttribute, size: String = kAXSizeAttribute) -> CGRect? {
        guard let p = TextTarget.attr(el, pos), let s = TextTarget.attr(el, size),
              CFGetTypeID(p as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(s as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var o = CGPoint.zero, z = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &o), AXValueGetValue(s as! AXValue, .cgSize, &z), z.width > 0 || z.height > 0 else { return nil }
        return CGRect(origin: o, size: z)
    }

    /// (a) the insertion point of a text element, in AX coordinates
    private static func caret(_ el: AXUIElement) -> CGRect? {
        guard let v = TextTarget.attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(v as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var rng = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &rng) else { return nil }
        for probe in [CFRange(location: rng.location, length: 1), CFRange(location: max(0, rng.location - 1), length: 1), rng] {
            var p = probe
            guard let pv = AXValueCreate(.cfRange, &p) else { continue }
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, pv, &out) == .success,
               let o = out, CFGetTypeID(o) == AXValueGetTypeID() {
                var r = CGRect.zero
                if AXValueGetValue(o as! AXValue, .cgRect, &r), r.width >= 0, r.height > 0, r.origin.x.isFinite { return r }
            }
        }
        return nil
    }

    /// the screen for the ellipse and the rule that decided it ("a" ... "d")
    static func resolve() -> (screen: NSScreen, index: Int, rule: String) {
        let screens = NSScreen.screens
        let frames = screens.map { $0.frame }
        let ph = frames.first?.height ?? 0
        func found(_ ax: CGRect?, _ rule: String) -> (NSScreen, Int, String)? {
            guard let ax, let i = screenIndex(of: appKitRect(fromAX: ax, primaryHeight: ph), frames: frames) else { return nil }
            return (screens[i], i, rule)
        }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.25)
        if let f = TextTarget.element(TextTarget.attr(sys, kAXFocusedUIElementAttribute)), TextTarget.pid(f) != getpid() {
            AXUIElementSetMessagingTimeout(f, 0.25)
            if let r = found(caret(f), "a: insertion point") { return r }
            if let r = found(rect(f), "b: focused element") { return r }
        }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.25)
            if let w = TextTarget.element(TextTarget.attr(ax, kAXFocusedWindowAttribute)), let r = found(rect(w), "c: focused window") { return r }
        }
        let m = NSEvent.mouseLocation
        let i = frames.firstIndex { NSMouseInRect(m, $0, false) } ?? 0
        return (screens[i], i, "d: mouse (last fallback)")
    }
}
