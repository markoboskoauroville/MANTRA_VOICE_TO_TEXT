// v5: VT IN THE MENU BAR (Marko, 1.11.2026: "an icon for the menu bar for this application. It will just be a simple
// text V and T. I need to see the status of what's going on: grayed out, nothing is going on; when it's recording, red;
// when it's processing the recording, yellow; when it pastes, gray again").
// The state is read from the stripe ten times a second, so no road through the app can leave it the wrong colour:
//   red     a take records (not paused)
//   yellow  a take is written down, corrected or typed, or STYLE works (busy)
//   grey    anything else (ready, paused, after the paste)
// v6 (Marko, 1.11.2026: "While I am recording ... this VT icon on the bar should become a stopwatch, red stopwatch, which
// is counting minutes of my talking"): while a take is open VT gives way to a stopwatch and the take's time, m:ss,
// red while it records, grey and standing still while paused (the take's own clock, which stops on pause).
// A click opens a small menu: the blob, ⚙, the history, Quit. The place is kept (autosaveName, MANTRA_MANIFEST swift-apps.md).
import AppKit

final class MenuBar: NSObject, NSMenuDelegate {
    enum State: Equatable { case idle, recording(Int), paused(Int), processing }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var state: State?
    private var shownBadge = ""
    private var checkTimer: Timer?
    private var timer: Timer?

