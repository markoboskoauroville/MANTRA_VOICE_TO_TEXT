// Mantra Voice to Text, until v27 "Marko Transcribe": one floating pill that hears him, corrects what he said and types it into the app he is
// in. Since 30.10.2026 it does one thing one way: Whisper Turbo on this Mac writes the take down (English or Croatian),
// a Claude model at Anthropic corrects it (or nothing does), and it is typed where the cursor is.
//
// Press the hotkey (F1 unless changed in ⚙), talk, press it again. Escape while listening throws the take away.
import AppKit
import AVFoundation
import Carbon

enum Ink {
    static let ground = NSColor(calibratedWhite: 0.08, alpha: 0.94)
    static let text = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let dim = NSColor(calibratedWhite: 0.55, alpha: 1)
    static let green = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 1)
    static let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1)
    static let red = NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.30, alpha: 1)
    static let grey = NSColor(calibratedWhite: 0.40, alpha: 1)
}

let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
func textWidth(_ s: String, _ f: NSFont = font) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) + 8 }

// ✕ at the far upper-right corner of every window of this app: it closes that window only, the app stays ON
// (Marko, 19.10.2026: "please unify the position of the close button on every application. It's far upper right corner.
// There is X to close the dialog in every dialog, same.")
func closeX(_ target: AnyObject, _ action: Selector, tip: String) -> NSButton {
    let b = NSButton(title: "", target: target, action: action)
    b.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "close")?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
    b.imagePosition = .imageOnly
    b.isBordered = false
    b.contentTintColor = NSColor(calibratedRed: 0x7A/255, green: 0x80/255, blue: 0x87/255, alpha: 1)
    b.toolTip = tip
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 28).isActive = true
    b.heightAnchor.constraint(equalToConstant: 28).isActive = true
    return b
}

final class Dot: NSView {
    var color = Ink.grey { didSet { needsDisplay = true } }
    override func draw(_ r: NSRect) { color.setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
}

// The display by name and the top-left corner on it (as Connection Keeper v14: "remembers its last position and its
// last display").
enum Place {
    static let key = "stripePlace"
    static func save(_ w: NSWindow) {
        let f = w.frame
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: f.midX, y: f.maxY - 1)) }) ?? w.screen else { return }
        UserDefaults.standard.set(["screen": s.localizedName, "x": f.minX - s.frame.minX, "top": s.frame.maxY - f.maxY,
                                   "w": s.frame.width, "h": s.frame.height], forKey: key)
    }
    // On another display (request 13: the stripe comes up on the screen he is typing on): always in the middle across
    // (request 14: "when it changes the screen, it should always be aligned in the middle"), as far down as on the display
    // it was left on, kept inside the visible part.
    static func origin(on s: NSScreen, size: NSSize) -> NSPoint {
        let p = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        let top = p["top"] as? Double
        let sh = p["h"] as? Double ?? Double(s.frame.height)
        let fy = top.map { $0 / max(sh - Double(size.height), 1) } ?? 0.9
        let v = s.visibleFrame
        let ox = v.midX - size.width / 2
        let oy = s.frame.maxY - CGFloat(min(max(fy, 0), 1)) * (s.frame.height - size.height) - size.height
        return NSPoint(x: min(max(ox, v.minX), v.maxX - size.width), y: min(max(oy, v.minY), v.maxY - size.height))
    }
    static func restore(_ w: NSWindow) -> Bool {
        guard let p = UserDefaults.standard.dictionary(forKey: key), let name = p["screen"] as? String,
              let x = p["x"] as? Double, let top = p["top"] as? Double,
              let s = NSScreen.screens.first(where: { $0.localizedName == name }) else { return false }
        w.setFrameOrigin(NSPoint(x: s.frame.minX + x, y: s.frame.maxY - top - w.frame.height))
        return true
    }
}

// THE SCREEN HE IS TYPING ON (request 13): the focused text field's display (Accessibility), else the front window's,
// else the display under the mouse. Accessibility counts from the top-left of the main display, AppKit from its bottom.
func typingScreen() -> NSScreen? {
    func frame(_ e: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success else { return nil }
        var p = CGPoint.zero, z = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &z)
        return CGRect(origin: p, size: z)
    }
    var r: CGRect?
    if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var el: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &el) == .success, let el {
            r = frame(el as! AXUIElement)
        }
        if r == nil || r!.isEmpty && r!.origin == .zero {
            var w: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success, let w { r = frame(w as! AXUIElement) }
        }
    }
    let main = NSScreen.screens.first?.frame.maxY ?? 0
    let point = r.map { NSPoint(x: $0.midX, y: main - $0.midY) } ?? NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
}

