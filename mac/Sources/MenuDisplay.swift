// v33 THE DISPLAY IN THE MENU BAR, v37 ALWAYS THERE (Marko, 16.11.2026: "I want that this menu bar item is always there. I cannot
// detach it ... application can be quick menu bar item. So we are discarding small display at the top of the blob. Blob can be
// closed and application stay open. To close application one needs to click on this status line in the menu bar").
// The display is ONE view (BandField, the status line): it lives only in this status item's button. Same text, same states,
// same hairline meter. The item is as long as the words (variable length), so nothing is cut; if the menu bar is crowded
// macOS may hide it. A click opens the menu: Show / Hide the blob, Settings, History, Quit (Quit only from here).
// Place: the autosaveName and a preferred position near 0 ask for the slot nearest the system icons and the clock.
import AppKit

final class MenuDisplay: NSObject {
    static let shared = MenuDisplay()
    static let name = "VoiceToTextBar"
    private var item: NSStatusItem?
    private var visObs: NSKeyValueObservation?
    private var timer: Timer?
    private var shownWidth: CGFloat = 0
    private var savedMenu: NSMenu?
    private var copyMode = false
    private weak var stripe: Stripe?

    func setup(_ s: Stripe) {
        stripe = s
        DispatchQueue.main.async { self.enable() }       // the globals (menuBar) exist once main.swift has run
    }

    private func enable() {
        guard let s = stripe else { return }
        let d = UserDefaults.standard
        d.set(true, forKey: "NSStatusItem Visible " + MenuDisplay.name)       // a Cmd-drag out of the bar is undone at the next start
        let key = "NSStatusItem Preferred Position " + MenuDisplay.name
        if d.object(forKey: key) == nil { d.set(0, forKey: key) }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.autosaveName = MenuDisplay.name
        it.isVisible = true
        it.button?.setAccessibilityLabel("Vox to Txt (Mantra) display")
        savedMenu = menuBar.makeMenu()
        it.menu = savedMenu
        item = it
        // always there: if it is taken out of the bar, it comes back
        visObs = it.observe(\.isVisible, options: [.new]) { i, _ in
            if !i.isVisible { DispatchQueue.main.async { i.isVisible = true } }
        }
        guard let button = it.button else { return }
        let line = s.face.line
        line.removeFromSuperview()
        line.passThrough = true; line.restrictHit = false
        button.addSubview(pipes, positioned: .below, relativeTo: nil)
        button.addSubview(line)
        HoverCard.attach(to: it) { [weak self] in self?.hoverContent() ?? HoverCard.Content(name: "Vox to Txt (Mantra)", what: "", state: "") }
        menuBar.item.isVisible = false              // its menu is on the display now
        layout()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.layout() }
        RunLoop.main.add(t, forMode: .common); timer = t
        appendLog("menu bar: the display is the menu-bar item (always there)")
        // test hook (--menu-shot): open the menu for a few seconds so it can be photographed, then close it again
        DistributedNotificationCenter.default().addObserver(forName: .init("com.mantra.voicetotext.openmenu"), object: nil, queue: .main) { [weak self] n in
            guard let it = self?.item else { return }
            let secs = (n.object as? String).flatMap(Double.init) ?? 6
            let t = Timer(timeInterval: secs, repeats: false) { _ in it.menu?.cancelTracking() }
            RunLoop.main.add(t, forMode: .common)
            it.button?.performClick(nil)
        }
    }

    private let pipes = HoverCard.PipesView(frame: .zero)

    /// the hover card (kit menubar-hover)
    func hoverContent() -> HoverCard.Content {
        let r = stripe?.recorder
        let secs = Int(r?.elapsed ?? 0)
        let (st, col): (String, NSColor) = (r?.recording ?? false) ? ((r?.paused ?? false) ? ("PAUSED", .systemOrange) : ("RECORDING", .systemRed))
            : (stripe?.busy ?? false) ? ("WRITING", .systemYellow) : ("READY", .systemGreen)
        let d = UserDefaults.standard
        func eng(_ l: String) -> String { let id = d.string(forKey: "engine_" + l) ?? "assemblyai"; return Catalog.byId(id).map { Stats.name($0, l) } ?? id }
        var lines = ["English: " + eng("en"), "Croatian: " + eng("hr"), "Route: " + (Frankfurt.badge == "FRA" ? "Frankfurt relay" : "direct")]
        if r?.recording ?? false { lines.insert(String(format: "Take: %d:%02d", secs / 60, secs % 60), at: 0) }
        return HoverCard.Content(name: "Vox to Txt (Mantra)", what: "Press F1, talk, the text is typed at the cursor", state: st, stateColor: col, lines: lines)
    }

    // v45 (Marko, 17.11.2026: "if the text do not land ... I want to then click on menu bar item, and then it copies the text, and
    // second click lands as normal click"): while the take did not land the item has no menu and its click copies that take's
    // text; once copied (or a new take lands) the menu is back and the next click opens it
    private func syncCopyMode() {
        guard let s = stripe, let it = item, let b = it.button else { return }
        let want = s.unlanded && !s.lastText.isEmpty
        guard want != copyMode else { return }
        copyMode = want
        if want {
            it.menu = nil
            b.target = self; b.action = #selector(copyClicked)
            b.sendAction(on: .leftMouseDown)
            appendLog("menu bar: the take did not land: the first click copies it")
        } else {
            b.target = nil; b.action = nil
            it.menu = savedMenu
        }
    }
    @objc func copyClicked() { stripe?.copyLast() }

    /// the item is as wide as the words (the band is the words plus 16 pt), the band 18 pt high in the 22 pt bar
    private func layout() {
        syncCopyMode()
        guard let s = stripe, let it = item, let button = it.button else { return }
        let line = s.face.line
        let words = line.stringValue.isEmpty ? 0 : ceil(line.attributedStringValue.size().width) + 16
        let w = max(words, 8)
        if w != shownWidth { shownWidth = w; it.length = w + 6 + 8 }
        let h = max(18, button.bounds.height - 4)
        pipes.frame = button.bounds
        line.frame = NSRect(x: 7, y: (button.bounds.height - h) / 2, width: w, height: h)
    }
}
