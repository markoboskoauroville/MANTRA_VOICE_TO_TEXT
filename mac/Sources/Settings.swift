// ⚙ of Vox to Txt (Mantra), two tabs (request 14): Settings (the hotkey, the keys (a file picker; only how many were
// found is ever shown), and his own additions to the style: "you can write the style prompt automatically,
// but in settings I can also add some things to it") and Transcription history (History.swift).
import AppKit
import AVFoundation
import Speech

final class SettingsWindow: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let onChange: () -> Void
    let hotkey = NSPopUpButton()
    let hotkeyHR = NSPopUpButton()             // v47: the Croatian key
    let extra = NSTextView()
    // v13: the engine panel (TTT's): one row per engine, its radio, its free/paid label and minutes, its numbered key
    var cards: [String: [String: EngineCard]] = [:]          // language -> engine id -> card (v17, TTT's two columns)
    var heads: [String: ColumnHead] = [:]
    let benchButton = NSButton(title: "Benchmark engines", target: nil, action: nil)
    let benchNote = NSTextField(wrappingLabelWithString: "")
    let testTick = NSButton(checkboxWithTitle: "TEST: score each take against the reference sentence (speak it, any engine; the stars follow)", target: nil, action: nil)
    let testField = NSTextField()
    // v20: the FRANKFURT switch (the relay on chromium-vm calls the cloud engines; direct stays as the fallback)
    let frankfurtTick = NSButton(checkboxWithTitle: "FRANKFURT: send the audio to the relay in Frankfurt, which calls the engines (each engine's direct path is the fallback)", target: nil, action: nil)
    let routeHeader = NSTextField(labelWithString: "Route: checking…")
    let frankfurtNote = NSTextField(wrappingLabelWithString: "")
    let anthropicLabel = NSTextField(labelWithString: "")
    let croatianTick = NSButton(checkboxWithTitle: "Auto correct Croatian takes too (off: Croatian goes in as the engine heard it)", target: nil, action: nil)
    let importResult = NSTextField(wrappingLabelWithString: "")
    // Vox to Txt (Mantra): the model downloaded from here, and a key pasted (never shown again)
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
    let suggestSwitch = NSSwitch()             // v51: typing suggestions
    let suggestModel = NSTextField(labelWithString: "")      // v55: the local model's state
    let suggestModelPicker = NSPopUpButton()                  // v56: which model file (or none)
    let fixTick = NSButton(checkboxWithTitle: "Corrections from the shared database (TTT): the Croatian dictionary fix, names, the spelling table, what you corrected before", target: nil, action: nil)
    let suggestPermissions = NSButton(title: "PERMISSIONS", target: nil, action: nil)
    var permTimer: Timer?
    let tabs = NSTabView()
    // v12 (Marko, 8.11.2026: "remove from drop down menus options. It must be very simple"): the models are round buttons,
    // every choice in sight, one click
    var langRadios: [String: NSButton] = [:]
    var styleRadios: [StyleEngine: NSButton] = [:]
    var styleButtonRadios: [StyleEngine: NSButton] = [:]
    var whisperRow: NSStackView!
    var history: HistoryPane!
    var fillWidth: [NSView] = []               // v49: the parts of a tab that take the page's whole width
    // v28: the TEXT selector, the typing target and its two ticks
    static let historyTab = 0          // v34: History is the first tab and the default one
    var modeRadios: [TextMode: NSButton] = [:]
    let targetLabel = NSTextField(labelWithString: "none yet: click into a text box")
    let pasteTick = NSButton(checkboxWithTitle: "When a box ignores Accessibility writing, bring its app to the front and paste (your clipboard is put back)", target: nil, action: nil)
    let clickTick = NSButton(checkboxWithTitle: "When the box cannot be focused, click into it (only if the click lands on that same box)", target: nil, action: nil)
    var targetTimer: Timer?
    // v28 (Marko, 15.11.2026: "quick switches at the top, MAC switches ... telling me for correction and styling which model
    // are used"): above the tabs, always in sight
    let qCorrect = NSSwitch(), qFrankfurt = NSSwitch(), qTest = NSSwitch()
    let qCorrectModel = NSPopUpButton(), qStyleModel = NSPopUpButton()
    let qDetail = NSTextField(labelWithString: "")
    let output = NSPopUpButton()                 // v28: OUTPUT, the speaker of Vox's own sounds
    // v28: the engine columns and their family headings, laid out by arrange()
    var columns: [String: NSStackView] = [:]
    var familyLabels: [String: [String: NSTextField]] = [:]
    let orderPicker = NSSegmentedControl()

    init(onChange: @escaping () -> Void, typeText: @escaping (String) -> Void) {
        self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Vox to Txt (Mantra) v\(appVersion)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 560)
        window.appearance = NSAppearance(named: .darkAqua)      // v17: TTT's host look
        window.backgroundColor = Host.bg
        super.init()
        // v26: an engine picked from outside (Talk Mode's panel, POST /engines/select) shows on the cards at once
        DistributedNotificationCenter.default().addObserver(forName: .init("com.mantra.voicetotext.engineChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.paintChoices(); self?.onChange()
        }
        history = HistoryPane(typeText: typeText) { [weak self] in self?.window.orderOut(nil); NSApp.hide(nil) }
        history.onChange = { [weak self] in self?.paintChoices(); self?.onChange() }     // v48: its choices are the global ones

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
        hotkeyHR.addItems(withTitles: HotKey.keys.map(\.0))
        hotkeyHR.selectItem(withTitle: HotKey.chosenHR)
        hotkeyHR.target = self; hotkeyHR.action = #selector(hotkeyChanged)


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

        // THE ENGINE PANEL (v13, TTT's long-press panel): all 13, one click selects; the accuracy of the language chosen beside
        // the name, free or paid and the minutes, and the numbered key in use ("Groq 2/3 in use")
        // v17: TTT's Voice transcription buttons: two columns (Croatian H, English E), a radio card per engine
        // v28: the cards made once; arrange() lays them out BEST FIRST (Marko: "order the engines inside the settings by the
        // quality. At the top are the best ones from our test") or BY FAMILY (the families ordered by their best member)
        func column(_ lang: String, _ letter: String, _ title: String) -> NSStackView {
            let head = ColumnHead(frame: .zero); head.letter = letter; heads[lang] = head
            let t = label(title, bold: true); t.textColor = Host.muted
            cards[lang] = [:]
            for id in Catalog.all.map(\.id) {
                let c = EngineCard(id: id, lang: lang); c.onPick = { [weak self] l, i in self?.cardPicked(l, i) }
                cards[lang]![id] = c
            }
            familyLabels[lang] = [:]
            for (family, _) in SettingsWindow.families {
                let g = NSTextField(labelWithString: family)
                g.font = .systemFont(ofSize: 10.5, weight: .bold); g.textColor = Host.gold
                familyLabels[lang]![family] = g
            }
            let col = NSStackView(views: [t, head]); col.orientation = .vertical; col.alignment = .leading; col.spacing = 4
            col.setCustomSpacing(8, after: head)
            head.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
            columns[lang] = col
            arrange(lang)
            return col
        }
        orderPicker.segmentCount = 2
        orderPicker.setLabel("BEST FIRST", forSegment: 0); orderPicker.setLabel("BY FAMILY", forSegment: 1)
        orderPicker.selectedSegment = SettingsWindow.byFamily ? 1 : 0
        orderPicker.target = self; orderPicker.action = #selector(orderChanged)
        orderPicker.setAccessibilityIdentifier("engineOrder"); orderPicker.setAccessibilityLabel("Engine order")
        let twoColumns = NSStackView(views: [column("hr", "H", "Croatian"), column("en", "E", "English")])
        twoColumns.orientation = .horizontal; twoColumns.distribution = .fillEqually; twoColumns.spacing = 16; twoColumns.alignment = .top
        fillWidth.append(twoColumns)          // v49: the two columns share the page's whole width
        frankfurtTick.target = self; frankfurtTick.action = #selector(frankfurtChanged)
        frankfurtTick.setAccessibilityIdentifier("frankfurt"); frankfurtTick.state = Frankfurt.on ? .on : .off
        frankfurtNote.font = .systemFont(ofSize: 11); frankfurtNote.textColor = Host.muted
        frankfurtNote.preferredMaxLayoutWidth = 780; frankfurtNote.maximumNumberOfLines = 3
        frankfurtNote.stringValue = "Parakeet and Whisper on this Mac run here; the other eleven engines run in Frankfurt while the relay answers."
        testTick.target = self; testTick.action = #selector(testChanged); testTick.setAccessibilityIdentifier("statsTest")
        testField.stringValue = Stats.reference; testField.target = self; testField.action = #selector(testChanged)
        fillWidth.append(testField)
        testField.setAccessibilityIdentifier("statsReference"); testField.lineBreakMode = .byWordWrapping
        testField.usesSingleLineMode = false; testField.cell?.wraps = true; testField.cell?.isScrollable = false
        testField.widthAnchor.constraint(equalToConstant: 640).isActive = true
        testTick.state = Stats.testOn ? .on : .off
        benchButton.target = self; benchButton.action = #selector(benchPressed)
        benchButton.setAccessibilityIdentifier("benchmark")
        benchNote.font = .systemFont(ofSize: 11); benchNote.textColor = Host.muted
        benchNote.preferredMaxLayoutWidth = 700; benchNote.maximumNumberOfLines = 3
        benchNote.stringValue = Settings_benchSummary()

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
        paintChoices(); showKeys()

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
        fillWidth.append(scroll)

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
        // v51 (Marko, 17.11.2026: "it offers me corrected words or finishing what I'm typing ... every time I press alt space"):
        // the switch stands before its name; PERMISSIONS (amber) only while macOS withholds the keys
        suggestSwitch.target = self; suggestSwitch.action = #selector(suggestChanged)
        suggestSwitch.setAccessibilityIdentifier("typingSuggestions"); suggestSwitch.setAccessibilityLabel("Typing suggestions")
        suggestPermissions.isBordered = false
        suggestPermissions.attributedTitle = voicePermissions.attributedTitle
        suggestPermissions.target = self; suggestPermissions.action = #selector(openSuggestPermissions)
        suggestPermissions.setAccessibilityIdentifier("typingPermissions")
        let suggestWord = label("TYPING SUGGESTIONS", bold: true)
        let suggestNote = label("While you type in any app, up to three suggestions (the word finished, or corrected) show on the blob and in the menu bar. Option+Space puts in the first, a click any of them; only the word being typed is replaced. Croatian and English, learned from your own dictations. Off in password boxes and terminals. Nothing you type is stored.")
        suggestNote.lineBreakMode = .byWordWrapping; suggestNote.maximumNumberOfLines = 4; suggestNote.textColor = Host.muted
        // v56: the switch and the local model on one grid: the names end on one line, the controls begin on one line
        suggestModelPicker.target = self; suggestModelPicker.action = #selector(suggestModelChanged)
        suggestModelPicker.setAccessibilityIdentifier("localModel"); suggestModelPicker.setAccessibilityLabel("Local model")
        let modelWord = label("LOCAL MODEL", bold: true)
        let suggestGrid = NSGridView(views: [
            [suggestSwitch, row([suggestWord, suggestPermissions])],
            [modelWord, suggestModelPicker],
        ])
        suggestGrid.rowSpacing = 8; suggestGrid.columnSpacing = 8
        suggestGrid.rowAlignment = .none; suggestGrid.yPlacement = .center
        suggestGrid.column(at: 0).xPlacement = .trailing
        suggestGrid.column(at: 1).xPlacement = .leading
        for i in 0..<suggestGrid.numberOfRows { suggestGrid.row(at: i).height = 24 }
        suggestRow = NSStackView(views: [suggestGrid])
        suggestModel.font = .systemFont(ofSize: 11); suggestModel.textColor = Host.muted
        suggestModel.setAccessibilityIdentifier("localModelState")
        // v53: TTT's corrections on or off (the dictionary fix for Croatian, the names, the spelling table, what was learned)
        fixTick.state = Fix.on ? .on : .off
        fixTick.target = self; fixTick.action = #selector(fixChanged)
        fixTick.setAccessibilityIdentifier("tttCorrections")
        suggestNoteLabel = suggestNote
        paintTyping()

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
        namesField.setContentHuggingPriority(.init(1), for: .horizontal)
        namesField.target = self; namesField.action = #selector(namesChanged)
        namesField.delegate = self
        namesField.setAccessibilityIdentifier("names")
        // by importance (Marko, 8.11.2026): 1 the key, 2 the recognition model, 3 the correction model, 4 their API keys
        croatianTick.state = Prefs.correctCroatian ? .on : .off
        croatianTick.target = self; croatianTick.action = #selector(croatianChanged)
        croatianTick.setAccessibilityIdentifier("correctCroatian")
        routeHeader.font = .systemFont(ofSize: 17, weight: .bold); routeHeader.textColor = Host.muted
        routeHeader.setAccessibilityIdentifier("routeHeader"); routeHeader.setAccessibilityLabel("Route")
        // v28 (Marko, 15.11.2026: "When I open my settings, it's a huge window with many things, and what is at the bottom is
        // difficult to even access ... I think you need to go with tabs. Maybe the engines should also be grouped"): one tab
        // per subject, each fitting the window; the engines grouped by family in each column
        let modeCol = NSStackView(); modeCol.orientation = .vertical; modeCol.alignment = .leading; modeCol.spacing = 6
        for m in TextMode.allCases {
            let b = NSButton(radioButtonWithTitle: "\(m.title.uppercased()) (\(m.short)): \(m.explain)", target: self, action: #selector(modePicked(_:)))
            b.identifier = .init(m.rawValue); b.setAccessibilityIdentifier("textmode-" + m.rawValue); modeRadios[m] = b
            modeCol.addArrangedSubview(b)
        }
        pasteTick.state = Prefs.pasteFallback ? .on : .off; pasteTick.target = self; pasteTick.action = #selector(typingTicks)
        pasteTick.setAccessibilityIdentifier("pasteFallback")
        clickTick.state = Prefs.clickToFocus ? .on : .off; clickTick.target = self; clickTick.action = #selector(typingTicks)
        clickTick.setAccessibilityIdentifier("clickToFocus")
        targetLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular); targetLabel.textColor = Host.sand
        targetLabel.setAccessibilityIdentifier("target")
        func para(_ t: String, _ w: CGFloat = 780) -> NSTextField {
            let l = label(t); l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 4; l.preferredMaxLayoutWidth = w
            l.textColor = Host.muted; return l
        }
        let enginesTab: [NSView] = [routeHeader,
                                    row([label("Language", bold: true), langRow]),
                                    row([label("Who writes down what you say, one engine per language (time · stars)", bold: true), orderPicker]),
                                    twoColumns, whisperRow!]
        let namesRow = row([label("Names"), namesField]); fillWidth.append(namesRow)
        let textTab: [NSView] = [label("What auto correct and STYLE do (the second selector on the blob)", bold: true), modeCol,
                                 label("Corrections without a model", bold: true), fixTick,
                                 label("Auto correct after each take (Anthropic)", bold: true), styleRow, croatianTick,
                                 label("The STYLE button's Claude", bold: true), styleButtonRow, styleNote,
                                 label("Your additions to auto correct and to STYLE", bold: true), note,
                                 namesRow, scroll]
        let typingNote = para("The text box you clicked into last, in any app: the words of a take are typed there, and STYLE restyles it (its selection, or all of it). Clicking the blob or STYLE never changes it. Accessibility first; if the box ignores that, its app comes to the front and the text is pasted (your clipboard is put back); COPY only when nothing else works.")
        let typingTab: [NSView] = [label("The keys that start and stop listening", bold: true),
                                   row([label("English"), hotkey, label("Croatian"), hotkeyHR]),
                                   label("Where the words go", bold: true), typingNote,
                                   row([label("Last text box:"), targetLabel]), pasteTick, clickTick,
                                   label("After hide", bold: true), autoHide,
                                   label("Voice activation", bold: true), row([voiceTick, voicePermissions]), voiceNote,
                                   suggestRow, suggestNoteLabel, suggestModel]
        let keysTab: [NSView] = [label("API keys: read by themselves from ~/Downloads/API; no key is ever shown, only its number", bold: true),
                                 row([importButton, retestButton]), importResult, anthropicLabel,
                                 label("Route", bold: true), frankfurtTick, frankfurtNote]
        // v72: the same lines in the Sound tab, with what they do
        let systemNote = para("The microphone and the speaker of the whole Mac, as in System Settings, Sound: every app that follows the system (Vox, Talk Mode, the Voice Engine, Speechify, browsers) changes with them. Click a name to choose; virtual loops (BlackHole, NDI, Zoom, Iriun) are listed apart and asked again. UNDO goes back to the device before. Ableton Live keeps its own devices.")
        var soundTab: [NSView] = [label("Microphone and speaker of the whole Mac", bold: true), SystemAudioView(fontSize: 14), systemNote,
                                  label("While listening", bold: true), duckTick]
        soundTab.append(contentsOf: soundRows)
        let testTab: [NSView] = [label("Benchmark", bold: true), row([benchButton, benchNote]),
                                 label("TEST mode", bold: true), testTick, testField]
        let tabsContent: [(String, [NSView])] = [("Engines", enginesTab), ("Text", textTab), ("Typing", typingTab),
                                                 ("Keys", keysTab), ("Sound", soundTab), ("Test", testTab)]
        addTab("History", history.view)           // v34 (Marko, 16.11.2026: "History first, please")
        for (title, views) in tabsContent { addTab(title, page(views)) }
        let about: [NSView] = [
            label("Vox to Txt (Mantra) · version \(appVersion)", bold: true),
            para("F1 talks; the words are typed into the text box you clicked into last. Two selectors on the blob: the language (EN · HR · AUTO) and the text mode (STY · S+C · COR)."),
            para("Local API on 127.0.0.1:8865: GET /status, GET /engines, POST /hear?lang=, POST /mode, GET /target, POST /transcribe, GET /job/<id>."),
            para("Log: ~/Library/Logs/voice-to-text-mantra.log"),
        ]
        addTab("About", page(about))
        // the ✕ in the far upper-right corner closes this window (Marko, 19.10.2026: "There is X to close the dialog in
        // every dialog, same."); the tabs keep the rest.
        // v27 (Marko, 31.10.2026: "Each needs to have the same user interface elements. On, off and top. Please build it
        // in every application."): the pill is full (never two buttons in one place), so the first row lives here, above
        // the tabs: ON OFF at the left, the name in the centre, TOP and the ✕ at the right (MANTRA_MANIFEST swift-apps.md,
        // "The first row of every app"). OFF quits, refused while a take is open; TOP keeps this window above the others.
        let box = DropBox()          // v15: a file dropped on the window is transcribed (History tab)
        box.onDrop = { [weak self] url in self?.tabs.selectTabViewItem(at: SettingsWindow.historyTab); self?.history.files.start(url) }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(tabs)
        let quick = quickRow()
        quick.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(quick)
        // v33 (Marko, 16.11.2026: "ON-OFF needs to go out of this application ... this X is actually becoming OFF button ... it
        // closes application completely. On the left side ... small speakers which is green when I select it ... gray"):
        // the ✕ quits the app (not while a take is open); the speaker is the start and stop sounds on or off
        let x = closeX(self, #selector(offPressed), tip: "Quit Vox to Txt (Mantra) completely (not while a take is open)")
        x.setAccessibilityIdentifier("close"); x.setAccessibilityLabel("Quit")
        let on = NSButton(title: "", target: self, action: #selector(soundsPressed))
        on.isBordered = false; on.imagePosition = .imageOnly
        on.setAccessibilityIdentifier("sounds"); on.setAccessibilityLabel("Start and stop sounds")
        soundsButton = on; paintSounds()
        let off = on
        topWord = rowWord("TOP", Ink.grey, id: "top", label: "Top", #selector(topPressed))
        paintTop()
        let name = NSTextField(labelWithString: "Vox to Txt (Mantra)")
        name.font = .systemFont(ofSize: 13, weight: .bold)
        offNote.font = .systemFont(ofSize: 11); offNote.textColor = Ink.amber
        for v in [x, on, topWord!, name, offNote] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(v) }
        NSLayoutConstraint.activate([
            on.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16), on.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            offNote.leadingAnchor.constraint(equalTo: off.trailingAnchor, constant: 12), offNote.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            name.centerXAnchor.constraint(equalTo: box.centerXAnchor), name.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            topWord.trailingAnchor.constraint(equalTo: x.leadingAnchor, constant: -10), topWord.centerYAnchor.constraint(equalTo: x.centerYAnchor),
            x.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6), x.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            tabs.leadingAnchor.constraint(equalTo: box.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            quick.topAnchor.constraint(equalTo: box.topAnchor, constant: 34), quick.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            quick.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: quick.bottomAnchor, constant: 4), tabs.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        window.contentView = box
        showKeys()
        // v72: the MICROPHONE level is measured only while this window is on screen (the microphone is not held otherwise)
        for n in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(forName: n, object: window, queue: .main) { [weak self] note in
                guard let self else { return }
                let seen = note.name != NSWindow.willCloseNotification && self.window.isVisible && !self.window.isMiniaturized
                    && self.window.occlusionState.contains(.visible)
                if seen { SystemAudioMeter.shared.start() } else { SystemAudioMeter.shared.stop() }
            }
        }
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
    @objc func playStart() { Chime.play(start: true, force: true) }
    @objc func playStop() { Chime.play(start: false, force: true) }

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
    var suggestRow: NSStackView!
    var suggestNoteLabel: NSTextField!
    func paintTyping() {
        suggestSwitch.state = TypingSuggest.on ? .on : .off
        suggestPermissions.isHidden = !(TypingSuggest.on && TypingSuggest.shared.tapFailed)
        suggestModel.stringValue = "Local model: " + LocalModel.state
        suggestModelPicker.removeAllItems()
        suggestModelPicker.addItem(withTitle: "None (dictionaries and your own layer only)")
        for f in LocalModel.files {
            let size = (try? FileManager.default.attributesOfItem(atPath: LocalModel.folder.appendingPathComponent(f).path)[.size] as? NSNumber)?.doubleValue ?? 0
            suggestModelPicker.addItem(withTitle: (f as NSString).deletingPathExtension + String(format: " · %.0f MB", size / 1_048_576))
            suggestModelPicker.lastItem?.representedObject = f
        }
        let current = LocalModel.on ? LocalModel.modelFile?.lastPathComponent : nil
        if let i = suggestModelPicker.itemArray.firstIndex(where: { $0.representedObject as? String == current }), current != nil { suggestModelPicker.selectItem(at: i) }
        else { suggestModelPicker.selectItem(at: 0) }
    }
    @objc func fixChanged() { Fix.on = fixTick.state == .on; appendLog("TTT corrections: \(Fix.on ? "on" : "off")") }
    @objc func suggestModelChanged() {
        LocalModel.choose(suggestModelPicker.selectedItem?.representedObject as? String)
        paintTyping()
    }
    @objc func suggestChanged() {
        TypingSuggest.on = suggestSwitch.state == .on
        appendLog("typing suggestions: switched \(TypingSuggest.on ? "on" : "off") in Settings")
    }
    @objc func openSuggestPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

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

    /// a card clicked: THAT language's engine (engine_<lang>); a take in that language uses it (HearEngine.current)
    func cardPicked(_ lang: String, _ id: String) {
        guard Catalog.byId(id) != nil else { return }
        UserDefaults.standard.set(id, forKey: "engine_" + lang)
        appendLog("recognition engine for \(lang.uppercased()): \(Catalog.byId(id)!.short)")
        if id == "parakeet" || id == "whisper" { Ears.warm() }
        paintChoices(); showKeys(); onChange()
    }

    func Settings_benchSummary() -> String {
        guard let d = Bench.stored() else { return "No measurement yet: English % are TTT's of 9.11.2026. The button speaks 12 sentences with the voice and writes each engine's % here." }
        let n = (d["results"] as? [String: Any])?.count ?? 0, bad = (d["failed"] as? [String: Any])?.count ?? 0
        return "English % measured \(d["date"] as? String ?? "") with 12 sentences (\(n) engines" + (bad > 0 ? ", \(bad) failed" : "") + "). Croatian % are TTT's of 9.11.2026."
    }
    @objc func frankfurtChanged() {
        Frankfurt.on = frankfurtTick.state == .on
        paintRoute()
        frankfurtNote.stringValue = "checking the relay…"
        DispatchQueue.global().async {
            if Frankfurt.on { Frankfurt.syncKeys() }
            let t = Frankfurt.on ? Frankfurt.summary() : "off: every engine runs direct"
            DispatchQueue.main.async { self.frankfurtNote.stringValue = "Parakeet and Whisper on this Mac run here; the other eleven run in Frankfurt while the relay answers. " + t }
        }
    }
    func paintRoute() {
        DispatchQueue.global().async {
            let h = Frankfurt.headline()
            DispatchQueue.main.async { self.routeHeader.stringValue = h.text; self.routeHeader.textColor = h.good ? Host.green : Host.gold; self.routeHeader.setAccessibilityValue(h.text) }
        }
    }
    func refreshFrankfurt() {
        paintRoute()
        DispatchQueue.global().async {
            let t = Frankfurt.on ? Frankfurt.summary() : "off: every engine runs direct"
            DispatchQueue.main.async { self.frankfurtNote.stringValue = "Parakeet and Whisper on this Mac run here; the other eleven run in Frankfurt while the relay answers. " + t }
        }
    }
    @objc func testChanged() {
        Stats.testOn = testTick.state == .on
        let r = testField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { Stats.reference = r }
        appendLog("TEST mode \(Stats.testOn ? "on" : "off"), reference: \(Stats.reference)")
    }
    /// the API changed the TEST mode
    func paintTest() { testTick.state = Stats.testOn ? .on : .off; testField.stringValue = Stats.reference }
    /// after a take or a rating: the names in the panel carry the new median and stars
    func refreshStats() { paintChoices(); showKeys() }
    @objc func benchPressed() {
        guard !Bench.running else { return }
        benchButton.isEnabled = false
        DispatchQueue.global().async {
            let r = Bench.run { t in DispatchQueue.main.async { self.benchNote.stringValue = t + "…" } }
            DispatchQueue.main.async {
                self.benchButton.isEnabled = true
                self.benchNote.stringValue = r.hasPrefix("FAILED") ? r : Settings_benchSummaryAfter(self)
                self.paintChoices(); self.showKeys()
            }
        }
    }

    @objc func closeWindow() { window.performClose(nil) }

    // v28: the engine families of the ENGINES tab (Marko: "grouped, by Whisper, because we have a few Whisper providers, then
    // Google engines, and so on")
    static let families: [(String, Set<String>)] = [
        ("WHISPER · PARAKEET", ["parakeet", "whisper", "groq_turbo", "groq_v3", "cloudflare"]),
        ("GOOGLE", ["gemini", "google_v1", "google_chirp"]),
        ("OTHERS", ["deepgram", "assemblyai", "speechmatics", "soniox", "elevenlabs"]),
    ]

    // MARK: v28 the quick row

    func quickRow() -> NSStackView {
        func word(_ t: String) -> NSTextField {
            let l = NSTextField(labelWithString: t); l.font = .monospacedSystemFont(ofSize: 11, weight: .bold); l.textColor = Host.ink; return l
        }
        for (p, id) in [(qCorrectModel, "quickCorrectionModel"), (qStyleModel, "quickStylingModel")] {
            for e in StyleButtonEngine.choices { p.addItem(withTitle: e.title); p.lastItem?.representedObject = e.rawValue }
            p.target = self; p.action = #selector(quickChanged(_:)); p.setAccessibilityIdentifier(id)
            p.controlSize = .small; p.font = .systemFont(ofSize: 11)
        }
        qCorrectModel.setAccessibilityLabel("Correction model"); qStyleModel.setAccessibilityLabel("Styling model")
        for (sw, id, label) in [(qCorrect, "quickCorrection", "Correction after each take"),
                                (qFrankfurt, "quickFrankfurt", "Frankfurt route")] {
            sw.target = self; sw.action = #selector(quickChanged(_:)); sw.controlSize = .small
            sw.setAccessibilityIdentifier(id); sw.setAccessibilityLabel(label)
        }
        qCorrect.toolTip = "Auto correct after each take, by this Claude (Anthropic), as the TEXT mode on the blob says"
        qStyleModel.toolTip = "The STYLE button on the blob: this Claude first (Opus by default), then Groq if it does not answer"
        qFrankfurt.toolTip = "The cloud engines are called from the relay in Frankfurt (direct is the fallback)"
        qDetail.font = .systemFont(ofSize: 11); qDetail.textColor = Host.muted; qDetail.lineBreakMode = .byTruncatingTail
        qDetail.setAccessibilityIdentifier("quickModels")
        // v34 (Marko, 16.11.2026: "the switch, macOS switch must become before the title"): switch first, then its word.
        // TEST left this row: it is the developer's accuracy scoring, it stays in the Test tab
        device.setAccessibilityIdentifier("input"); device.setAccessibilityLabel("Input: the microphone Vox records from")
        output.setAccessibilityIdentifier("output"); output.setAccessibilityLabel("Output: the speaker of Vox's sounds")
        output.target = self; output.action = #selector(outputChanged)
        device.toolTip = "The microphone a take is recorded from (and voice activation listens on)"
        output.toolTip = "The speaker of Vox's own sounds (start, stop, the magnet's pop); the Mac's default output is not changed"
        for p in [device, output] { p.controlSize = .small; p.font = .systemFont(ofSize: 11) }
        device.widthAnchor.constraint(lessThanOrEqualToConstant: 330).isActive = true
        output.widthAnchor.constraint(lessThanOrEqualToConstant: 330).isActive = true
        fillOutputs()
        // plugged in or out: both menus follow (and again each time one opens)
        OutputDevice.watch { [weak self] in self?.fillDevices(); self?.fillOutputs() }
        for p in [device, output] {
            NotificationCenter.default.addObserver(forName: NSPopUpButton.willPopUpNotification, object: p, queue: .main) { [weak self] _ in
                self?.fillDevices(); self?.fillOutputs()
            }
        }
        // v49 (Marko, 17.11.2026: "we always align the buttons perfectly"): the strip is ONE grid. Column 0 and 2 the names
        // (switch before its word; INPUT / OUTPUT under them), ending on one line; columns 1 and 3 the pop-ups, one left
        // edge and one width each; FRANKFURT after them.
        func named(_ sw: NSSwitch, _ t: String) -> NSStackView {
            let r = NSStackView(views: [sw, word(t)]); r.orientation = .horizontal; r.spacing = 6; r.alignment = .centerY; return r
        }
        let grid = NSGridView(views: [
            [named(qCorrect, "CORRECTION"), qCorrectModel, word("STYLE BUTTON"), qStyleModel, named(qFrankfurt, "FRANKFURT")],
        ])
        grid.rowSpacing = 4; grid.columnSpacing = 8
        grid.rowAlignment = .none; grid.yPlacement = .center
        for c in [0, 2] { grid.column(at: c).xPlacement = .trailing }
        for c in [1, 3] { grid.column(at: c).xPlacement = .fill }
        grid.column(at: 2).leadingPadding = 10; grid.column(at: 4).leadingPadding = 10
        grid.column(at: 4).xPlacement = .leading
        for i in 0..<grid.numberOfRows { grid.row(at: i).height = 22 }
        // v72 (Marko, 24.11.2026: "I want to see which devices are active ... microphone and speak[er]"): the Mac's default input
        // with its live level and the default output, always in sight; a click opens the picker, which sets them for every app
        let audio = SystemAudioView(fontSize: 13)
        let col = NSStackView(views: [grid, audio, qDetail]); col.orientation = .vertical; col.alignment = .leading; col.spacing = 4
        paintQuick()
        return col
    }

    func fillOutputs() {
        output.removeAllItems()
        output.addItem(withTitle: "System default (\(OutputDevice.defaultName()))")
        output.lastItem?.representedObject = nil
        for (uid, name) in OutputDevice.all() { output.addItem(withTitle: name); output.lastItem?.representedObject = uid }
        if let uid = OutputDevice.chosenUID, let i = output.itemArray.firstIndex(where: { $0.representedObject as? String == uid }) {
            output.selectItem(at: i)
        } else { output.selectItem(at: 0) }
    }
    @objc func outputChanged() {
        OutputDevice.chosenUID = output.selectedItem?.representedObject as? String
        appendLog("output: \(output.titleOfSelectedItem ?? "")")
        Chime.play(start: true, force: true)                  // heard on the speaker just chosen
    }

    /// the models really called (the newest of the family, as Anthropic lists it) and how long their last answer took
    static func modelLine(_ e: StyleEngine) -> String {
        let id = UserDefaults.standard.string(forKey: e.rawValue + "Model") ?? "\(e.rawValue), newest"
        let secs = UserDefaults.standard.object(forKey: "styleSecs_" + e.rawValue) as? Double
        return id + (secs.map { String(format: " · last %.1f s", $0) } ?? "")
    }

    func paintQuick() {
        let corr = StyleEngine.current
        qCorrect.state = corr == .off ? .off : .on
        let shown = corr == .off ? (StyleEngine(rawValue: UserDefaults.standard.string(forKey: "styleLastOn") ?? "") ?? .haiku) : corr
        qCorrectModel.selectItem(at: StyleButtonEngine.choices.firstIndex(of: shown) ?? 0)
        qCorrectModel.isEnabled = corr != .off
        qStyleModel.selectItem(at: StyleButtonEngine.choices.firstIndex(of: StyleButtonEngine.current) ?? 0)
        qFrankfurt.state = Frankfurt.on ? .on : .off
        let anth = keyText(.anthropic)
        qDetail.stringValue = "Correction: " + (corr == .off ? "off" : SettingsWindow.modelLine(corr)) +
            "   ·   STYLE button: " + SettingsWindow.modelLine(StyleButtonEngine.current) + ", then Groq" +
            "   ·   " + anth + "   ·   text mode " + TextMode.current.title
        qDetail.setAccessibilityValue(qDetail.stringValue)
    }

    @objc func quickChanged(_ sender: Any) {
        func engine(_ p: NSPopUpButton) -> StyleEngine { StyleEngine(rawValue: p.selectedItem?.representedObject as? String ?? "") ?? .haiku }
        if let sw = sender as? NSSwitch {
            if sw === qCorrect {
                StyleEngine.current = sw.state == .on ? engine(qCorrectModel) : .off
                appendLog("quick: correction \(StyleEngine.current.title)")
            } else if sw === qFrankfurt {
                frankfurtTick.state = sw.state; frankfurtChanged()
            }
        } else if let p = sender as? NSPopUpButton {
            if p === qCorrectModel { StyleEngine.current = engine(p); appendLog("quick: correction \(StyleEngine.current.title)") }
            if p === qStyleModel { StyleButtonEngine.current = engine(p); appendLog("quick: styling \(StyleButtonEngine.current.title)") }
        }
        paintChoices(); onChange()
    }

    static var byFamily: Bool {
        get { UserDefaults.standard.bool(forKey: "enginesByFamily") }
        set { UserDefaults.standard.set(newValue, forKey: "enginesByFamily") }
    }
    @objc func orderChanged() {
        SettingsWindow.byFamily = orderPicker.selectedSegment == 1
        for l in Array(columns.keys) { arrange(l) }
    }

    /// the cards of one column, best first (Catalog.qualityRank) or by family (families by their best member, best first inside)
    func arrange(_ lang: String) {
        guard let col = columns[lang], let byId = cards[lang] else { return }
        for v in col.arrangedSubviews.dropFirst(2) { col.removeArrangedSubview(v); v.removeFromSuperview() }
        let ranked = Catalog.ranked()
        var views: [NSView] = []
        if SettingsWindow.byFamily {
            func best(_ ids: Set<String>) -> Int {
                for (i, id) in ranked.enumerated() where ids.contains(id) { return i }
                return 99
            }
            let fams = SettingsWindow.families.sorted { best($0.1) < best($1.1) }
            var placed = Set<String>()
            for (family, ids) in fams {
                let inFamily = ranked.filter { ids.contains($0) && byId[$0] != nil }
                if inFamily.isEmpty { continue }
                if let g = familyLabels[lang]?[family] { views.append(g) }
                for id in inFamily { views.append(byId[id]!); placed.insert(id) }
            }
            for id in ranked where !placed.contains(id) { if let c = byId[id] { views.append(c) } }
        } else {
            for id in ranked { if let c = byId[id] { views.append(c) } }
        }
        for v in views {
            col.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        }
    }

    func addTab(_ title: String, _ view: NSView) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        tabs.addTabViewItem(item)
    }

    /// a tab's page: its rows from the top, the copyright line last; it scrolls only on a screen too small for it
    func page(_ views: [NSView]) -> NSScrollView {
        let copyright = NSTextField(labelWithString: "© 2026 Mantra Productions")
        copyright.font = NSFont.systemFont(ofSize: 11); copyright.textColor = .secondaryLabelColor
        let col = NSStackView(views: views + [copyright])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 10
        col.setCustomSpacing(18, after: views.last ?? copyright)
        col.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        let sc = NSScrollView()
        sc.hasVerticalScroller = true
        sc.autohidesScrollers = true
        sc.drawsBackground = false
        let holder = FlippedView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        col.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(col)
        sc.documentView = holder
        // v49 (Marko, 17.11.2026: "Please don't make these empty parts"; "we always align the buttons perfectly"): the page is as
        // wide as the window; paragraphs wrap at the page's width and the wide parts (engine columns, text boxes) fill it,
        // so a wide window has no empty column on the right and a narrow one cuts nothing
        for v in views {
            let wraps = (v as? NSTextField).map { !$0.isEditable && $0.lineBreakMode == .byWordWrapping } ?? false
            guard wraps || fillWidth.contains(where: { $0 === v }) else { continue }
            if let t = v as? NSTextField, wraps { t.preferredMaxLayoutWidth = 0; t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -40).isActive = true
        }
        NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                                     col.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                                     col.topAnchor.constraint(equalTo: holder.topAnchor),
                                     col.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                                     holder.widthAnchor.constraint(equalTo: sc.contentView.widthAnchor)])
        return sc
    }

    @objc func modePicked(_ b: NSButton) {
        if let m = TextMode(rawValue: b.identifier?.rawValue ?? "") { TextMode.current = m; appendLog("text mode: \(m.title)") }
        paintChoices(); onChange()
    }
    @objc func typingTicks() {
        Prefs.pasteFallback = pasteTick.state == .on
        Prefs.clickToFocus = clickTick.state == .on
        appendLog("typing: paste \(Prefs.pasteFallback ? "on" : "off"), click to focus \(Prefs.clickToFocus ? "on" : "off")")
    }
    func paintTarget() { targetLabel.stringValue = TextTarget.shared.last?.describe ?? "none yet: click into a text box" }

    // v12: the round buttons
    func paintChoices() {
        croatianTick.state = Prefs.correctCroatian ? .on : .off      // v42: it is the HR slot's correction
        let h = HearEngine.current
        for (l, byId) in cards {
            let chosen = UserDefaults.standard.string(forKey: "engine_" + l) ?? "assemblyai"
            for (id, c) in byId { c.chosen = id == chosen }
            if let sp = Catalog.byId(chosen) { heads[l]?.engine = sp.short; heads[l]?.pct = String(Stats.tag(chosen, l).dropFirst(3)); heads[l]?.needsDisplay = true }
        }
        for (l, b) in langRadios { b.state = l == h.lang ? .on : .off }
        for (e, b) in styleRadios { b.state = e == StyleEngine.current ? .on : .off }
        for (e, b) in styleButtonRadios { b.state = e == StyleButtonEngine.current ? .on : .off }
        for (m, b) in modeRadios { b.state = m == TextMode.current ? .on : .off }
        paintQuick()
        history?.paintSlot()                                         // v48: History shows the same slots
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
    var soundsButton: NSButton!
    func paintSounds() {
        let on = Prefs.chimesOn
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        soundsButton.image = NSImage(systemSymbolName: on ? "speaker.wave.2.fill" : "speaker.fill", accessibilityDescription: "sounds")?.withSymbolConfiguration(cfg)
        soundsButton.contentTintColor = on ? Ink.green : Ink.grey
        soundsButton.setAccessibilityValue(on ? "on" : "off")
        soundsButton.toolTip = on ? "The start and stop sounds are on (click: off)" : "The start and stop sounds are off (click: on)"
    }
    @objc func soundsPressed() {
        Prefs.chimesOn.toggle(); paintSounds()
        appendLog("start/stop sounds: \(Prefs.chimesOn ? "on" : "off")")
        if Prefs.chimesOn { Chime.play(start: true, force: true) }
    }
    // OFF quits, but never costs a take (the same guard as a build's quit)
    @objc func offPressed() {
        if stripe.recorder.recording || stripe.busy {
            offNote.stringValue = "a take is open: send or cancel it first"
            appendLog("OFF pressed: refused, a take is in progress")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.offNote.stringValue = "" }
            return
        }
        appendLog("✕ pressed: quit")
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
        DispatchQueue.global().async { let r = KeyImporter.loadFamous(); if !r.isEmpty { DispatchQueue.main.async { self.showKeys() } }; Frankfurt.syncKeys() }
        refreshFrankfurt()   // keys new in ~/Downloads/API come in by themselves
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
        paintTarget()
        paintTyping()
        targetTimer?.invalidate()
        targetTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.window.isVisible else { t.invalidate(); return }
            self.paintTarget()
        }
        tabs.selectTabViewItem(at: min(max(tab, 0), tabs.numberOfTabViewItems - 1))
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
        for (l, byId) in cards {
            for (id, c) in byId {
                guard let s = Catalog.byId(id) else { continue }
                let ok = Catalog.available(s)
                c.usable = ok; c.name = s.short; c.pct = String(Stats.tag(id, l).dropFirst(3))
                let keys = s.ring.map(keyText) ?? (ok ? "on this Mac" : "not on this Mac")
                c.sub = s.label + " · " + keys
                c.toolTip = s.ring.map { p in
                    let m = Ring.memory(p)
                    return Keys.entries(p).enumerated().map { i, k in
                        let st = m.states[Ring.fingerprint(k.key)]
                        return "\(i + 1). \(k.title): " + (st.map { "\(KeyTest.word($0.verdict)) (\($0.detail))" } ?? "not asked yet")
                    }.joined(separator: "\n")
                }
            }
        }
        anthropicLabel.stringValue = "The correction key: " + keyText(.anthropic)
    }

    @objc func hotkeyChanged() {
        HotKey.chosen = hotkey.titleOfSelectedItem ?? "F1"
        HotKey.chosenHR = hotkeyHR.titleOfSelectedItem ?? "F2"
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

func Settings_benchSummaryAfter(_ w: SettingsWindow) -> String { w.Settings_benchSummary() }
