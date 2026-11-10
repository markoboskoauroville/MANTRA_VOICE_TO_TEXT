// ⚙ of Voice to Text (Mantra), two tabs (request 14): Settings (the hotkey, the keys (a file picker; only how many were
// found is ever shown), and his own additions to the style: "you can write the style prompt automatically,
// but in settings I can also add some things to it") and Transcription history (History.swift).
import AppKit
import AVFoundation
import Speech

final class SettingsWindow: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let onChange: () -> Void
    let hotkey = NSPopUpButton()
    let extra = NSTextView()
    // v13: the engine panel (TTT's): one row per engine, its radio, its free/paid label and minutes, its numbered key
    var engineRadios: [String: NSButton] = [:]
    var engineFree: [String: NSTextField] = [:]
    var engineKey: [String: NSTextField] = [:]
    let anthropicLabel = NSTextField(labelWithString: "")
    let croatianTick = NSButton(checkboxWithTitle: "Auto correct Croatian takes too (off: Croatian goes in as the engine heard it)", target: nil, action: nil)
    let importResult = NSTextField(wrappingLabelWithString: "")
    // Voice to Text (Mantra): the model downloaded from here, and a key pasted (never shown again)
    let modelButton = NSButton(title: "", target: nil, action: nil)
    let modelBar = NSProgressIndicator()
    let modelLabel = NSTextField(labelWithString: "")
    let keyField = NSSecureTextField()
    // v3, one app: who hears (Marko's MANTRA_VOICE ears or the built-in Whisper), the names, the duck
    let earsButton = NSPopUpButton()
    let namesField = NSTextField()
    let duckTick = NSButton(checkboxWithTitle: "Speakers at 6 % while listening, back after", target: nil, action: nil)
    let device = NSPopUpButton()
    // v20 (Marko, 31.10.2026: "add the tick marks after hide so I can turn off after hide"): the same setting, named plainly
    // under its own heading; unticked, the blob never hides by itself (only ✕ sends it away)
    let autoHide = NSButton(checkboxWithTitle: "Hide the blob 3 s after each take and bring it to the screen I type on (untick: it stays, fixed where I put it)", target: nil, action: nil)
    // v15: the start and stop sounds' levels (Marko, 31.10.2026)
    let startLevel = NSSlider(value: Double(Prefs.startVolume) * 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    let stopLevel = NSSlider(value: Double(Prefs.stopVolume) * 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    let startPct = NSTextField(labelWithString: ""), stopPct = NSTextField(labelWithString: "")
    // v19: the STYLE button's own Claude (Marko, 31.10.2026), never None, Haiku by default
    let styleButton = NSPopUpButton()
    // v21: voice activation, its words in the label from VoiceWords (Voice.swift), off by default
    let voiceTick = NSButton(checkboxWithTitle: VoiceWords.label, target: nil, action: nil)
    let voicePermissions = NSButton(title: "PERMISSIONS", target: nil, action: nil)
    var permTimer: Timer?
    let tabs = NSTabView()
    // v12 (Marko, 8.11.2026: "remove from drop down menus options. It must be very simple"): the models are round buttons,
    // every choice in sight, one click
    var langRadios: [String: NSButton] = [:]
    var styleRadios: [StyleEngine: NSButton] = [:]
    var styleButtonRadios: [StyleEngine: NSButton] = [:]
    var whisperRow: NSStackView!
    var history: HistoryPane!

    init(onChange: @escaping () -> Void, typeText: @escaping (String) -> Void) {
        self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 940), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Voice to Text (Mantra) v\(appVersion)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 600)
        super.init()
        history = HistoryPane(typeText: typeText) { [weak self] in self?.window.orderOut(nil); NSApp.hide(nil) }

        func label(_ s: String, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = bold ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12)
            return l
        }
        func row(_ views: [NSView]) -> NSStackView {
            let r = NSStackView(views: views); r.orientation = .horizontal; r.spacing = 8; return r
        }

        hotkey.addItems(withTitles: HotKey.keys.map(\.0))
        hotkey.selectItem(withTitle: HotKey.chosen)
        hotkey.target = self; hotkey.action = #selector(hotkeyChanged)


        modelButton.target = self; modelButton.action = #selector(modelPressed)
        modelButton.setAccessibilityIdentifier("model")
        modelBar.isIndeterminate = false; modelBar.minValue = 0; modelBar.maxValue = 1; modelBar.style = .bar
        modelBar.widthAnchor.constraint(equalToConstant: 220).isActive = true
        modelLabel.textColor = .secondaryLabelColor
        showModel(); followModel()
        importResult.textColor = .secondaryLabelColor
        importResult.maximumNumberOfLines = 14
        importResult.lineBreakMode = .byWordWrapping
        importResult.preferredMaxLayoutWidth = 600
        importResult.isHidden = true                     // until a pick has something to say

        // THE KEYS (v13, TTT): no key field, no per-provider button: one picker (File…) that sorts every key by its shape and tests
        // it free, and Re-test. On Marko's Mac the key notes in ~/Downloads/API come in by themselves (KeyImporter.loadFamous).
        let importButton = NSButton(title: "Import keys from file…", target: self, action: #selector(chooseAllKeys))
        importButton.setAccessibilityIdentifier("importKeys")
        let retestButton = NSButton(title: "Re-test keys", target: self, action: #selector(retestKeys))
        retestButton.setAccessibilityIdentifier("retestKeys")
        let keyRows: [NSView] = [row([importButton, retestButton]), importResult]

        // THE ENGINE PANEL (v13, TTT's long-press panel): all 13, one click selects; the accuracy of the language chosen beside
        // the name, free or paid and the minutes, and the numbered key in use ("Groq 2/3 in use")
        var engineRows: [NSView] = []
        for s in Catalog.all {
            let b = NSButton(radioButtonWithTitle: s.name, target: self, action: #selector(enginePicked(_:)))
            b.identifier = .init(s.id); b.setAccessibilityIdentifier("engine-" + s.id)
            let free = label(s.label); free.textColor = .secondaryLabelColor
            let key = label("")
            b.widthAnchor.constraint(equalToConstant: 280).isActive = true
            free.widthAnchor.constraint(equalToConstant: 190).isActive = true
            key.widthAnchor.constraint(equalToConstant: 220).isActive = true
            for t in [free, key] { t.lineBreakMode = .byTruncatingTail }
            engineRadios[s.id] = b; engineFree[s.id] = free; engineKey[s.id] = key
            engineRows.append(row([b, free, key]))
        }

        // THE MODELS (v12): recognition first, then the correction
        func radios<T>(_ items: [(T, String)], _ sel: Selector, into: (T, NSButton) -> Void) -> NSStackView {
            row(items.map { v, t in
                let b = NSButton(radioButtonWithTitle: t, target: self, action: sel)
                into(v, b); return b
            })
        }
        let langRow = radios([("en", "English"), ("hr", "Croatian"), ("auto", "Auto (Croatian and English)")], #selector(langPicked(_:))) { l, b in
            b.identifier = .init(l); b.setAccessibilityIdentifier("lang-" + l); langRadios[l] = b }
        let styleRow = radios(StyleEngine.allCases.map { ($0, $0.menuTitle) }, #selector(stylePicked(_:))) { e, b in
            b.identifier = .init(e.rawValue); b.setAccessibilityIdentifier("correct-" + e.rawValue); styleRadios[e] = b }
        let styleButtonRow = radios(StyleButtonEngine.choices.map { ($0, $0.menuTitle) }, #selector(styleButtonPicked(_:))) { e, b in
            b.identifier = .init(e.rawValue); b.setAccessibilityIdentifier("stylebutton-" + e.rawValue); styleButtonRadios[e] = b }
        whisperRow = row([modelButton, modelBar, modelLabel])
        paintChoices()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        extra.isRichText = false
        extra.font = .systemFont(ofSize: 12)
        extra.string = Prefs.extra
        extra.delegate = self
        extra.autoresizingMask = [.width]
        scroll.documentView = extra
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 500).isActive = true

        let note = label("Auto correct follows your style (normal capitals, no dashes, the language you spoke). Anything you write here is added to it.")
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 3
        note.preferredMaxLayoutWidth = 500

        device.target = self; device.action = #selector(deviceChanged)
        autoHide.state = Prefs.autoHide ? .on : .off
        autoHide.target = self; autoHide.action = #selector(autoHideChanged)
        fillDevices()
        for (sl, pct, sel) in [(startLevel, startPct, #selector(startLevelChanged)), (stopLevel, stopPct, #selector(stopLevelChanged))] {
            sl.target = self; sl.action = sel; sl.isContinuous = true
            sl.widthAnchor.constraint(equalToConstant: 220).isActive = true
            pct.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            pct.widthAnchor.constraint(equalToConstant: 44).isActive = true
            pct.stringValue = "\(Int(sl.doubleValue.rounded())) %"
        }
        let startLabel = label("Start"), stopLabel = label("Stop")
        startLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        stopLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let soundRows: [NSView] = [
            label("The sounds when listening starts and stops", bold: true),
            row([startLabel, startLevel, startPct, NSButton(title: "Play", target: self, action: #selector(playStart))]),
            row([stopLabel, stopLevel, stopPct, NSButton(title: "Play", target: self, action: #selector(playStop))]),
        ]

        for e in StyleButtonEngine.choices {
            styleButton.addItem(withTitle: e.menuTitle)
            styleButton.lastItem?.representedObject = e.rawValue
        }
        styleButton.selectItem(at: StyleButtonEngine.choices.firstIndex(of: StyleButtonEngine.current) ?? 0)
        styleButton.target = self; styleButton.action = #selector(styleButtonChanged)
        styleButton.setAccessibilityIdentifier("styleButtonEngine")
        let styleNote = label("Click into any text box, then STYLE on the blob: the selection, or the whole text of the box, is corrected in place by this Claude (Anthropic). Independent of auto correct after a take.")
        styleNote.lineBreakMode = .byWordWrapping
        styleNote.maximumNumberOfLines = 3
        styleNote.preferredMaxLayoutWidth = 500

        voiceTick.state = VoiceWords.enabled ? .on : .off
        voiceTick.target = self; voiceTick.action = #selector(voiceChanged)
        voiceTick.setAccessibilityIdentifier("voiceActivation")
        voicePermissions.isBordered = false
        voicePermissions.attributedTitle = NSAttributedString(string: "PERMISSIONS", attributes: [
            .foregroundColor: NSColor(red: 0xE8 / 255.0, green: 0xA3 / 255.0, blue: 0x3D / 255.0, alpha: 1),
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)])
        voicePermissions.target = self; voicePermissions.action = #selector(openVoicePermissions)
        voicePermissions.setAccessibilityIdentifier("permissions")
        let voiceNote = label("Say the start word to begin a take, the end word to send it (as F1). Apple's speech recognition on this Mac, nothing sent out; the words are cut from the text.")
        voiceNote.lineBreakMode = .byWordWrapping
        voiceNote.maximumNumberOfLines = 2
        voiceNote.preferredMaxLayoutWidth = 700
        showVoicePermissions()

        for e in [Ears.server, Ears.builtIn] { earsButton.addItem(withTitle: e.title); earsButton.lastItem?.representedObject = e.rawValue }
        earsButton.selectItem(at: Ears.current == .server ? 0 : 1)
        earsButton.target = self; earsButton.action = #selector(earsChanged)
        earsButton.setAccessibilityIdentifier("ears")
        earsButton.isHidden = !Ears.serverHere                 // only where the MANTRA_VOICE ears live
        duckTick.state = Duck.enabled ? .on : .off
        duckTick.target = self; duckTick.action = #selector(duckChanged)
        duckTick.setAccessibilityIdentifier("duck")
        namesField.stringValue = Prefs.names
        namesField.placeholderString = "names to spell right, e.g. Marko (never Marco), Auroville"
        namesField.widthAnchor.constraint(equalToConstant: 500).isActive = true
        namesField.target = self; namesField.action = #selector(namesChanged)
        namesField.delegate = self
        namesField.setAccessibilityIdentifier("names")
        // by importance (Marko, 8.11.2026): 1 the key, 2 the recognition model, 3 the correction model, 4 their API keys
        croatianTick.state = Prefs.correctCroatian ? .on : .off
        croatianTick.target = self; croatianTick.action = #selector(croatianChanged)
        croatianTick.setAccessibilityIdentifier("correctCroatian")
        var views: [NSView] = []
        views.append(label("1 · The key that starts and stops listening", bold: true)); views.append(hotkey)
        views.append(label("2 · Recognition engine: who writes down what you say (13, the same as TTT; the % is the accuracy in this language)", bold: true))
        views.append(row([label("Language"), langRow]))
        views.append(contentsOf: engineRows)
        views.append(whisperRow)
        views.append(label("3 · Correction model: who cleans the text after each take (Anthropic)", bold: true)); views.append(styleRow)
        views.append(row([label("The STYLE button"), styleButtonRow])); views.append(croatianTick); views.append(anthropicLabel)
        views.append(label("4 · API keys: read by themselves from ~/Downloads/API; no key is ever shown, only its number", bold: true))
        views.append(contentsOf: keyRows)
        views.append(label("Recording device", bold: true)); views.append(device)
        views.append(label("After hide · while listening", bold: true)); views.append(autoHide); views.append(duckTick)
        views.append(label("Voice activation", bold: true)); views.append(row([voiceTick, voicePermissions])); views.append(voiceNote)
        views.append(contentsOf: soundRows)
        views.append(label("Your additions to auto correct and to STYLE", bold: true)); views.append(note)
        views.append(row([label("Names"), namesField])); views.append(scroll)
        let col = NSStackView(views: views)
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 10
        col.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        // v13: the page scrolls (the engine panel made it taller than a screen): nothing is cut
        let settingsPage = NSScrollView()
        settingsPage.hasVerticalScroller = true
        settingsPage.drawsBackground = false
        let holder = FlippedView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        col.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(col)
        settingsPage.documentView = holder
        NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                                     col.topAnchor.constraint(equalTo: holder.topAnchor),
                                     col.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                                     holder.widthAnchor.constraint(equalTo: settingsPage.contentView.widthAnchor)])
        for (title, page) in [("Settings", settingsPage), ("Transcription history", history.view)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = page
            tabs.addTabViewItem(item)
        }
        // the ✕ in the far upper-right corner closes this window (Marko, 19.10.2026: "There is X to close the dialog in
        // every dialog, same."); the tabs keep the rest.
        // v27 (Marko, 31.10.2026: "Each needs to have the same user interface elements. On, off and top. Please build it
        // in every application."): the pill is full (never two buttons in one place), so the first row lives here, above
        // the tabs: ON OFF at the left, the name in the centre, TOP and the ✕ at the right (MANTRA_MANIFEST swift-apps.md,
        // "The first row of every app"). OFF quits, refused while a take is open; TOP keeps this window above the others.
        let box = NSView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(tabs)
        let x = closeX(self, #selector(closeWindow), tip: "Close; Voice to Text (Mantra) stays on")
        x.setAccessibilityIdentifier("close"); x.setAccessibilityLabel("Close window")
        let on = rowWord("ON", Ink.green, id: "on", label: "On", #selector(nothing))
        on.toolTip = "Voice to Text (Mantra) runs"
        let off = rowWord("OFF", Ink.grey, id: "off", label: "Off", #selector(offPressed))
        off.toolTip = "Quit Voice to Text (Mantra) (not while a take is open)"
        topWord = rowWord("TOP", Ink.grey, id: "top", label: "Top", #selector(topPressed))
        paintTop()
        let name = NSTextField(labelWithString: "Voice to Text (Mantra)")
        name.font = .systemFont(ofSize: 13, weight: .bold)
        offNote.font = .systemFont(ofSize: 11); offNote.textColor = Ink.amber
        for v in [x, on, off, topWord!, name, offNote] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(v) }
        NSLayoutConstraint.activate([
            on.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16), on.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            off.leadingAnchor.constraint(equalTo: on.trailingAnchor, constant: 10), off.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            offNote.leadingAnchor.constraint(equalTo: off.trailingAnchor, constant: 12), offNote.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            name.centerXAnchor.constraint(equalTo: box.centerXAnchor), name.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            topWord.trailingAnchor.constraint(equalTo: x.leadingAnchor, constant: -10), topWord.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            x.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6), x.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            tabs.leadingAnchor.constraint(equalTo: box.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: box.topAnchor, constant: 32), tabs.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        window.contentView = box
        showKeys()
    }

    // The microphones macOS has now; "System default" follows whatever macOS uses.
    func fillDevices() {
        device.removeAllItems()
        device.addItem(withTitle: "System default (\(AVCaptureDevice.default(for: .audio)?.localizedName ?? "none"))")
        device.lastItem?.representedObject = nil
        for d in InputDevice.all() {
            device.addItem(withTitle: d.localizedName)
            device.lastItem?.representedObject = d.uniqueID
        }
        if let id = InputDevice.chosenID, let i = device.itemArray.firstIndex(where: { $0.representedObject as? String == id }) {
            device.selectItem(at: i)
        } else { device.selectItem(at: 0) }
    }

    @objc func startLevelChanged() {
        Prefs.startVolume = Float(startLevel.doubleValue / 100); startPct.stringValue = "\(Int(startLevel.doubleValue.rounded())) %"
    }
    @objc func stopLevelChanged() {
        Prefs.stopVolume = Float(stopLevel.doubleValue / 100); stopPct.stringValue = "\(Int(stopLevel.doubleValue.rounded())) %"
    }
    @objc func playStart() { Chime.play(start: true) }
    @objc func playStop() { Chime.play(start: false) }

    @objc func styleButtonChanged() {
        if let raw = styleButton.selectedItem?.representedObject as? String, let e = StyleEngine(rawValue: raw) { StyleButtonEngine.current = e }
    }

    // the tick is the one place that asks: speech recognition, then the microphone (never at launch or at --login)
    @objc func voiceChanged() {
        VoiceWords.enabled = voiceTick.state == .on
        appendLog("voice activation: \(VoiceWords.enabled ? "on" : "off")")
        guard VoiceWords.enabled else { stripe.voice.stop(); stripe.voiceMeter(); showVoicePermissions(); return }
        SFSpeechRecognizer.requestAuthorization { _ in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.showVoicePermissions(); stripe.voiceChanged() }
            }
        }
    }

    // MANTRA_MANIFEST swift-apps.md: PERMISSIONS only while one is missing, a click goes straight to its page, read every 2 s
    func showVoicePermissions() {
        voicePermissions.isHidden = !(VoiceWords.enabled && (!VoiceWords.authorized || !VoiceWords.micAllowed))
    }

    @objc func openVoicePermissions() {
        let pane = VoiceWords.authorized ? "Microphone" : "SpeechRecognition"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")!)
    }

    @objc func autoHideChanged() { Prefs.autoHide = autoHide.state == .on; appendLog("after hide: \(Prefs.autoHide ? "on" : "off")") }

    @objc func deviceChanged() {
        InputDevice.chosenID = device.selectedItem?.representedObject as? String
        if VoiceWords.enabled { stripe.voiceChanged() }        // v21: the commands are heard on the same microphone
    }

    @objc func retestKeys() {
        importResult.stringValue = "asking each key one free question…"; importResult.isHidden = false
        DispatchQueue.global().async {
            let r = KeyImporter.retest()
            DispatchQueue.main.async { self.importResult.stringValue = r; self.showKeys() }
        }
    }

    @objc func croatianChanged() {
        Prefs.correctCroatian = croatianTick.state == .on
        appendLog("auto correct Croatian: \(Prefs.correctCroatian ? "on" : "off")")
    }

    @objc func enginePicked(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, Catalog.byId(id) != nil else { return }
        HearEngine.setEngine(id)
        appendLog("recognition engine: \(HearEngine.current.title)")
        if id == "parakeet" || id == "whisper" { Ears.warm() }
        paintChoices(); onChange()
    }

    @objc func closeWindow() { window.performClose(nil) }

    // v12: the round buttons
    func paintChoices() {
        let h = HearEngine.current
        for (id, b) in engineRadios {
            b.state = id == h.id ? .on : .off
            if let sp = Catalog.byId(id) { b.title = Catalog.shown(sp, lang: h.lang) }
        }
        for (l, b) in langRadios { b.state = l == h.lang ? .on : .off }
        for (e, b) in styleRadios { b.state = e == StyleEngine.current ? .on : .off }
        for (e, b) in styleButtonRadios { b.state = e == StyleButtonEngine.current ? .on : .off }
        whisperRow?.isHidden = Ears.current == .server
    }
    @objc func langPicked(_ b: NSButton) {
        HearEngine.setLang(b.identifier?.rawValue ?? "auto")
        paintChoices(); onChange()
    }
    @objc func stylePicked(_ b: NSButton) {
        if let e = StyleEngine(rawValue: b.identifier?.rawValue ?? "") { StyleEngine.current = e; appendLog("correction model: \(e.title)") }
        paintChoices(); onChange()
    }
    @objc func styleButtonPicked(_ b: NSButton) {
        if let e = StyleEngine(rawValue: b.identifier?.rawValue ?? "") { StyleButtonEngine.current = e }
        paintChoices()
    }

    // v27: the first row's words (MANTRA_MANIFEST swift-apps.md, "The first row of every app")
    var topWord: NSButton!
    let offNote = NSTextField(labelWithString: "")
    var onTop: Bool { UserDefaults.standard.bool(forKey: "onTop") }
    func rowWord(_ title: String, _ colour: NSColor, id: String, label: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: colour])
        b.setAccessibilityIdentifier(id); b.setAccessibilityLabel(label)
        return b
    }
    @objc func nothing() {}
    // OFF quits, but never costs a take (the same guard as a build's quit)
    @objc func offPressed() {
        if stripe.recorder.recording || stripe.busy {
            offNote.stringValue = "a take is open: send or cancel it first"
            appendLog("OFF pressed: refused, a take is in progress")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.offNote.stringValue = "" }
            return
        }
        appendLog("OFF pressed: quit")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    @objc func topPressed() {
        UserDefaults.standard.set(!onTop, forKey: "onTop")
        paintTop()
    }
    // TOP green = this window above every other window; applied at once and every time the window is shown
    func paintTop() {
        topWord.attributedTitle = NSAttributedString(string: "TOP", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: onTop ? Ink.green : Ink.grey])
        topWord.setAccessibilityValue(onTop ? "on" : "off")
        topWord.toolTip = "Always on top: green, this window stays above every other window"
        window.level = onTop ? .floating : .normal
    }

    // tab 0 Settings, 1 Transcription history
    func show(tab: Int = 0) {
        fillDevices()
        DispatchQueue.global().async { let r = KeyImporter.loadFamous(); if !r.isEmpty { DispatchQueue.main.async { self.showKeys() } } }   // keys new in ~/Downloads/API come in by themselves
        paintChoices()
        showKeys()
        history.reload()
        showVoicePermissions()
        permTimer?.invalidate()
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, self.window.isVisible else { t.invalidate(); return }
            let was = self.voicePermissions.isHidden
            self.showVoicePermissions()
            if was != self.voicePermissions.isHidden, self.voicePermissions.isHidden, VoiceWords.enabled { stripe.voiceChanged() }
        }
        tabs.selectTabViewItem(at: tab)
        paintTop()                                              // v27: TOP as remembered
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// "Groq 2/3 in use" (the key the next take starts with), "3 keys", "no key"; never a key
    func keyText(_ p: Provider) -> String {
        let list = Keys.entries(p)
        if list.isEmpty { return "no key" }
        let m = Ring.memory(p)
        var t = p == .cloudflare || p == .chirp ? "1 account" : "\(list.count) key\(list.count == 1 ? "" : "s")"
        if let cur = m.current, let k = list.first(where: { Ring.fingerprint($0.key) == cur }) { t = Ring.name(p, k) + " in use" }
        let resting = list.filter { k in m.states[Ring.fingerprint(k.key)].map { !Ring.usable($0) } ?? false }.count
        if resting > 0 { t += " · \(resting) resting" }
        return t
    }

    func showKeys() {
        let lang = HearEngine.current.lang
        for s in Catalog.all {
            let ok = Catalog.available(s)
            engineRadios[s.id]?.isEnabled = ok
            engineRadios[s.id]?.title = Catalog.shown(s, lang: lang)
            let t = s.ring.map(keyText) ?? (ok ? "on this Mac" : "not on this Mac")
            engineKey[s.id]?.stringValue = t
            engineKey[s.id]?.textColor = ok ? .labelColor : .secondaryLabelColor
            if let p = s.ring {
                let m = Ring.memory(p)
                engineKey[s.id]?.toolTip = Keys.entries(p).enumerated().map { i, k in
                    let st = m.states[Ring.fingerprint(k.key)]
                    return "\(i + 1). \(k.title): " + (st.map { "\(KeyTest.word($0.verdict)) (\($0.detail))" } ?? "not asked yet")
                }.joined(separator: "\n")
            }
        }
        anthropicLabel.stringValue = "Anthropic (the correction): " + keyText(.anthropic)
    }

    @objc func hotkeyChanged() {
        HotKey.chosen = hotkey.titleOfSelectedItem ?? "F1"
        onChange()
    }

    func textDidChange(_ n: Notification) { Prefs.extra = extra.string }
    func controlTextDidChange(_ n: Notification) { if (n.object as? NSTextField) === namesField { Prefs.names = namesField.stringValue } }
    @objc func namesChanged() { Prefs.names = namesField.stringValue }
    @objc func duckChanged() {
        Duck.enabled = duckTick.state == .on
        appendLog("duck: \(Duck.enabled ? "on" : "off")")
    }
    @objc func earsChanged() {
        Ears.current = Ears(rawValue: earsButton.selectedItem?.representedObject as? String ?? "") ?? .builtIn
        appendLog("ears: \(Ears.current.title)")
        if Ears.current == .server { DispatchQueue.global().async { _ = VoiceServer.ensure() } } else { Whisper.warm() }
        onChange()
    }

    func pickFiles(_ title: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    func showModel() {
        let mb = Model.partSize / 1_000_000
        if Model.downloading {
            modelButton.title = "Pause"; modelButton.isEnabled = true; modelBar.isHidden = false
            modelBar.doubleValue = Double(Model.partSize) / Double(Model.bytes)
            return
        }
        modelBar.isHidden = !Model.started || Model.ready
        modelBar.doubleValue = Double(Model.partSize) / Double(Model.bytes)
        modelButton.title = Model.ready ? "Downloaded" : Model.started ? "Continue the download" : "Download the model"
        modelButton.isEnabled = !Model.ready
        modelLabel.stringValue = Model.ready ? "ready, works offline" : Model.started ? "\(mb) of 574 MB, goes on from there" : "needed before the first take"
    }

    /// the download's news reaches ⚙ whoever started it (the button, or the app itself at launch)
    func followModel() {
        Model.onProgress = { [weak self] f in
            guard let self else { return }
            self.modelBar.isHidden = false; self.modelBar.doubleValue = f
            self.modelButton.title = "Pause"
            self.modelLabel.stringValue = String(format: "%.0f %% of 574 MB", f * 100)
        }
        Model.onWait = { [weak self] w in self?.modelLabel.stringValue = w }
        Model.onDone = { [weak self] problem in
            self?.showModel()
            if let problem { self?.modelLabel.stringValue = problem } else { Whisper.warm() }
            self?.onChange()
        }
    }

    @objc func modelPressed() {
        if Model.downloading { Model.cancel(); showModel(); return }
        followModel()
        Model.download()
        showModel()
    }

    @objc func addPastedKey() {
        let k = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        keyField.stringValue = ""
        guard k.range(of: Provider.anthropic.pattern, options: .regularExpression) != nil else {
            importResult.stringValue = "That is not an Anthropic key: they start with sk-ant-."
            importResult.isHidden = false; return
        }
        let n = Keys.add(.anthropic, [KeyEntry(key: k, title: "key \(Keys.entries(.anthropic).count + 1)")])
        importResult.stringValue = n == 1 ? "Key added. Press Test to check it." : "This key was already there."
        importResult.isHidden = false
        showKeys()
    }

    @objc func chooseAllKeys() {
        let urls = pickFiles("Key files (several at once): Groq, Deepgram, AssemblyAI, Gemini, Cloudflare, Anthropic ...")
        guard !urls.isEmpty else { return }
        importResult.stringValue = "testing each key, free calls only…"
        importResult.isHidden = false
        DispatchQueue.global().async {
            let r = KeyImporter.importFiles(urls)
            DispatchQueue.main.async { self.importResult.stringValue = r; self.showKeys() }
        }
    }
}

// a scroll view's document that sits at the top
final class FlippedView: NSView { override var isFlipped: Bool { true } }