final class Stripe: NSObject {
    let panel: NSPanel
    // v12, THE TALK BLOB (Pill.swift): the pill; its ⚙ holds the two choices, the history and the settings
    var face: PillFace!
    let dot = Dot()                            // the state's colour (green ready, red listening or failed, amber busy)
    let recorder = Recorder()
    var hotkey: HotKey?
    var escape: HotKey?
    var busy = false
    var cancelled = false                      // Esc while the take is written down or styled: nothing is typed
    var take = 0                               // each take its number: only the current, uncancelled one may type
    var loudest: Float = -160                  // the take's loudest moment: a take that never rose is not sent
    var hideToken = 0                          // a later take cancels the hide planned for an earlier one
    var tick: Timer?
    var sweepTimer: Timer?                     // the Braille spinner while the take is written down and styled
    var spinFrame = 0
    var statusText = ""
    static let braille = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    var lastText = ""
    var unlanded = false                       // the last text did not land: the blue button and the line copy it
    var lastLang = "en"                        // the language of the last text (Auto: the one Whisper heard)
    var pinned = false                         // v15: after STYLE the blob stays until ✕ (Marko, 31.10.2026)
    var minimizedFrame: NSRect?
    var settings: SettingsWindow?
    let voice = VoiceCommands()                // v21: "Listen" / "Send" (Voice.swift)
    var voiceTake = false                      // the take was started or sent by voice: its command words are cut

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: PANEL_W, height: PILL_H + LINE_H),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // v23 (Marko, 31.10.2026: "why I have double sausage ... remove this sausage behind"): no window shadow. The shadow
        // is made from the panel's shape once and is not redrawn when the line flips or the pill changes, so a second,
        // stale pill showed behind the pill
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // ✕ throws the take away (Esc), cancels the writing down, or, with nothing going on, sends the pill away (F1 or
        // the star brings it back); the blue button is F1: start, send, or copy what did not land
        face = PillFace(close: { [weak self] in self?.closePressed() },
                        lang: { [weak self] in self?.toggleLanguage() },
                        pause: { [weak self] in self?.togglePause() },
                        style: { [weak self] in self?.stylePressed() },
                        copy: { [weak self] in self?.copyPressed() },
                        gear: { [weak self] in self?.gearMenu() },
                        send: { [weak self] in self?.sendPressed() })
        face.line.clicked = { [weak self] in self?.statusClicked() }
        face.placeLine(below: Prefs.lineBelow)
        panel.contentView = face
        if !Place.restore(panel), let s = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: s.visibleFrame.midX - panel.frame.width / 2, y: s.visibleFrame.minY + 60))
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.minimizedFrame == nil else { return }
            Place.save(self.panel)
        }
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.restoreStripe() }
        }
        panel.orderFrontRegardless()

        // Typing into other apps needs Accessibility; macOS asks him once.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        bindHotkey()
        // v21: the voice commands act as F1 does; only the word that fits the moment is listened for
        voice.wanted = { [weak self] in
            guard let self else { return nil }
            if self.recorder.recording { return VoiceWords.end }
            return self.busy || self.styling ? nil : VoiceWords.start
        }
        voice.heard = { [weak self] w in
            guard let self else { return }
            if (w == VoiceWords.start && !self.recorder.recording && !self.busy) || (w == VoiceWords.end && self.recorder.recording) {
                self.voiceTake = true
                self.pressed()
            }
        }
        if VoiceWords.enabled { voice.start() }             // never asks at launch: permissions are asked from ⚙'s tick
        voiceMeter()
        refresh()
        ready()
        Whisper.warm()                                      // the model loaded once, before the first take
        // a download left half done (the app was quit, the Mac slept) goes on by itself (Marko, 1.11.2026)
        if !Model.ready && Model.started && !CommandLine.arguments.contains("--take") { Model.download() }
        if !Model.ready && !CommandLine.arguments.contains("--take") {   // the first start: ⚙ with the download button
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.openSettingsTab() }
        }
        History.purge()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in History.purge() }
        // with the stripe coming and going (request 10), it starts minimized: F1 brings it
        if Prefs.autoHide && !VoiceWords.enabled && !CommandLine.arguments.contains("--take") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if Prefs.autoHide && self?.recorder.recording == false && self?.busy == false { self?.minimizeStripe() }
            }
        }
        // AT LOGIN (the star opens its apps hidden with --login): the stripe is this app's only face, so it comes back to its
        // place quietly, without taking the front.
        // Whenever macOS hides the app and "–" was not pressed (a hidden launch hides it after this init has run), it shows
        // itself again without taking the front.
        NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.minimizedFrame == nil else { return }
            NSApp.unhideWithoutActivation()
            self.panel.orderFrontRegardless()
        }
        // A press from outside (tests, and any later remote control): the distributed notification
        // com.mantra.voicetotext.press does what the hotkey does; ".escape" what Esc does.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.press"), object: nil, queue: .main) { [weak self] _ in self?.pressed() }
        // v15: a build quits the running copy and opens the new one (MANTRA_MANIFEST swift-apps.md); never while it listens or
        // writes down, so no take is lost
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.quit"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.recorder.recording || self.busy { appendLog("quit asked from outside: refused, a take is in progress"); return }
            appendLog("quit asked from outside (a new build)")
            NSApp.terminate(nil)
        }
        // v22: what a short click on the status line does (tests)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.flipline"), object: nil, queue: .main) { [weak self] _ in self?.statusClicked() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.history"), object: nil, queue: .main) { [weak self] _ in self?.openHistory() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.settings"), object: nil, queue: .main) { [weak self] _ in self?.openSettingsTab() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mantra.voicetotext.escape"), object: nil, queue: .main) { [weak self] _ in
            if self?.recorder.recording == true { self?.cancel() } else { self?.cancelProcessing() }
        }
        // THE ARTIFICIAL TEST (Marko, 18.10.2026: "test it with artificial voices from edge ... I don't need to speak"):
        // --take <wav> sends a recording through the same road as a take from the microphone, 3 s after the start.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--take"), i + 1 < args.count {
            let file = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.process(file) }
        }
    }

    // MARK: the stripe's words

    // the pill at rest: HR / EN, pause and the wave quiet, the blue button ready to start
    func refresh() {
        face.lang.text = HearEngine.current.lang.uppercased()
        face.pause.live = recorder.recording
        // v17 (Marko, 31.10.2026: "tile should be always available, grayed out. When I press it, while it's working, it's
        // becoming green"): STYLE always there and pressable, grey at rest, green while it works
        face.style.live = true
        face.light(autoCorrect: StyleEngine.current != .off, styling: styling, unlanded: unlanded, copying: copying)
        if !recorder.recording && !busy { face.send.symbol = "mic.fill" }
    }

    // who hears and who cleans, in the small letters above the pill (as the Claude blob names its voice engine)
    var engines: String {
        "\(HearEngine.current.title.uppercased()) · " +
            (StyleEngine.current == .off ? "NO AUTO CORRECT" : "AUTO CORRECT: \(StyleEngine.current.title.uppercased())")
    }

    func say(_ text: String, _ color: NSColor, tip: String? = nil) {
        statusText = text; crashCrumb = text
        face.line.stringValue = sweepTimer == nil ? text : Stripe.braille[spinFrame % Stripe.braille.count] + " " + text
        face.line.textColor = color == Ink.dim ? NSColor(white: 1, alpha: 0.75) : color
        face.line.toolTip = tip ?? (lastText.isEmpty ? nil : "Last: " + lastText)
    }

    func ready() {
        dot.color = Ink.green
        refresh()
        let word = VoiceWords.enabled ? "SAY \"\(VoiceWords.start.uppercased())\" · " : ""          // v22
        say(word + "\(HotKey.chosen) TO TALK · " + engines, Ink.dim)
    }

    // MARK: the hotkey

    func bindHotkey() {
        hotkey = nil
        let code = HotKey.keys.first { $0.0 == HotKey.chosen }?.1 ?? UInt32(kVK_F1)
        hotkey = HotKey(code: code, id: 1) { [weak self] in self?.pressed() }
        if hotkey == nil { say("\(HotKey.chosen) is taken by another app: ⚙ to choose another", Ink.red) }
    }

    func pressed() {
        if busy { return }
        hideToken += 1                                  // a hide planned for the last take must not hide this one
        unlanded = false
        refresh()                                       // v29: COPY back to grey
        if minimizedFrame != nil && !recorder.recording { showQuietly() } else if !recorder.recording { followTyping() }
        recorder.recording ? finish() : listen()
    }

    func listen() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { self.say("no microphone: System Settings → Privacy → Microphone", Ink.red); return }
                Chime.play(start: true)
                usleep(150_000)                             // the sound (0.1 s) is over before the microphone opens
                guard self.recorder.start() else { self.say("the microphone did not start", Ink.red); return }
                Whisper.warm()                                 // v28: the model is ready before the words arrive
                self.loudest = -160
                self.dot.color = Ink.red
                self.escape = HotKey(code: UInt32(kVK_Escape), id: 2) { [weak self] in self?.cancel() }
                self.face.send.symbol = "arrow.up"
                self.face.pause.live = true
                self.face.wave.moving = true
                self.voiceTick?.invalidate(); self.voiceTick = nil
                self.face.wave.color = VoiceWords.enabled ? Ink.green : WaveView.white      // v22: green while a take records
                self.tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in self?.showListening() }
                self.showListening()
            }
        }
    }

    // 24 times a second: his voice in the bars, the clock and the ear above
    func showListening() {
        guard recorder.recording else { return }
        let db = recorder.peakDB
        if let db { loudest = max(loudest, db) }
        face.wave.moving = !recorder.paused
        face.wave.take(recorder.bands.db)
        face.pause.symbol = recorder.paused ? "play.fill" : "pause.fill"
        face.lang.text = HearEngine.current.lang.uppercased()
        let s = Int(recorder.elapsed)
        let word = VoiceWords.enabled ? " · SAY \"\(VoiceWords.end.uppercased())\"" : ""                 // v22
        say(String(format: "%@ %d:%02d · ", recorder.paused ? "PAUSED" : "●", s / 60, s % 60) + engines + word, recorder.paused ? Ink.dim : Ink.red)
        dot.color = recorder.paused ? Ink.grey : Ink.red
    }

    func endListening() {
        tick?.invalidate(); escape = nil
        face.pause.live = false
        if VoiceWords.enabled && voice.running { voiceMeter(); return }      // v22: the listener's meter goes on
        face.wave.moving = false
        face.wave.take(nil)
        // the bars fall back to dots on their own release
        Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] t in
            guard let self, !self.recorder.recording else { t.invalidate(); return }
            self.face.wave.take(nil)
            if self.face.wave.spec.allSatisfy({ $0 <= -140 }) { t.invalidate() }
        }
    }

    @objc func closePressed() {
        if recorder.recording { cancel() } else if busy { cancelProcessing() } else { pinned = false; minimizeStripe() }
    }

    @objc func sendPressed() {
        pressed()                                   // v17: the blue button is F1 only; COPY copies
    }

    @objc func trashTake() { cancel() }
    @objc func togglePause() { recorder.paused ? recorder.resume() : recorder.pause(); showListening() }

    // 🌐: Whisper in the other language (EN ⇄ HR), for this take and the next
    @objc func toggleLanguage() {
        let swap: [HearEngine: HearEngine] = [.whisperEN: .whisperHR, .whisperHR: .whisperAuto, .whisperAuto: .whisperEN]   // v15: EN → HR → AUTO
        if let other = swap[HearEngine.current] { HearEngine.current = other; refresh(); recorder.recording ? showListening() : ready() }
    }

    // WHILE THE TAKE IS WRITTEN DOWN AND STYLED: the Braille spinner in front of the words, the meter quiet (request 13:
    // "add the Braille spinner instead of playing with LED lights or VU meter while in the process of transcribing").
    func sending(_ on: Bool) {
        sweepTimer?.invalidate()
        sweepTimer = nil
        guard on else { face.line.stringValue = statusText; refresh(); return }
        face.send.symbol = "ellipsis"
        spinFrame = 0
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.spinFrame += 1
            self.face.line.stringValue = Stripe.braille[self.spinFrame % Stripe.braille.count] + " " + self.statusText
        }
        RunLoop.main.add(t, forMode: .common)               // it turns while a menu is open too
        sweepTimer = t
    }

    func cancelProcessing() {
        guard busy else { return }
        cancelled = true
        escape = nil
        busy = false
        sending(false)
        Chime.play(start: false)
        dot.color = Ink.green
        say("cancelled", Ink.dim)
        hideSoon()
    }

    func cancel() {
        endListening()
        recorder.stop { _ in }
        Chime.play(start: false)
        say("thrown away", Ink.dim)
        dot.color = Ink.green
        hideSoon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in if self?.recorder.recording == false { self?.ready() } }
    }

    // NOTHING SAID, NOTHING SENT (18.10.2026: two quick F1 presses, half a second of room noise, and Whisper wrote "you",
    // which was typed). Shorter than 0.7 s, or never louder than -40 dB: the take is dropped.
    func finish() {
        let secs = recorder.elapsed
        endListening()
        Chime.play(start: false)
        if secs < 0.7 || loudest < -40 {
            recorder.stop { _ in }
            say(String(format: "nothing said (%.1f s, %.0f dB): not sent", secs, loudest), Ink.dim)
            dot.color = Ink.green
            hideSoon()
            appendLog(String(format: "dropped: %.1f s, loudest %.0f dB", secs, loudest))
            return
        }
        recorder.stop { [weak self] wav in
            guard let self else { return }
            guard let wav else { self.say("the recording did not finish", Ink.red); return }
            self.process(wav)
        }
    }

    // A take, from the microphone or (the artificial test, --take <file>) from a recording: written down, styled, typed.
    func process(_ wav: URL) {
        busy = true
        cancelled = false
        take += 1
        let mine = take
        sending(true)
        // Esc while it is written down or styled: the action is cancelled, nothing is typed
        escape = HotKey(code: UInt32(kVK_Escape), id: 2) { [weak self] in self?.cancelProcessing() }
        dot.color = Ink.amber
        say("writing it down…", Ink.amber)
        let hear = HearEngine.current, style = StyleEngine.current
        let byVoice = voiceTake
        voiceTake = false
        DispatchQueue.global().async {
            let t0 = Date()
            Ring.lastMove = nil
            // v21: a take started or sent by voice has "listen" / "send" cut from its text (Whisper hears them too)
            let heard = byVoice ? Hear.run(hear, wav: wav).map(VoiceWords.strip) : Hear.run(hear, wav: wav)
            let tHear = Date().timeIntervalSince(t0)
            guard case .success(let words) = heard, !words.trimmingCharacters(in: .whitespaces).isEmpty else {
                let why: String = { if case .failure(let e) = heard { return e.message }; return "nothing heard" }()
                DispatchQueue.main.async {
                    guard mine == self.take, !self.cancelled else { return }
                    self.escape = nil
                    self.busy = false; self.sending(false); self.dot.color = Ink.red
                    self.say(why, Ink.red, tip: "⚙ → History: this take waits there with its audio for Transcribe again")
                    appendLog("failed (\(hear.title)): \(why)")
                    // the audio is not lost: the take goes in the history without words, to be transcribed again there
                    if !why.hasPrefix("nothing heard") {
                        History.add(wav: wav, Version(at: Date(), hear: hear.title, style: "failed: " + why, lang: hear.lang, heard: "", text: ""))
                    }
                    self.hideSoon(after: 5)
                }
                return
            }
            // Auto: the language Whisper heard, or "auto" for the correction when the voice did not say
            let lang = hear == .whisperAuto ? (Hear.lastLang.flatMap { ["en", "hr"].contains($0) ? $0 : nil } ?? "auto") : hear.lang
            if style != .off { DispatchQueue.main.async { self.say("auto correct (\(style.title))…", Ink.amber) } }
            let t1 = Date()
            var final = corrected(words), warning: String?
            switch Style.run(style, text: words, lang: lang) {
            case .success(let t): final = t
            case .failure(let e):
                warning = "not auto corrected: " + e.message        // the words as heard still go in, he is never left with nothing
            }
            let tStyle = Date().timeIntervalSince(t1)
            let moved = Ring.lastMove
            DispatchQueue.main.async {
                guard mine == self.take, !self.cancelled else { appendLog("cancelled (Esc), not typed: \(final)"); return }
                self.escape = nil
                self.sending(false)
                self.lastText = final
                self.lastLang = lang
                self.busy = false
                History.add(wav: wav, Version(at: Date(), hear: hear.title, style: style.title, lang: hear.lang, heard: words,
                                              text: final))
                if self.settings?.window.isVisible == true { self.settings?.history.reload() }
                let n = final.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
                // TEST MODE (request 17: tested by Claude with artificial speech while Marko works): `defaults write
                // com.mantra.markotranscribe testNoTyping -bool true` keeps the words out of the app in front; history and log only
                if UserDefaults.standard.bool(forKey: "testNoTyping") {
                    self.dot.color = Ink.green
                    self.say(String(format: "test: %d words, not typed · %.1f + %.1f s", n, tHear, tStyle) + (moved.map { " · key moved: \($0)" } ?? ""), Ink.green)
                    appendLog("test, not typed: \(final)")
                    return
                }
                Typer.insert(final) { landing in
                    if landing == .nowhere { self.notLanded("\(n) words did not land"); return }
                    let how = landing == .typed ? "typed" : "pasted"
                    if let warning {
                        self.dot.color = Ink.amber
                        self.say("\(how): \(warning)", Ink.amber)
                    } else if let moved {
                        self.dot.color = Ink.amber                   // the ring moved: said once (quota-and-fallback.md rule 5)
                        self.say(String(format: "%@ %d words · %.1f + %.1f s · key moved: %@", how, n, tHear, tStyle, moved), Ink.amber)
                    } else {
                        self.dot.color = Ink.green
                        self.say(String(format: "%@ %d words · %.1f + %.1f s", how, n, tHear, tStyle), Ink.green)
                    }
                    self.hideSoon()
                }
                appendLog("heard (\(hear.title), \(String(format: "%.1f", tHear)) s): \(words)\n  styled (\(style.title), \(String(format: "%.1f", tStyle)) s): \(final)")
            }
        }
    }

    // MARK: the drop-downs

    // ⚙ ON THE PILL (Marko, 30.10.2026: "remove quick choices. Too many choices ... the first selection is called
    // transcription model and the second correction. Simplify the wordings in the menu")
    @objc func gearMenu() {
        let m = NSMenu()
        func head(_ t: String) { let h = NSMenuItem(title: t, action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h) }
        head("Transcription model")
        for e in HearEngine.allCases {
            let i = NSMenuItem(title: e.menuTitle, action: #selector(pickHear(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = e.rawValue; i.state = e == HearEngine.current ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        head("Auto correct (after a take)")          // v23 (Marko, 31.10.2026: "It's not corrections ... Auto correct")
        for e in StyleEngine.allCases {
            let i = NSMenuItem(title: e.menuTitle, action: #selector(pickStyle(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = e.rawValue; i.state = e == StyleEngine.current ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        for (t, sel, on) in [("History…", #selector(openHistory), true),
                             ("Type the last text again", #selector(typeAgain), !lastText.isEmpty),
                             ("Settings…", #selector(openSettingsTab), true)] {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; i.isEnabled = on; m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: face.gear.bounds.height + 4), in: face.gear)
    }

    @objc func pickHear(_ i: NSMenuItem) {
        HearEngine.current = HearEngine(rawValue: i.representedObject as! String)!
        refresh(); ready()
    }

    @objc func pickStyle(_ i: NSMenuItem) {
        StyleEngine.current = StyleEngine(rawValue: i.representedObject as! String)!
        refresh(); ready()
    }

    @objc func typeAgain() {
        guard !lastText.isEmpty else { return }
        Typer.insert(lastText) { l in
            if l == .nowhere { self.notLanded("did not land") }
            else { self.say((l == .typed ? "typed" : "pasted") + " again", Ink.green) }
        }
    }

    // History… opens ⚙ on its second tab, Transcription history (request 14).
    @objc func openHistory() { openSettings(tab: 1) }

    @objc func openSettingsTab() { openSettings(tab: 0) }

    func openSettings(tab: Int) {
        if settings == nil {
            settings = SettingsWindow(onChange: { [weak self] in self?.bindHotkey(); self?.refresh(); self?.ready() }) { [weak self] text in
                self?.lastText = text
                Typer.insert(text) { l in if l == .nowhere { self?.notLanded("did not land") } }
            }
        }
        settings?.show(tab: tab)
    }

    // MARK: minimize (as Connection Keeper: in Command-Tab and the Dock only while hidden)

    @objc func minimizeStripe() {
        minimizedFrame = panel.frame
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.hide(nil)
    }

    // F1 brings the stripe back to its place without taking the front from the app he is typing into.
    func showQuietly() {
        guard let f = minimizedFrame else { return }
        minimizedFrame = nil
        panel.setFrame(f, display: true)
        followTyping()
        NSApp.setActivationPolicy(.accessory)
        NSApp.unhideWithoutActivation()
        panel.orderFrontRegardless()
    }

    // The stripe comes up on the display he is typing on, at the same place it has there (request 13).
    // v20 (Marko, 31.10.2026: "When after hide is turned off, then the blob is always in the same fixed position"): with
    // the tick off it never moves by itself; only his drag moves it, and that place is remembered (Place.save)
    func followTyping() {
        guard Prefs.autoHide else { return }
        guard let s = typingScreen() else { return }
        let here = NSScreen.screens.first { $0.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 1)) }
        if here == s { return }
        panel.setFrameOrigin(Place.origin(on: s, size: panel.frame.size))
    }

    // Three seconds after the take is typed or thrown away (five after an error, twelve when the text did not land), the
    // pill goes, as the Claude blob's does (request 10: "f1 again hides it after 2 second delay ... esc same"; v12: one
    // second; v15, Marko 31.10.2026: "It needs to have 3 seconds delay so I can still click on something when I stop
    // transcribing"). After STYLE it does not go at all: only ✕ sends it away.
    func hideSoon(after secs: Double = 3) {
        guard Prefs.autoHide, !pinned, !VoiceWords.enabled else { return }   // v22: voice activation keeps the blob in sight
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
            guard let self, Prefs.autoHide, !VoiceWords.enabled, token == self.hideToken, !self.busy, !self.recorder.recording, !self.pinned, self.minimizedFrame == nil else { return }
            self.unlanded = false
            self.refresh()
            self.minimizeStripe()
        }
    }

    // THE TEXT DID NOT LAND (request 11, request 14: "if I click on error, it should copy what is not landing to the
    // clipboard so I can manually paste it into the missing field"): the words above the pill are a button now, and the
    // blue button copies too.
    // v15 (Marko, 31.10.2026: "if transcription do not land, I need to have ... link, which is going to appear in the blob
    // saying copy transcript"): the band ends in COPY TRANSCRIPT, underlined like a link.
    func notLanded(_ text: String) {
        dot.color = Ink.amber
        // v17: the blob stays and waits (no hiding) until COPY or ✕ (Marko, 31.10.2026: "this blob will not disappear,
        // it will wait for action. and then I simply can press copy")
        say(text + " · press COPY", Ink.amber, tip: "COPY puts it on the clipboard, then ⌘V where you want it\n\n" + lastText)
        unlanded = true
        pinned = true
        hideToken += 1
        refresh()
    }

    // STYLE (v15): his prompt (the correction's rules and his additions) rewrites text in place. The blob stays.
    // v19 (Marko, 31.10.2026: "this styling works always. I can click anywhere where there is a text box in the screen and
    // it will correct styling"): the text box he clicked into, in any app (Restyle, Hands.swift): its selection, else the
    // words this app typed last when they are there, else its whole text; its own Claude (⚙ "The STYLE button", Haiku by
    // default), never None. A box that takes no Accessibility writing gets the styled text on the clipboard: ⌘V by hand.
    /// STYLE is working (v17): its word green from the press until the words are replaced or it failed
    var styling = false

    @objc func stylePressed() {
        if styling { return }
        if recorder.recording { say("STYLE works on text already written: send this take first", Ink.amber); return }
        if busy { say("still writing the last take down: STYLE after it", Ink.amber); return }
        guard AXIsProcessTrusted() else {
            // MANTRA_MANIFEST swift-apps.md, PERMISSIONS: the system's own request once, then straight to the page
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            dot.color = Ink.amber
            say("PERMISSIONS: STYLE needs Accessibility (System Settings is open)", Ink.amber)
            return
        }
        // the focus is read at the press: the blob never takes it (a non-activating panel)
        var target: Restyle.Target?
        var lang = "auto"
        switch Restyle.find(lastTyped: lastText) {
        case .target(let t):
            if t.text.count > 20000 { say("too much text for STYLE (\(t.text.count) characters): select a part, then STYLE", Ink.amber); return }
            target = t
            if t.text == lastText { lang = lastLang }
        case .ownWindow:
            say("click into the text box you want styled, then STYLE", Ink.amber); return
        case .empty:
            say("this text box is empty: write or select something, then STYLE", Ink.amber); return
        case .noFocus, .unreadable:
            // no text box, or one that does not let its text be read: the last take styled onto the clipboard, if any
            if lastText.isEmpty { say("no text box to style: click into one (or select its text), then STYLE", Ink.amber); return }
            lang = lastLang
        }
        let source = target?.text ?? lastText
        styling = true
        pinned = true
        hideToken += 1
        busy = true
        let engine = StyleButtonEngine.current
        sending(true)
        say("styling \(target?.what ?? "the last take") (\(engine.title))…", Ink.amber)
        refresh()
        DispatchQueue.global().async {
            let r = Style.run(engine, text: source, lang: lang)
            DispatchQueue.main.async {
                self.busy = false
                self.sending(false)
                self.styling = false
                switch r {
                case .failure(let e):
                    self.dot.color = Ink.red
                    self.say("not styled: " + e.message, Ink.red)
                    appendLog("STYLE failed (\(engine.title)): \(e.message)")
                case .success(let styled):
                    appendLog("STYLE (\(engine.title)) on \(target?.what ?? "the last take"), \(target.map { Restyle.role($0.field) } ?? "no field"): \(source)\n  styled: \(styled)")
                    let n = styled.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
                    if styled == source { self.dot.color = Ink.green; self.say("nothing to correct · ✕ closes", Ink.green); break }
                    let written = target.map { Restyle.write(styled, to: $0) } ?? .failed
                    switch written {
                    case .replaced:
                        self.lastText = styled
                        self.dot.color = Ink.green
                        self.say("styled: \(target!.what), \(n) words · ✕ closes", Ink.green)
                    case .believed:
                        self.lastText = styled
                        self.toClipboard(styled)
                        self.dot.color = Ink.green
                        self.say("styled: \(n) words written (this box cannot be read back; also on the clipboard)", Ink.green)
                    case .failed:
                        self.lastText = styled
                        self.toClipboard(styled)
                        self.dot.color = Ink.amber
                        self.say(target == nil ? "styled the last take: on the clipboard, press ⌘V where you want it"
                                               : "this box takes no writing: styled text on the clipboard, select its text and press ⌘V", Ink.amber)
                        appendLog("STYLE: the field did not take it (\(target.map { Restyle.role($0.field) } ?? "no field")), on the clipboard")
                    }
                }
                self.refresh()
            }
        }
    }

    /// v19: the styled text that could not be written goes on the clipboard, COPY green while it waits for ⌘V
    func toClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copying = true
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.copying = false; self?.refresh() }
    }

    @objc func copyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
        let waited = unlanded
        unlanded = false
        copying = true
        refresh()
        say("copied: ⌘V where you want it", Ink.green)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.copying = false; self?.refresh() }
        if waited { pinned = false }
        hideSoon()
    }

    /// COPY is working (v17): green for a moment while the words go on the clipboard
    var copying = false

    @objc func copyPressed() {
        if lastText.isEmpty { say("nothing to copy yet: dictate first", Ink.amber); return }
        copyLast()
    }

    // v22 (Marko, 31.10.2026: "Only function of the clicking is to push this line at the bottom of blob or at the top"):
    // a short click on the line flips it, nothing else (COPY copies, ⚙ → History opens the history). The pill stays where
    // it is on screen: the panel moves by the line's height the other way.
    @objc func statusClicked() {
        Prefs.lineBelow.toggle()
        face.placeLine(below: Prefs.lineBelow)
        var o = panel.frame.origin
        o.y += Prefs.lineBelow ? -LINE_H : LINE_H
        panel.setFrameOrigin(o)
    }

    // v22, THE METER WITH VOICE ACTIVATION (Marko, 31.10.2026: "this spectral meter is always running, but only in
    // different colors ... yellow and when it starts to transcribe it's green"): the listener's own bands, yellow while
    // it waits for the start word; green while a take records (the take's bands, showListening) and while it is written
    // down. 15 frames a second while waiting (less drawing than the take's 24).
    var voiceTick: Timer?
    func voiceMeter() {
        voiceTick?.invalidate(); voiceTick = nil
        guard VoiceWords.enabled, voice.running, !recorder.recording else {
            if !recorder.recording { face.wave.color = WaveView.white }
            return
        }
        voiceTick = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            guard let self, self.minimizedFrame == nil else { return }
            self.face.wave.color = self.busy ? Ink.green : WaveView.yellow
            self.face.wave.moving = true
            self.face.wave.take(self.voice.bands.db)
        }
    }

    /// the tick in ⚙ changed: the listener and the meter follow; with voice activation the blob stays in sight
    func voiceChanged() {
        voice.restart()
        voiceMeter()
        if VoiceWords.enabled && minimizedFrame != nil { showQuietly() }
        if !recorder.recording && !busy { ready() }
    }

    func restoreStripe() {
        guard let f = minimizedFrame else { return }
        minimizedFrame = nil
        panel.setFrame(f, display: true)
        panel.orderFrontRegardless()
        NSApp.setActivationPolicy(.accessory)
    }
}

