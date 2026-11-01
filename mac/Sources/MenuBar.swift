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

final class MenuBar: NSObject {
    enum State: Equatable { case idle, recording(Int), paused(Int), processing }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var state: State?
    private var timer: Timer?

    static let red = NSColor(red: 0.93, green: 0.22, blue: 0.20, alpha: 1)
    static let yellow = NSColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)

    override init() {
        super.init()
        item.autosaveName = "voicetotext"
        item.button?.setAccessibilityLabel("Voice to Text (Mantra)")
        let menu = NSMenu()
        for (title, sel) in [("Show the blob", #selector(showBlob)), ("Settings…", #selector(settings)),
                             ("Transcription history", #selector(history))] {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: ""); m.target = self; menu.addItem(m)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Voice to Text (Mantra)", action: #selector(quit), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        item.menu = menu
        show(.idle)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.follow() }
        RunLoop.main.add(t, forMode: .common)            // it changes colour while a menu is open too
        timer = t
    }

    func follow() {
        let r = stripe.recorder
        let secs = Int(r.elapsed)
        show(r.recording ? (r.paused ? .paused(secs) : .recording(secs)) : stripe.busy ? .processing : .idle)
    }

    func show(_ s: State) {
        guard s != state, let b = item.button else { return }
        state = s
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
            b.toolTip = paused ? "Voice to Text: paused" : "Voice to Text: recording"
        case .idle, .processing:
            let colour: NSColor = s == .processing ? MenuBar.yellow : .tertiaryLabelColor
            b.attributedTitle = NSAttributedString(string: "VT", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy), .foregroundColor: colour, .kern: 0.5])
            b.toolTip = s == .processing ? "Voice to Text: writing it down" : "Voice to Text: ready (F1)"
        }
    }

    @objc func showBlob() { stripe.showQuietly(); stripe.panel.orderFrontRegardless() }
    @objc func settings() { stripe.openSettingsTab() }
    @objc func history() { stripe.openHistory() }
    @objc func quit() {
        if stripe.recorder.recording || stripe.busy { return }       // never while a take is open (as OFF)
        NSApp.terminate(nil)
    }
}
