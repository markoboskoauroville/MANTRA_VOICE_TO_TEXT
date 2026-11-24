// v70, THE BLOB COMES HOME (Marko, 24.11.2026: "It's not showing the blob anymore. When I go at the menu bar and I click show the
// blob, it's not showing.").
// Cause found on 24.11.2026: the saved place of the blob (defaults stripePlace) was written while the BenQ was turned (1440 x 2560,
// top = 1617 from the screen's top). The BenQ is 2560 x 1440 again: that place is 177 points BELOW the screen. The window was
// ordered in and "visible" for AppKit and the window server, so the menu said "Hide the blob"; the click hid it, the next click
// showed it again in the same place below the glass. Place.restore, showQuietly and restoreStripe put the old frame back without
// ever asking whether any screen still holds it.
// Now: the blob's frame is checked against the screens at launch, whenever it is shown, and whenever the screens change; when
// too little of it is on any screen it goes to the screen it was saved on (else the first one) at its remembered height.
import AppKit

extension Place {
    /// enough of the frame (60 %) lies on one of the screens that it can be seen and grabbed
    static func onScreen(_ f: NSRect, screens: [NSRect] = NSScreen.screens.map(\.frame)) -> Bool {
        guard f.width > 0, f.height > 0 else { return false }
        return screens.contains { s in
            let i = s.intersection(f)
            return !i.isNull && i.width * i.height >= 0.6 * f.width * f.height
        }
    }
}

extension Stripe {
    /// the blob is really there to see: not minimized, ordered in, opaque and on a screen
    var blobShown: Bool { minimizedFrame == nil && panel.isVisible && panel.alphaValue > 0.05 && Place.onScreen(panel.frame) }

    /// puts the blob back on a screen when its frame is on none (a changed display, a turned BenQ); true when it moved
    @discardableResult func ensureOnScreen(_ why: String) -> Bool {
        if Place.onScreen(panel.frame) { return false }
        let name = (UserDefaults.standard.dictionary(forKey: Place.key)?["screen"]) as? String
        let s = NSScreen.screens.first(where: { $0.localizedName == name }) ?? NSScreen.screens.first
        guard let s else { return false }
        let was = panel.frame
        panel.setFrameOrigin(Place.origin(on: s, size: panel.frame.size))
        Place.save(panel)
        flipStrip()
        appendLog("blob: its frame \(NSStringFromRect(was)) was on no screen (\(why)); moved to \(s.localizedName) at \(NSStringFromRect(panel.frame))")
        return true
    }

    /// the menu item "Show the blob": always visible, opaque, on a screen and in front
    func bringBlob() {
        Prefs.blobOpen = true
        if minimizedFrame != nil { showQuietly() }
        panel.alphaValue = 1
        ensureOnScreen("show the blob")
        panel.orderFrontRegardless()
        appendLog("blob: shown at \(NSStringFromRect(panel.frame)) on \(panel.screen?.localizedName ?? "no screen")")
    }

    func watchScreens() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.minimizedFrame != nil {
                if let f = self.minimizedFrame, !Place.onScreen(f) {       // closed: the place it comes back to is checked too
                    let was = self.panel.frame
                    self.panel.setFrame(f, display: false); self.ensureOnScreen("screens changed, blob closed")
                    self.minimizedFrame = self.panel.frame; self.panel.orderOut(nil); _ = was
                }
            } else { self.ensureOnScreen("screens changed") }
        }
    }
}