    static let red = NSColor(red: 0.93, green: 0.22, blue: 0.20, alpha: 1)
    static let yellow = NSColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)

    override init() {
        super.init()
        item.autosaveName = "voicetotext"
        item.button?.setAccessibilityLabel("Vox to Txt (Mantra)")
        item.menu = makeMenu()
        show(.idle)
        item.isVisible = false                           // v37: the display item carries the menu
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.follow() }
        RunLoop.main.add(t, forMode: .common)            // it changes colour while a menu is open too
        timer = t
        // v22: the Frankfurt badge (FRA / DIR) next to VT; the relay is asked every 20 s, off the main thread
        let c = Timer(timeInterval: 20, repeats: true) { _ in DispatchQueue.global().async { Frankfurt.backgroundCheck() } }
        RunLoop.main.add(c, forMode: .common); checkTimer = c
        DispatchQueue.global().async { _ = Frankfurt.reachable(force: true) }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.mantra.voicetotext.toast"), object: nil, queue: .main) { n in
            if let t = n.object as? String { Toast.show(t, good: !t.hasPrefix("Direct")) }      // test hook: --hear ... --toast
        }
    }

    /// v33: the same menu for the VT icon and for the display in the menu bar (MenuDisplay)
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // v38 (Marko, 16.11.2026: "checkmarks for 4 options: English, Croatian, Correction, Styling"): the dictation language
        // (the same hearLang as the blob's [EN], with AUTO because the app has it) and the two quick switches of ⚙
        for (title, tag, sel) in [("English", 11, #selector(pickLang(_:))), ("Croatian", 12, #selector(pickLang(_:))),
                                  ("Auto (English and Croatian)", 13, #selector(pickLang(_:))),
                                  ("Correction", 14, #selector(toggleCorrection)), ("Styling", 15, #selector(toggleStyling))] {
            if tag == 14 { menu.addItem(.separator()) }
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: ""); m.target = self; m.tag = tag; menu.addItem(m)
        }
        menu.addItem(.separator())
        for (title, sel) in [("Show the blob", #selector(showBlob)), ("Settings…", #selector(settings)),
                             ("Transcription history", #selector(history))] {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: ""); m.target = self; menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.delegate = self
        for l in ["en", "hr"] { let m = NSMenuItem(title: "", action: nil, keyEquivalent: ""); m.isEnabled = false; m.tag = l == "en" ? 1 : 2; menu.addItem(m) }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Vox to Txt (Mantra)", action: #selector(quit), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        return menu
    }

    /// v24: the engines in use for English and Croatian, each with its median time and its stars
    func menuNeedsUpdate(_ menu: NSMenu) {
        let lang = HearEngine.current.lang
        for m in menu.items {
            switch m.tag {
            case 11: m.state = lang == "en" ? .on : .off
            case 12: m.state = lang == "hr" ? .on : .off
            case 13: m.state = lang == "auto" ? .on : .off
            case 14: m.state = StyleEngine.current != .off ? .on : .off
            case 15: m.state = Prefs.styleButtonOn ? .on : .off
            default: break
            }
        }
        if let m = menu.items.first(where: { $0.action == #selector(showBlob) }) { m.title = stripe.minimizedFrame == nil && stripe.panel.isVisible ? "Hide the blob" : "Show the blob" }
        for m in menu.items where m.tag == 1 || m.tag == 2 {
            let l = m.tag == 1 ? "en" : "hr"
            let id = UserDefaults.standard.string(forKey: "engine_" + l) ?? "assemblyai"
            if let s = Catalog.byId(id) { m.title = (l == "en" ? "English: " : "Croatian: ") + Stats.name(s, l) }
        }
    }

    func follow() {
        let r = stripe.recorder
        let secs = Int(r.elapsed)
        show(r.recording ? (r.paused ? .paused(secs) : .recording(secs)) : stripe.busy ? .processing : .idle)
    }

    func show(_ s: State) {
        let badge = Frankfurt.badge
        guard s != state || badge != shownBadge, let b = item.button else { return }
        state = s; shownBadge = badge
        switch s {
        case .recording(let t), .paused(let t):
            let paused: Bool = { if case .paused = s { return true }; return false }()
            let colour: NSColor = paused ? .secondaryLabelColor : MenuBar.red
            let out = NSMutableAttributedString()
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [colour]))
            if let img = NSImage(systemSymbolName: "stopwatch.fill", accessibilityDescription: "recording")?.withSymbolConfiguration(cfg) {
                img.isTemplate = false
                let a = NSTextAttachment(); a.image = img
                a.bounds = NSRect(x: 0, y: -2.5, width: img.size.width, height: img.size.height)
                out.append(NSAttributedString(attachment: a))
            }
            out.append(NSAttributedString(string: String(format: " %d:%02d", t / 60, t % 60), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: colour]))
            b.attributedTitle = out
            b.toolTip = paused ? "Vox to Txt: paused" : "Vox to Txt: recording"
        case .idle, .processing:
            let colour: NSColor = s == .processing ? MenuBar.yellow : MenuBar.red
            let t = NSMutableAttributedString(string: "VT", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy), .foregroundColor: colour, .kern: 0.5])
            t.append(NSAttributedString(string: " " + badge, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: badge == "FRA" ? Host.green : Host.gold, .baselineOffset: 1]))
            b.attributedTitle = t
            b.setAccessibilityLabel("Vox to Txt (Mantra), route " + (badge == "FRA" ? "Frankfurt" : "direct"))
            b.toolTip = (s == .processing ? "Vox to Txt: writing it down" : "Vox to Txt: ready (F1)") + (badge == "FRA" ? " · route: Frankfurt" : " · route: direct")
        }
    }

    @objc func showBlob() {
        if stripe.minimizedFrame == nil && stripe.panel.isVisible { stripe.pinned = false; stripe.minimizeStripe() }
        else { stripe.showQuietly(); stripe.panel.orderFrontRegardless() }
    }
    /// everything that shows the choice follows at once: the blob, the status text, ⚙
    private func changed() {
        stripe.refresh()
        if !stripe.recorder.recording && !stripe.busy { stripe.ready() } else if stripe.recorder.recording { stripe.showListening() }
        stripe.settings?.paintChoices()
    }
    @objc func pickLang(_ m: NSMenuItem) {
        HearEngine.setLang(m.tag == 11 ? "en" : m.tag == 12 ? "hr" : "auto")
        appendLog("menu: language \(HearEngine.current.lang)")
        changed()
    }
    @objc func toggleCorrection() {
        if StyleEngine.current != .off { StyleEngine.current = .off }
        else { StyleEngine.current = StyleEngine(rawValue: UserDefaults.standard.string(forKey: "styleLastOn") ?? "") ?? .haiku }
        appendLog("menu: correction \(StyleEngine.current.title)")
        changed()
    }
    @objc func toggleStyling() {
        Prefs.styleButtonOn.toggle()
        appendLog("menu: styling \(Prefs.styleButtonOn ? "on" : "off")")
        changed()
    }
    @objc func settings() { stripe.openSettingsTab() }
    @objc func history() { stripe.openHistory() }
    @objc func quit() {
        if stripe.recorder.recording || stripe.busy { return }       // never while a take is open (as OFF)
        NSApp.terminate(nil)
    }
}
