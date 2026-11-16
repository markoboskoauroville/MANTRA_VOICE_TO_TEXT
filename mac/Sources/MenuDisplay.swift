// v33 THE DISPLAY IN THE MENU BAR (Marko, 16.11.2026: "I want to have option in the settings that this bar which is small
// display bar become part of menu. When I select this option ... this bar will become permanent part of menu bar with all
// its text as it is now, even with Vumeter. and will be installed always next to the date so it is the first thing in
// line"). The display is ONE view (BandField, the status line of the blob): it is built once and only moved between its
// hosts, the blob's panel / the magnet's panel / this status item's button. Same text, same states, same hairline meter.
// The item is as long as the words (variable length), so nothing is cut; if the menu bar is crowded macOS may hide it
// (it hides the items that do not fit, left of the clock first, and the notch takes room on a MacBook).
// Place: the autosaveName and a preferred position near 0 ask for the slot nearest the system icons and the clock; a
// Cmd-drag by Marko is kept (the default is only written when there is none). Apps cannot be placed left of the clock by
// code; the slot nearest to it is the most that can be asked.
import AppKit

final class MenuDisplay: NSObject {
    static let shared = MenuDisplay()
    static let name = "VoiceToTextBar"
    private var item: NSStatusItem?
    private var timer: Timer?
    private var gripView: BarGrip?
    static let gripW: CGFloat = 16
    private var shownWidth: CGFloat = 0
    private weak var stripe: Stripe?

    func setup(_ s: Stripe) {
        stripe = s
        DispatchQueue.main.async { self.apply() }       // the globals (menuBar) exist once main.swift has run
    }

    func apply() {
        if Prefs.barInMenu { enable() } else { disable() }
    }

    private func enable() {
        guard let s = stripe else { return }
        if Magnet.shared.detached { Magnet.shared.attach() }
        if item == nil {
            let key = "NSStatusItem Preferred Position " + MenuDisplay.name
            if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(0, forKey: key) }
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            it.autosaveName = MenuDisplay.name
            it.button?.setAccessibilityLabel("Voice to Text (Mantra) display")
            let m = menuBar.makeMenu(); it.menu = m
            item = it
        }
        item?.isVisible = true
        guard let button = item?.button else { return }
        let line = s.face.line
        line.removeFromSuperview()
        line.passThrough = true; line.restrictHit = false
        button.addSubview(line)
        if gripView == nil { gripView = BarGrip() }
        button.addSubview(gripView!)
        menuBar.item.isVisible = false              // its menu is on the display now
        shownWidth = 0
        layout()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.layout() }
        RunLoop.main.add(t, forMode: .common); timer = t
        appendLog("menu bar: the display is in the menu bar")
    }

    /// the grip was dragged: the display leaves the menu bar and floats under the pointer (the MENU BAR switch puts it back)
    func beginDetach(at m: NSPoint) {
        guard let s = stripe else { return }
        Prefs.barInMenu = false
        s.face.line.passThrough = false
        Magnet.shared.detach(at: NSPoint(x: m.x - PANEL_W / 2, y: m.y - (LINE_H - 2) / 2))
        appendLog("menu bar: the display was dragged out by its grip")
    }
    func finishDetach() { apply() }

    private func disable() {
        timer?.invalidate(); timer = nil
        guard let s = stripe, item != nil else { return }
        item?.isVisible = false
        let line = s.face.line
        line.passThrough = false
        gripView?.removeFromSuperview()
        if !Magnet.shared.detached {            // dragged out by the grip: the display is already a floating panel of its own
            line.removeFromSuperview()
            s.face.addSubview(line)
            s.face.placeLine(below: Prefs.lineBelow)
        }
        menuBar.item.isVisible = true
        appendLog("menu bar: the display is back on the blob")
    }

    /// the item is as wide as the words (the band is the words plus 16 pt), the band 18 pt high in the 22 pt bar
    private func layout() {
        guard let s = stripe, let it = item, let button = it.button, !Magnet.shared.detached else { return }
        let line = s.face.line
        let words = line.stringValue.isEmpty ? 0 : ceil(line.attributedStringValue.size().width) + 16
        let w = max(words, 8)
        if w != shownWidth { shownWidth = w; it.length = w + 6 + MenuDisplay.gripW }
        let h = max(18, button.bounds.height - 4)
        gripView?.frame = NSRect(x: 3, y: (button.bounds.height - h) / 2, width: MenuDisplay.gripW, height: h)
        line.frame = NSRect(x: 3 + MenuDisplay.gripW, y: (button.bounds.height - h) / 2, width: w, height: h)
    }
}

// v36: the grab handle at the left end of the display in the menu bar. Mouse down and drag takes the display out of the
// menu bar into a floating one under the pointer; a plain click opens the menu. With Cmd held it lets the press through, so
// the system's Cmd-drag reordering of menu-bar items works from here too.
final class BarGrip: NSView {
    private var down = NSPoint.zero, last = NSPoint.zero, dragging = false
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? {
        if NSEvent.modifierFlags.contains(.command) { return nil }
        return frame.contains(p) ? self : nil
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .handle }
    override func accessibilityLabel() -> String? { "Move the display: drag it out of the menu bar" }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ r: NSRect) {
        NSColor(white: 0, alpha: 0.55).setFill()
        let plate = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6); plate.fill()
        NSColor(white: 0.95, alpha: 1).setFill()
        for x in [bounds.midX - 4, bounds.midX + 1.5] {
            NSBezierPath(roundedRect: NSRect(x: x, y: bounds.midY - 6, width: 2.5, height: 12), xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
    override func mouseDown(with e: NSEvent) { down = NSEvent.mouseLocation; last = down; dragging = false }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        if !dragging {
            guard hypot(m.x - down.x, m.y - down.y) > 3 else { return }
            dragging = true
            MenuDisplay.shared.beginDetach(at: m)
        } else if let w = Magnet.shared.display {
            w.setFrameOrigin(NSPoint(x: w.frame.origin.x + m.x - last.x, y: w.frame.origin.y + m.y - last.y))
        }
        last = m
    }
    override func mouseUp(with e: NSEvent) {
        if dragging { dragging = false; MenuDisplay.shared.finishDetach() }
        else { enclosingMenuItemButton?.performClick(nil) }
    }
    private var enclosingMenuItemButton: NSButton? { superview as? NSButton }
}