// The log: what was heard and what was typed, so a bad result can be looked at afterwards.
let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/mantra-voice-to-text.log")
func appendLog(_ s: String) {
    let f = ISO8601DateFormatter(); f.timeZone = .current
    let line = "\(f.string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logFile) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logFile, atomically: true, encoding: .utf8) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // A hidden launch (the star at login) starts the app hidden, and macOS announces no hide for that: look once it has
    // finished launching, and again a moment later.
    func applicationDidFinishLaunching(_ n: Notification) {
        TakeMark.set(false)          // v26: a mark left by a crash never holds the voice
        for delay in [0.3, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard NSApp.isHidden, stripe.minimizedFrame == nil else { return }
                NSApp.unhideWithoutActivation()
                stripe.panel.orderFrontRegardless()
            }
        }
    }

    // closing a window leaves the app ON; the star's open (a reopen) brings the stripe back (Marko, 19.10.2026)
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if stripe.minimizedFrame != nil { stripe.showQuietly() } else { stripe.panel.orderFrontRegardless() }
        return false
    }
}

// THE TERMINAL TOO (keyring.md §6b): --import-keys FILE... reads key notes the way ⚙'s picker does (every provider by its
// shape), prints the sentence back, never a key.
if let i = CommandLine.arguments.firstIndex(of: "--import-keys"), i + 1 < CommandLine.arguments.count {
    var rest = Array(CommandLine.arguments[(i + 1)...])
    let only = Provider(rawValue: rest[0])
    if only != nil { rest.removeFirst() }
    print(Keys.importFiles(rest.map { URL(fileURLWithPath: $0) }, only: only))
    for p in Provider.allCases { print("\(p.title): \(Keys.entries(p).count) key(s) held") }
    exit(0)
}

