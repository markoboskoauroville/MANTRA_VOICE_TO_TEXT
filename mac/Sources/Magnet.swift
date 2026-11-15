// v27, THE MAGNET (Marko, 15.11.2026: "voice to text has two parts, there is a small display at the top and the body I want
// to be able to long press the small display or the body ... and then they detach imagine like a magnet which gets
// deactivated and then I can move each piece separately and when I bring them together they again attach as two magnets
// because I want to have this small display around the screen available in front of my eyes and a big one somewhere on
// the side."). The two parts: the DISPLAY (the status line, BandField) and the BODY (the pill with the wave and the
// buttons). Attached, the display is a view in the body's panel, above or below the pill (Prefs.lineBelow). Detached, it is
// a panel of its own (DisplayPanel) and each part drags alone, anywhere, on any screen. A part brought within 24 pt of
// the other's slot shows a ghost of the slot and both glow; letting go there attaches them again, in the old order.
// Held still for 0.6 s on either part (the buttons too) = detach; the two glow, a soft click. State kept across launches.
import AppKit

/// a press held still for 0.6 s
final class LongPress {
    static let seconds = 0.6
    private var item: DispatchWorkItem?
    func begin(_ fire: @escaping () -> Void) {
        cancel()
        let w = DispatchWorkItem(block: fire); item = w
        DispatchQueue.main.asyncAfter(deadline: .now() + LongPress.seconds, execute: w)
    }
    func cancel() { item?.cancel(); item = nil }
}

final class DisplayPanel: NSPanel {
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect {
        var f = r
        guard let sc = BlobPanel.screen(for: r) else { return f }
        let v = sc.frame
        f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
        f.origin.x = min(max(f.origin.x, v.minX - f.width + 80), v.maxX - 80)
        return f
    }
}

/// the dashed outline of the slot where the display would sit
final class GhostView: NSView {
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
        BLUE.withAlphaComponent(0.18).setFill(); p.fill()
        BLUE.setStroke(); p.lineWidth = 1.5; p.setLineDash([5, 3], count: 2, phase: 0); p.stroke()
    }
}

final class Magnet: NSObject {
    static let shared = Magnet()
    static let snap: CGFloat = 24            // within this the parts snap together
    static let gap: CGFloat = 30             // a detached display steps this far from its slot, so it is seen to be free
    weak var stripe: Stripe?
    var display: DisplayPanel?
    var ghost: NSPanel?
    var near = false
    var didDrag = false                      // the press that is ending moved a part (a still press never attaches)
    var cueing = false
    private var observers: [NSObjectProtocol] = []
    private var visibleObs: NSKeyValueObservation?
    var detached: Bool { display != nil }

    /// the AX actions "Detach" and "Attach" on both parts (MANTRA_MANIFEST: every control reachable by Accessibility)
    static func axActions() -> [NSAccessibilityCustomAction] {
        [NSAccessibilityCustomAction(name: "Detach") { Magnet.shared.detach(); return true },
         NSAccessibilityCustomAction(name: "Attach") { Magnet.shared.attach(); return true }]
    }

    // MARK: geometry

    /// where the display sits when attached, in screen coordinates
    func slot() -> NSRect {
        guard let s = stripe else { return .zero }
        let p = s.panel.frame
        let y = Prefs.lineBelow ? p.minY : p.minY + PILL_H + 2
        return NSRect(x: p.minX, y: y, width: PANEL_W, height: LINE_H - 2)
    }

    // MARK: start

