import AppKit

// v61, Marko, 21.11.2026: "F one, this blob should appear. Not the big blob, this more transparent thing going in and out
// ... in the middle of the screen, oval, transparent, just say recording, transcribing, and disappears ... in both screens
// ... momentarily without any delays, and stopping is also momentarily. And fading is momentarily."
//
// One oval, see-through, in the middle of EVERY screen: "Recording" from the F1 press (the Go sound included), "Transcribing"
// while the take is written down, gone when it is typed. It appears at once (no fade in), leaves in 0.1 s, takes no mouse
// and no focus. The state is read from the Stripe 33 times a second, and the key press asks for it directly.
final class TakeHUD {
    static let shared = TakeHUD()
    private weak var stripe: Stripe?
    private var panels: [NSPanel] = []
    private var labels: [NSTextField] = []
    private var dots: [NSView] = []
    private var key = ""
    private var showing: String?
    private var timer: Timer?
    private var hideToken = 0

    func start(_ s: Stripe) {
        stripe = s
        let t = Timer(timeInterval: 1.0 / 33, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard let s = stripe else { return }
        let want: (String, NSColor)?
        if s.recorder.recording { want = s.recorder.paused ? ("Paused", Ink.grey) : ("Recording", Ink.red) }
        else if s.goPending { want = ("Recording", Ink.red) }
        else if s.busy { want = ("Transcribing", Ink.amber) }
        else { want = nil }
        guard let (text, colour) = want else {
            if showing != nil { showing = nil; fadeOut() }
            return
        }
        if showing == text { return }
        showing = text
        hideToken += 1
        build()
        for (i, p) in panels.enumerated() {
            labels[i].stringValue = text
            dots[i].layer?.backgroundColor = colour.cgColor
            p.alphaValue = 1
            p.orderFrontRegardless()
        }
    }

    private func fadeOut() {
        hideToken += 1
        let token = hideToken
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.1
            for p in panels { p.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self, token == self.hideToken else { return }
            for p in self.panels { p.orderOut(nil) }
        })
    }

    /// one oval panel per screen, rebuilt when the screens change
    private func build() {
        let k = NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: "|")
        if k == key, !panels.isEmpty { return }
        key = k
        for p in panels { p.orderOut(nil) }
        panels = []; labels = []; dots = []
        let w: CGFloat = 230, h: CGFloat = 64
        for sc in NSScreen.screens {
            let p = NSPanel(contentRect: NSRect(x: sc.frame.midX - w / 2, y: sc.frame.midY - h / 2, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.ignoresMouseEvents = true; p.hidesOnDeactivate = false
            let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.5).cgColor
            v.layer?.cornerRadius = h / 2
            let dot = NSView(frame: NSRect(x: 26, y: h / 2 - 8, width: 16, height: 16))
            dot.wantsLayer = true; dot.layer?.cornerRadius = 8
            let l = NSTextField(labelWithString: "")
            l.frame = NSRect(x: 54, y: h / 2 - 13, width: w - 70, height: 26)
            l.font = .systemFont(ofSize: 20, weight: .semibold)
            l.textColor = NSColor(white: 1, alpha: 0.95)
            v.addSubview(dot); v.addSubview(l)
            p.contentView = v
            panels.append(p); labels.append(l); dots.append(dot)
        }
    }
}