// --chime start|stop <percent>: the Start or Stop sound at a slider position, through the app's own Chime, nothing kept
// (v24: measured through BlackHole; the settings are never written by a test)
if let i = CommandLine.arguments.firstIndex(of: "--chime"), i + 2 < CommandLine.arguments.count,
   let pct = Float(CommandLine.arguments[i + 2]) {
    _ = NSApplication.shared
    Chime.play(start: CommandLine.arguments[i + 1] == "start", position: pct / 100)
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    exit(0)
}

// --parse FILE...: what the picker would take from each file, nothing kept; titles and counts only, never a key (tests)
if let i = CommandLine.arguments.firstIndex(of: "--parse"), i + 1 < CommandLine.arguments.count {
    for path in CommandLine.arguments[(i + 1)...] {
        let url = URL(fileURLWithPath: path)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for (p, list) in Keys.parse(text, sourceName: url.lastPathComponent).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("\(url.lastPathComponent): \(p.title) \(list.count): " + list.map { "\"\($0.title)\"" }.joined(separator: ", "))
        }
    }
    exit(0)
}


// --test-keys <assemblyai|groq|anthropic>: what ⚙'s Test button does, from the command line.
if let i = CommandLine.arguments.firstIndex(of: "--test-keys"), i + 1 < CommandLine.arguments.count,
   let p = Provider(rawValue: CommandLine.arguments[i + 1]) {
    print("\(p.title): \(KeyTest.run(p))")
    exit(0)
}