    func setup(_ s: Stripe) {
        stripe = s
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: s.panel, queue: .main) { [weak self] _ in self?.moved() })
        // the detached display goes and comes with the body (hidden after a take, back with F1)
        visibleObs = s.panel.observe(\.isVisible, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                guard let self, let d = self.display else { return }
                if p.isVisible { d.orderFrontRegardless() } else { d.orderOut(nil); self.ghost?.orderOut(nil) }
            }
        }
        for prefix in ["com.mantra.voicetotext", "com.mantra.markotranscribe"] {
            // test hooks (no mouse): userInfo action = detach | attach | drop; for drop: part = display | body, x, y = the
            // panel's lower-left corner in screen points (drop is a drag and a release there, so the snap rule applies)
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(prefix + ".magnet"), object: nil, queue: .main) { [weak self] n in
                guard let self else { return }
                let u = n.userInfo ?? [:]
                switch u["action"] as? String ?? "" {
                case "detach": self.detach()
                case "attach": self.attach()
                case "drop":
                    guard let x = (u["x"] as? NSNumber)?.doubleValue, let y = (u["y"] as? NSNumber)?.doubleValue else { return }
                    let w: NSWindow
                    if (u["part"] as? String) == "display" { guard let d = self.display else { return }; w = d } else { w = s.panel }
                    self.didDrag = true
                    w.setFrameOrigin(NSPoint(x: x, y: y))
                    self.moved()
                    self.released()
                default: break
                }
            }
        }
        restore()
    }

    // MARK: detach and attach

    func longPressed() {
        guard let s = stripe, s.minimizedFrame == nil else { return }
        if detached { cue(); return }
        detach()
    }

    func detach(at origin: NSPoint? = nil) {
        guard display == nil, let s = stripe, s.minimizedFrame == nil else { return }
        let r = slot()
        let face = s.face!
        let p = DisplayPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(p)
        let host = NSView(frame: NSRect(origin: .zero, size: r.size))
        p.contentView = host
        face.line.removeFromSuperview()
        face.line.frame = host.bounds
        face.line.restrictHit = true
        host.addSubview(face.line)
        display = p
        observeDisplay(p)
        var o = origin ?? r.origin
        if origin == nil { o.y += Prefs.lineBelow ? -Magnet.gap : Magnet.gap }
        p.setFrame(p.constrainFrameRect(NSRect(origin: o, size: r.size), to: nil), display: true)
        p.orderFrontRegardless()
        cue()
        save()
        appendLog("magnet: detached (display at \(Int(p.frame.minX)),\(Int(p.frame.minY)); body at \(Int(s.panel.frame.minX)),\(Int(s.panel.frame.minY)))")
    }

    func attach() {
        guard let p = display, let s = stripe else { return }
        let face = s.face!
        ghost?.orderOut(nil); ghost = nil
        for o in observers.dropFirst() { NotificationCenter.default.removeObserver(o) }
        observers = Array(observers.prefix(1))
        p.orderOut(nil)
        face.line.removeFromSuperview()
        face.line.restrictHit = false
        face.addSubview(face.line)
        display = nil
        near = false
        face.placeLine(below: Prefs.lineBelow)
        applyGlow(false)
        cue()
        save()
        appendLog("magnet: attached")
    }

    private func configure(_ p: NSPanel) {
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
    }

    private func observeDisplay(_ p: NSPanel) {
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            self?.moved(); self?.save()
        })
    }

    // MARK: while a part moves

    func moved() {
        guard let p = display, let s = stripe, s.minimizedFrame == nil else { return }
        let a = slot().origin, b = p.frame.origin
        let isNear = hypot(a.x - b.x, a.y - b.y) <= Magnet.snap
        if isNear != near {
            near = isNear
            if near { showGhost() } else { ghost?.orderOut(nil) }
            applyGlow(near)
        } else if near { ghost?.setFrame(slot(), display: true) }
    }

    /// a press ends: where a part was dragged and let go near its magnet, they attach
    func released() {
        defer { didDrag = false }
        guard display != nil else { return }
        if didDrag && near { attach() }
        else { ghost?.orderOut(nil); applyGlow(false); near = false }
    }

    private func showGhost() {
        if ghost == nil {
            let g = NSPanel(contentRect: slot(), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            configure(g)
            g.ignoresMouseEvents = true
            g.contentView = GhostView(frame: NSRect(origin: .zero, size: slot().size))
            ghost = g
        }
        ghost?.setFrame(slot(), display: true)
        ghost?.orderFrontRegardless()
    }

    // MARK: the cue

    func applyGlow(_ on: Bool) {
        guard let s = stripe else { return }
        s.face.pill.glow = on
        s.face.line.glow = on
    }

    /// the seam glows for a moment, and a soft click
    func cue() {
        applyGlow(true)
        if stripe?.recorder.recording != true, let snd = NSSound(named: NSSound.Name("Pop")) { snd.volume = 0.35; snd.play() }
        cueing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.cueing = false
            self.applyGlow(self.near)
        }
    }

    // MARK: kept across launches

    func save() {
        let d = UserDefaults.standard
        d.set(detached, forKey: "magnetDetached")
        guard let p = display else { return }
        let f = p.frame
        guard let sc = BlobPanel.screen(for: f) else { return }
        d.set(sc.localizedName, forKey: "magnetScreen")
        d.set(Double(f.minX - sc.frame.minX), forKey: "magnetX")
        d.set(Double(f.minY - sc.frame.minY), forKey: "magnetY")
    }

    func restore() {
        let d = UserDefaults.standard
        guard d.bool(forKey: "magnetDetached"), stripe != nil else { return }
        var origin: NSPoint?
        if let name = d.string(forKey: "magnetScreen"), let sc = NSScreen.screens.first(where: { $0.localizedName == name }),
           d.object(forKey: "magnetX") != nil {
            let o = NSPoint(x: sc.frame.minX + CGFloat(d.double(forKey: "magnetX")), y: sc.frame.minY + CGFloat(d.double(forKey: "magnetY")))
            let r = NSRect(origin: o, size: NSSize(width: PANEL_W, height: LINE_H - 2))
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: 40, dy: 20).intersects(r) }) { origin = o }
        }
        // a display that is gone: it comes back beside the body, still free
        detach(at: origin)
        if origin == nil { appendLog("magnet: the saved display is not here, the display is beside the body") }
        applyGlow(false)
    }
}
