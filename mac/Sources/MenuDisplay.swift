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
        s.face.grip.isHidden = true
        menuBar.item.isVisible = false              // its menu is on the display now
        shownWidth = 0
        layout()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.layout() }
        RunLoop.main.add(t, forMode: .common); timer = t
        appendLog("menu bar: the display is in the menu bar")
    }

    private func disable() {
        timer?.invalidate(); timer = nil
        guard let s = stripe, item != nil else { return }
        item?.isVisible = false
        let line = s.face.line
        line.passThrough = false
        line.removeFromSuperview()
        s.face.addSubview(line)
        s.face.placeLine(below: Prefs.lineBelow)
        s.face.grip.isHidden = false
        menuBar.item.isVisible = true
        appendLog("menu bar: the display is back on the blob")
    }

    /// the item is as wide as the words (the band is the words plus 16 pt), the band 18 pt high in the 22 pt bar
    private func layout() {
        guard let s = stripe, let it = item, let button = it.button else { return }
        let line = s.face.line
        let words = line.stringValue.isEmpty ? 0 : ceil(line.attributedStringValue.size().width) + 16
        let w = max(words, 8)
        if w != shownWidth { shownWidth = w; it.length = w + 6 }
        let h = max(18, button.bounds.height - 4)
        line.frame = NSRect(x: 3, y: (button.bounds.height - h) / 2, width: w, height: h)
    }
}