// --hear <engine> <audio> / --style <engine> <lang> <text>: one engine alone, the time it took (tests, no stripe)
if let i = CommandLine.arguments.firstIndex(of: "--hear"), i + 2 < CommandLine.arguments.count,
   let e = HearEngine(rawValue: CommandLine.arguments[i + 1]) {
    let t0 = Date()
    switch Hear.run(e, wav: URL(fileURLWithPath: CommandLine.arguments[i + 2])) {
    case .success(let t): print(String(format: "%.2f s", Date().timeIntervalSince(t0)), t)
    case .failure(let err): print("FAILED:", err.message)
    }
    if let m = Ring.lastMove { print("ring:", m) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--style"), i + 3 < CommandLine.arguments.count,
   let e = StyleEngine(rawValue: CommandLine.arguments[i + 1]) {
    let t0 = Date()
    switch Style.run(e, text: CommandLine.arguments[i + 3], lang: CommandLine.arguments[i + 2]) {
    case .success(let t): print(String(format: "%.2f s", Date().timeIntervalSince(t0)), t)
    case .failure(let err): print("FAILED:", err.message)
    }
    if let m = Ring.lastMove { print("ring:", m) }
    exit(0)
}

// --test-style-focused <App name> [<from> <length>]: STYLE's road (Restyle, the STYLE button's Claude, the write back) on the
// focused text box of that app, which may be hidden or behind (a test never takes his focus); with <from> <length> that
// range is selected first, to test the selection. Prints the box's text before and after.
if let i = CommandLine.arguments.firstIndex(of: "--test-style-focused"), i + 1 < CommandLine.arguments.count {
    let a = CommandLine.arguments
    guard AXIsProcessTrusted() else { print("FAILED: no Accessibility for this process"); exit(1) }
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == a[i + 1] }) else { print("FAILED: \(a[i + 1]) is not running"); exit(1) }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 3)
    // the app's own focused element (it is not the front app); else the first text area of its first window
    func firstText(_ el: AXUIElement, _ depth: Int) -> AXUIElement? {
        if Typer.textRoles.contains(Restyle.role(el)) { return el }
        guard depth < 8, let kids = Restyle.attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for k in kids { if let t = firstText(k, depth + 1) { return t } }
        return nil
    }
    var field = Restyle.attr(ax, kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
    if field == nil || !Typer.textRoles.contains(Restyle.role(field!)),
       let w = (Restyle.attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first { field = firstText(w, 0) }
    guard let field else { print("FAILED: no text box in \(a[i + 1])"); exit(1) }
    if i + 3 < a.count, let from = Int(a[i + 2]), let len = Int(a[i + 3]) {
        var cf = CFRange(location: from, length: len)
        let ok = AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &cf)!) == .success
        print("selected \(from)+\(len):", ok ? "yes" : "NO")
    }
    print("field:", Restyle.role(field))
    print("before:", Typer.value(field) ?? "(unreadable)")
    switch Restyle.find(in: field, lastTyped: "") {
    case .target(let t):
        print("target: \(t.what): \(t.text)")
        let engine = StyleButtonEngine.current, t0 = Date()
        switch Style.run(engine, text: t.text, lang: "auto") {
        case .success(let styled):
            print(String(format: "styled by %@ in %.1f s: %@", engine.title, Date().timeIntervalSince(t0), styled))
            print("written:", Restyle.write(styled, to: t))
            print("after:", Typer.value(field) ?? "(unreadable)")
        case .failure(let e): print("FAILED: \(e.message)")
        }
    case .empty(let r): print("empty box (\(r))")
    case .unreadable(let r): print("unreadable box (\(r))")
    default: print("no target")
    }
    exit(0)
}

// --test-voice-commands <audio>: the voice commands' recognizer on a file (Voice.swift)
if let i = CommandLine.arguments.firstIndex(of: "--test-voice-commands"), i + 1 < CommandLine.arguments.count {
    VoiceCommands.testFile(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    print("strip: \"Listen. Please send me the file. Send.\" -> \"\(VoiceWords.strip("Listen. Please send me the file. Send."))\"")
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--test-voice-feed"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    VoiceCommands.feed(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

// --test-voice-live <seconds>: the live listener on ⚙'s microphone beside a take's recorder (both sessions on one device),
// nothing kept: how many buffers each got, every command heard
if let i = CommandLine.arguments.firstIndex(of: "--test-voice-live"), i + 1 < CommandLine.arguments.count, let secs = Double(CommandLine.arguments[i + 1]) {
    _ = NSApplication.shared
    let v = VoiceCommands(), rec = Recorder()
    var heard: [String] = []
    v.wanted = { rec.recording ? VoiceWords.end : VoiceWords.start }
    v.heard = { heard.append($0); print("heard:", $0) }
    v.start()
    print("listener running:", v.running)
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let idle = CommandLine.arguments.contains("idle")       // idle: the listener alone, as when no take is recording
    // meter: the blob's yellow meter drawn at 15 fps in a non-activating panel on the MacBook's own screen (never the
    // BenQ, never the focus), as with voice activation on
    var meterPanel: NSPanel?
    if CommandLine.arguments.contains("meter") {
        let screen = NSScreen.screens.first { $0.localizedName.contains("Built-in") } ?? NSScreen.screens.first!
        let p = NSPanel(contentRect: NSRect(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20, width: PANEL_W, height: PILL_H + LINE_H),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar; p.backgroundColor = .clear; p.isOpaque = false
        let f = PillFace(close: {}, lang: {}, pause: {}, style: {}, copy: {}, gear: {}, send: {})
        f.line.stringValue = "TEST: THE VOICE METER"
        f.wave.color = WaveView.yellow; f.wave.moving = true
        p.contentView = f; p.orderFrontRegardless()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { _ in f.wave.take(v.bands.db) }
        meterPanel = p
        print("meter on", screen.localizedName)
    }
    print("recorder started:", idle ? false : rec.start())
    RunLoop.main.run(until: Date().addingTimeInterval(secs))
    let b1 = v.buffers
    var file: URL?
    rec.stop { file = $0 }
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let size = file.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) } ?? 0
    let lv = v.levels.sorted()
    let pct = { (q: Double) -> Float in lv.isEmpty ? -160 : lv[min(lv.count - 1, Int(Double(lv.count) * q))] }
    print("listener buffers: \(b1) · recognizer woken \(v.tasks)× · levels dBFS 10/50/90 %: \(Int(pct(0.1)))/\(Int(pct(0.5)))/\(Int(pct(0.9))) · take file: \(size) bytes · commands: \(heard)")
    if let file { try? FileManager.default.removeItem(at: file) }
    meterPanel?.orderOut(nil)
    v.stop()
    exit(0)
}

// --download-model: only the model download (resumes from a .part), no window; ends when it is complete or failed
if CommandLine.arguments.contains("--download-model") {
    Model.onProgress = { f in FileHandle.standardError.write(String(format: "\r%.2f %%", f * 100).data(using: .utf8)!) }
    Model.onWait = { w in FileHandle.standardError.write(("\n" + w + "\n").data(using: .utf8)!) }
    Model.onDone = { p in print(p == nil ? "\ncomplete: \(Model.file.path)" : "\nproblem: \(p!)"); exit(p == nil ? 0 : 1) }
    print("from byte \(Model.partSize)")
    Model.download()
    RunLoop.main.run()
}

// --settings-shot <png>: ⚙'s Settings page drawn off screen (never on his screen), to see nothing is cut
if let i = CommandLine.arguments.firstIndex(of: "--settings-shot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let w = SettingsWindow(onChange: {}, typeText: { _ in })
    w.window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); w.window.appearance = NSAppearance(named: .aqua)
    w.window.layoutIfNeeded()
    if let v = w.window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("settings page: \(Int(v.bounds.width))×\(Int(v.bounds.height))")
    }
    exit(0)
}

// --bands <audio>: the pill's meter numbers for a recording (Pill.swift), no microphone, no window
if let i = CommandLine.arguments.firstIndex(of: "--bands"), i + 1 < CommandLine.arguments.count {
    MicBands.printBands(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

// --pill-shot <dir>: the pill drawn off screen in its three faces (ready, listening, writing down), never on his screen
if let i = CommandLine.arguments.firstIndex(of: "--pill-shot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let white = NSColor(white: 1, alpha: 0.75)
    func shot(_ name: String, _ line: String, _ colour: NSColor, send: String, pause: Bool, db: [Double]?, styling: Bool = false, copying: Bool = false,
              autoCorrect: Bool = true, unlanded: Bool = false,
              wave: NSColor = WaveView.white, below: Bool = false) {
        let f = PillFace(close: {}, lang: {}, pause: {}, style: {}, copy: {}, gear: {}, send: {})
        f.wave.color = wave; f.placeLine(below: below)
        f.line.stringValue = line; f.line.textColor = colour
        f.lang.text = "AUTO"; f.send.symbol = send; f.pause.live = pause; f.light(autoCorrect: autoCorrect, styling: styling, unlanded: unlanded, copying: copying)
        f.wave.moving = db != nil; f.wave.take(db)
        try? f.png()?.write(to: dir.appendingPathComponent(name))
    }
    shot("1-ready.png", "F1 TO TALK · WHISPER TURBO AUTO · AUTO CORRECT: CLAUDE HAIKU", white, send: "mic.fill", pause: false, db: nil)
    shot("2-listening.png", "● 0:07 · WHISPER TURBO AUTO · AUTO CORRECT: CLAUDE HAIKU", Ink.red, send: "arrow.up", pause: true,
         db: [-40, -30, -24, -22, -26, -30, -34, -40, -46, -52, -60])
    shot("3-writing.png", "⠹ writing it down…", Ink.amber, send: "ellipsis", pause: false, db: nil)
    shot("4-not-landed.png", "12 words did not land · press COPY", Ink.amber, send: "mic.fill", pause: false, db: nil, unlanded: true)
    shot("5-styled.png", "styled: 12 words replaced · ✕ closes", Ink.green, send: "mic.fill", pause: false, db: nil)
    shot("6-styling.png", "styling (Claude Haiku)…", Ink.amber, send: "ellipsis", pause: false, db: nil, styling: true)
    shot("7-copied.png", "copied: ⌘V where you want it", Ink.green, send: "mic.fill", pause: false, db: nil, copying: true)
    let voiceDB: [Double] = [-50, -44, -38, -36, -40, -46, -50, -54, -58, -62, -66]
    shot("8-voice-waiting.png", "SAY \"LISTEN\" · F1 TO TALK · WHISPER TURBO AUTO", white, send: "mic.fill", pause: false, db: voiceDB, wave: WaveView.yellow)
    shot("9-voice-take.png", "● 0:04 · WHISPER TURBO AUTO · SAY \"SEND\"", Ink.red, send: "arrow.up", pause: true, db: [-40, -30, -24, -22, -26, -30, -34, -40, -46, -52, -60], wave: Ink.green)
    shot("11-no-auto-correct.png", "F1 TO TALK · WHISPER TURBO AUTO", white, send: "mic.fill", pause: false, db: nil, autoCorrect: false)
    shot("10-line-below.png", "F1 TO TALK · WHISPER TURBO AUTO · AUTO CORRECT: CLAUDE HAIKU", white, send: "mic.fill", pause: false, db: nil, below: true)
    exit(0)
}

Crash.install()
Crash.testIfAsked()
let app = NSApplication.shared
Crash.afterApp()
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
let stripe = Stripe()
app.run()
