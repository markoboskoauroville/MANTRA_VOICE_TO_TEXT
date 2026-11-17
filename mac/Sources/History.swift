// THE HISTORY (Marko, 18.10.2026: "add history of transcription same as Speechify and retranscribe if language is
// chosen wrongly keep audio of each transcription for one day and same as TTT Mini make re-transcribe possible with same
// audio for different models and different languages").
//
// Every take is an entry: its time, the ear, the style, the language, what was heard and what was typed, and every later
// version made from the same audio. The audio is kept for one day (24 h) beside the entry, then deleted; the words stay.
//
//   ~/Library/Application Support/Marko Transcribe/history/<id>/entry.json, take.flac (the recorded rate, lossless)
import AppKit

struct Version: Codable {
    let at: Date, hear: String, style: String, lang: String, heard: String, text: String
    var rating: Int? = nil                 // v24 rating (thumbs removed in v46, old entries keep the field)
    var landed: String? = nil              // v46: where the take went: typed, pasted, did not land, not typed (test), cancelled, failed
}

struct Entry: Codable {
    let id: String
    var versions: [Version]                    // the first is the take as typed; the others re-transcriptions
    var latest: Version { versions.last! }
}

enum History {
    static let folder = Keys.folder.appendingPathComponent("history")
    static let audioDays: TimeInterval = 86400

    static func audio(_ id: String) -> URL { folder.appendingPathComponent(id).appendingPathComponent("take.caf") }
    static func hasAudio(_ id: String) -> Bool { FileManager.default.fileExists(atPath: audio(id).path) }

    static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    @discardableResult
    static func add(wav: URL, _ v: Version) -> Entry {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let id = f.string(from: v.at) + "-" + String(UUID().uuidString.prefix(4))
        let dir = folder.appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !Audio.archive(wav, to: audio(id)) { try? FileManager.default.copyItem(at: wav, to: audio(id)) }
        let e = Entry(id: id, versions: [v])
        save(e)
        return e
    }

    /// v46: where the take landed, written on its first version
    static func mark(_ id: String, landed: String) {
        let url = folder.appendingPathComponent(id).appendingPathComponent("entry.json")
        guard let d = try? Data(contentsOf: url), var e = try? coder().1.decode(Entry.self, from: d), !e.versions.isEmpty else { return }
        e.versions[0].landed = landed
        save(e)
    }

    static func save(_ e: Entry) {
        let url = folder.appendingPathComponent(e.id).appendingPathComponent("entry.json")
        try? coder().0.encode(e).write(to: url, options: .atomic)
    }

    // newest first
    static func all() -> [Entry] {
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return dirs.sorted(by: >).compactMap { id in
            (try? Data(contentsOf: folder.appendingPathComponent(id).appendingPathComponent("entry.json")))
                .flatMap { try? coder().1.decode(Entry.self, from: $0) }
        }
    }

    // Audio older than a day goes; the words stay.
    static func purge() {
        for e in all() where Date().timeIntervalSince(e.versions.first!.at) > audioDays && hasAudio(e.id) {
            try? FileManager.default.removeItem(at: audio(e.id))
        }
    }

    // One take with its audio and every version (the row's 🗑), or all of them (Clean).
    static func remove(_ id: String) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(id)) }
    static func clean() { for e in all() { remove(e.id) } }
}


// MARK: the pane, the second tab of ⚙ (request 14: "settings has two tabs: settings and transcription history ... all
// transcription will be there with the copy button and of course the clean button and search field filtering")

final class HistoryPane: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let view = NSView()
    let table = NSTableView()
    let search = NSSearchField()
    let count = NSTextField(labelWithString: "")
    let detail = NSTextView()
    let hear = NSPopUpButton()
    let hearLang = NSPopUpButton()
    let style = NSPopUpButton()                // the correction model
    let styling = NSPopUpButton()              // v46: the styling model
    // v48: the check box comes AFTER its model's pop-up and has no word of its own (the row's label names it)
    let useCorrection = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let useStyling = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var onChange: () -> Void = {}              // v48: a choice made here is the global one: the menu bar, pill and Settings follow
    private var painting = false
    let retranscribe = NSButton(title: "Re-transcribe", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    let files = FilePanel()                    // v15: Transcribe a file…
    var everything: [Entry] = []
    var entries: [Entry] = []                  // what the search lets through
    let typeText: (String) -> Void
    let stepAside: () -> Void

    init(typeText: @escaping (String) -> Void, stepAside: @escaping () -> Void) {
        self.typeText = typeText
        self.stepAside = stepAside
        super.init()
        files.onDone = { [weak self] in self?.reload() }

        search.placeholderString = "Search the transcriptions"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        count.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)
        let clean = NSButton(title: "Clean", target: self, action: #selector(cleanAll))
        clean.toolTip = "Delete every transcription and its audio"
        let top = NSStackView(views: [search, count, clean])
        top.orientation = .horizontal
        top.spacing = 8

        let col = NSTableColumn(identifier: .init("t"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 70                   // v47: the head on one line, the words on up to three
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        col.resizingMask = .autoresizingMask
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self
        table.delegate = self
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        // v47 (Marko, 17.11.2026: "there is an empty column at the end ... Please don't make these empty parts."): the list and the
        // take share the whole width (list 42 %, at least 300 pt); no fixed width, nothing left empty at any window size
        tableScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        tableScroll.automaticallyAdjustsContentInsets = false
        tableScroll.contentInsets = NSEdgeInsetsZero

        detail.isEditable = false
        detail.font = .systemFont(ofSize: 13)
        detail.textContainerInset = NSSize(width: 8, height: 8)
        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detail.autoresizingMask = [.width]
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder

        // v13 (TTT: "Re-transcribe with..." and the accuracy % next to every model): every engine of the catalogue, the
        // accuracy for the language chosen beside it; one without a key is greyed
        for l in HearEngine.langs { hearLang.addItem(withTitle: l == "auto" ? "AUTO" : l.uppercased()); hearLang.lastItem?.representedObject = l }
        hearLang.target = self; hearLang.action = #selector(langChanged)
        hearLang.toolTip = "The language for the new version"
        hear.target = self; hear.action = #selector(engineChanged)
        style.target = self; style.action = #selector(correctionModelChanged)
        styling.target = self; styling.action = #selector(stylingModelChanged)
        // v46 (Marko, 17.11.2026: "I can change the model ... change the language ... change the auto-correction model ... but
        // there is no model for styling. And I need checkmarks to re-transcribe with styling or correction."): a labelled table,
        // engine, language, correction model, styling model, and the two checkmarks that decide what the new version gets
        for e in StyleEngine.allCases where e != .off { style.addItem(withTitle: e.title); style.lastItem?.representedObject = e.rawValue }
        for e in StyleButtonEngine.choices { styling.addItem(withTitle: e.title); styling.lastItem?.representedObject = e.rawValue }
        hear.toolTip = "The engine that hears the stored audio again"
        style.toolTip = "The Claude model that corrects spelling, grammar and misheard words"
        styling.toolTip = "The Claude model that styles the text (repetitions, filler words, order)"
        useCorrection.toolTip = "Correct the new version with the correction model"
        useStyling.toolTip = "Style the new version with the styling model"
        useCorrection.target = self; useCorrection.action = #selector(correctionToggled)
        useStyling.target = self; useStyling.action = #selector(stylingToggled)
        useCorrection.setAccessibilityLabel("Correction"); useCorrection.setAccessibilityIdentifier("history-correction")
        useStyling.setAccessibilityLabel("Styling"); useStyling.setAccessibilityIdentifier("history-styling")
        hear.setAccessibilityIdentifier("history-engine"); hearLang.setAccessibilityIdentifier("history-language")
        style.setAccessibilityIdentifier("history-correction-model"); styling.setAccessibilityIdentifier("history-styling-model")
        retranscribe.target = self; retranscribe.action = #selector(again)
        retranscribe.toolTip = "Transcribe the stored audio again with the choices above: a new version of this take"
        retranscribe.setAccessibilityIdentifier("retranscribe")
        let copy = NSButton(title: "Copy", target: self, action: #selector(copySelected))
        let typeAgain = NSButton(title: "Type it", target: self, action: #selector(typeIt))
        typeAgain.toolTip = "Type the version shown into the app you were in"
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        func label(_ t: String) -> NSTextField {
            let l = NSTextField(labelWithString: t.uppercased())
            l.font = .systemFont(ofSize: 10, weight: .semibold); l.textColor = .secondaryLabelColor
            l.alignment = .right
            return l
        }
        // v48 (Marko, 17.11.2026: "The correction and styling check marks are not aligned. It's very ugly ... move the check boxes
        // next to the options for changing the Sonnet, Opus, or Haiku, so they are placed after that menu ... Re-transcribe should be
        // under the model's choice ... we always align the buttons perfectly."): ONE grid. Column 0 the labels, right-aligned;
        // column 1 the four pop-ups, one left edge and one width, and under them on the same two edges Re-transcribe, then
        // Copy | Type it; column 2 the two check boxes, one above the other. Every row the same height.
        for p in [hear, hearLang, style, styling] {
            p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            p.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        for b in [retranscribe, copy, typeAgain] { b.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        let pair = NSStackView(views: [copy, typeAgain])
        pair.orientation = .horizontal; pair.distribution = .fillEqually; pair.spacing = 8
        let grid = NSGridView(views: [
            [label("Engine"), hear, NSGridCell.emptyContentView],
            [label("Language"), hearLang, NSGridCell.emptyContentView],
            [label("Correction"), style, useCorrection],
            [label("Styling"), styling, useStyling],
            [NSGridCell.emptyContentView, retranscribe, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, pair, NSGridCell.emptyContentView],
        ])
        grid.rowSpacing = 8; grid.columnSpacing = 8
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 2).xPlacement = .center
        grid.column(at: 2).width = 20
        for i in 0..<grid.numberOfRows { grid.row(at: i).height = 24 }
        grid.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let line = NSBox(); line.boxType = .separator
        let right = NSStackView(views: [detailScroll, line, grid, status])
        right.orientation = .vertical
        right.alignment = .leading
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([detailScroll.widthAnchor.constraint(equalTo: right.widthAnchor),
                                     line.widthAnchor.constraint(equalTo: right.widthAnchor),
                                     grid.widthAnchor.constraint(equalTo: right.widthAnchor),
                                     status.widthAnchor.constraint(equalTo: right.widthAnchor)])
        let split = NSStackView(views: [tableScroll, right])
        split.orientation = .horizontal
        split.alignment = .top
        split.spacing = 12
        split.distribution = .fill
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tableScroll.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let share = tableScroll.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.42)
        share.priority = .defaultHigh
        share.isActive = true
        right.trailingAnchor.constraint(equalTo: split.trailingAnchor).isActive = true
        tableScroll.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        right.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true

        let page = NSStackView(views: [top, files.view, split])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        page.translatesAutoresizingMaskIntoConstraints = false
        top.translatesAutoresizingMaskIntoConstraints = false
        split.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page)
        paintSlot()
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor), page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.topAnchor.constraint(equalTo: view.topAnchor), page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            top.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -24),
            files.view.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -24),
            split.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -24),
        ])
    }

    /// the language whose slot the controls show and change (History's LANGUAGE)
    var slotLang: String { hearLang.selectedItem?.representedObject as? String ?? "auto" }

    // the engines with their accuracy in the language chosen, and a note for the ones that cannot run now
    func fillEngines() {
        let lang = slotLang
        hear.removeAllItems()
        hear.menu?.autoenablesItems = false
        for s in Catalog.all {
            hear.addItem(withTitle: Catalog.shown(s, lang: lang) + (Catalog.available(s) ? "" : (s.local ? "  (not on this Mac)" : "  (no key)")))
            hear.lastItem?.representedObject = s.id
            hear.lastItem?.isEnabled = Catalog.available(s)
        }
    }
    /// v48: the four controls show the GLOBAL slot of the language chosen here (engine_<lang>, style_<lang>, styleButtonOn_<lang>,
    /// the styling model): the same values the menu bar menu, the pill and Settings show for that language
    func paintSlot() {
        painting = true; defer { painting = false }
        let l = slotLang
        fillEngines()
        let id = Slot.engine(l)
        if let i = hear.itemArray.firstIndex(where: { $0.representedObject as? String == id }) { hear.selectItem(at: i) }
        let cm = Slot.correction(l)
        let showC = cm == .off ? Slot.lastCorrection : cm
        if let i = style.itemArray.firstIndex(where: { $0.representedObject as? String == showC.rawValue }) { style.selectItem(at: i) }
        if let i = styling.itemArray.firstIndex(where: { $0.representedObject as? String == StyleButtonEngine.current.rawValue }) { styling.selectItem(at: i) }
        useCorrection.state = cm != .off ? .on : .off
        useStyling.state = Slot.stylingOn(l) ? .on : .off
    }
    @objc func langChanged() { paintSlot() }
    @objc func engineChanged() {
        guard !painting, let id = hear.selectedItem?.representedObject as? String, Catalog.byId(id) != nil else { return }
        Slot.setEngine(id, slotLang)
        appendLog("history: engine \(id) for \(slotLang) (global)")
        onChange()
    }
    private func picked(_ p: NSPopUpButton) -> StyleEngine { StyleEngine(rawValue: p.selectedItem?.representedObject as? String ?? "") ?? .haiku }
    @objc func correctionToggled() {
        Slot.setCorrection(useCorrection.state == .on ? picked(style) : .off, slotLang)
        appendLog("history: correction \(Slot.correction(slotLang).title) for \(slotLang) (global)")
        onChange()
    }
    @objc func correctionModelChanged() {
        guard !painting else { return }
        if useCorrection.state == .on { Slot.setCorrection(picked(style), slotLang) }
        else { UserDefaults.standard.set(picked(style).rawValue, forKey: "styleLastOn") }       // the model the switch turns on next
        appendLog("history: correction model \(picked(style).title) for \(slotLang) (global)")
        onChange()
    }
    @objc func stylingToggled() {
        Slot.setStylingOn(useStyling.state == .on, slotLang)
        appendLog("history: styling \(useStyling.state == .on ? "on" : "off") for \(slotLang) (global)")
        onChange()
    }
    @objc func stylingModelChanged() {
        guard !painting else { return }
        StyleButtonEngine.current = picked(styling)
        appendLog("history: styling model \(StyleButtonEngine.current.title) (global)")
        onChange()
    }

    func reload() {
        History.purge()
        everything = History.all()
        filter()
    }

    // Every word of the search must be somewhere in the take (any version, typed or heard, or the ear and style),
    // capitals and accents not counted: "sre" finds Srećko.
    func filter() {
        let keep = selected?.id
        let words = search.stringValue.split(separator: " ").map(String.init)
        entries = words.isEmpty ? everything : everything.filter { e in
            let hay = e.versions.map { "\($0.text) \($0.heard) \($0.hear) \($0.style)" }.joined(separator: " ")
            return words.allSatisfy { hay.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        count.stringValue = words.isEmpty ? "\(everything.count) transcriptions" : "\(entries.count) of \(everything.count)"
        table.reloadData()
        let row = entries.firstIndex { $0.id == keep } ?? (entries.isEmpty ? -1 : 0)
        if row >= 0 { table.selectRowIndexes([row], byExtendingSelection: false); table.scrollRowToVisible(row) }
        showSelected()
    }

    func controlTextDidChange(_ n: Notification) { filter() }

    func numberOfRows(in t: NSTableView) -> Int { entries.count }

    // A row: the time, language, ear and style above, the text below; Copy and 🗑 on the right.
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row], v = e.latest
        let f = DateFormatter(); f.dateFormat = "d.M. HH:mm"
        let l = NSTextField(wrappingLabelWithString: "")
        let head = "\(f.string(from: e.versions.first!.at)) · \(v.lang.uppercased()) · \(Stats.decorate(hear: v.hear)) · \(v.style)\(e.versions.first!.landed.map { " · " + $0 } ?? "")\(History.hasAudio(e.id) ? "" : " · no audio")\n"
        let s = NSMutableAttributedString(string: head, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
        if v.text.isEmpty {
            s.append(NSAttributedString(string: "not transcribed: select it, Re-transcribe", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemRed]))
        } else {
            s.append(NSAttributedString(string: v.text.replacingOccurrences(of: "\n", with: " "), attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        }
        l.attributedStringValue = s
        l.maximumNumberOfLines = 4
        l.cell?.wraps = true
        l.cell?.truncatesLastVisibleLine = true
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyRow(_:)))
        copy.controlSize = .small
        copy.bezelStyle = .rounded
        copy.toolTip = "Put this transcription on the clipboard"
        copy.isEnabled = !v.text.isEmpty
        let bin = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") ?? NSImage(), target: self, action: #selector(deleteRow(_:)))
        bin.isBordered = false
        bin.toolTip = "Delete this transcription and its audio"
        for b in [copy, bin] { b.identifier = .init(e.id); b.setContentHuggingPriority(.required, for: .horizontal) }
        let cell = NSStackView(views: [l, copy, bin])
        cell.orientation = .horizontal
        cell.spacing = 6
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
        return cell
    }

    func tableViewSelectionDidChange(_ n: Notification) { showSelected() }

    var selected: Entry? { table.selectedRow >= 0 && table.selectedRow < entries.count ? entries[table.selectedRow] : nil }

    // Every version of the take, newest last, each with what was heard and what was typed.
    func showSelected() {
        guard let e = selected else {
            detail.string = everything.isEmpty ? "No transcriptions yet." : "Nothing matches the search."
            retranscribe.isEnabled = false; status.stringValue = ""; return
        }
        let f = DateFormatter(); f.dateFormat = "d.M.yyyy HH:mm:ss"
        detail.string = e.versions.enumerated().map { i, v in
            "\(i == 0 ? "THE TAKE" : "VERSION \(i + 1)") · \(f.string(from: v.at)) · \(v.lang.uppercased()) · \(Stats.decorate(hear: v.hear)) · \(v.style)\(v.landed.map { " · " + $0 } ?? "")\n\n\(v.text)\n\nheard: \(v.heard)"
        }.joined(separator: "\n\n────────\n\n")
        retranscribe.isEnabled = History.hasAudio(e.id)
        status.stringValue = History.hasAudio(e.id) ? "The audio is kept until \(f.string(from: e.versions.first!.at.addingTimeInterval(History.audioDays)))." : "The audio is gone (kept one day); the words stay."
        // v48: the take's language picks the slot; the controls then show that language's GLOBAL choices
        let sl = ["en", "hr", "auto"].contains(e.latest.lang) ? e.latest.lang : "auto"
        if let i = hearLang.itemArray.firstIndex(where: { $0.representedObject as? String == sl }) { hearLang.selectItem(at: i) }
        paintSlot()
    }

    // TTT Mini's re-transcribe: the same audio, another ear or language, another style; the result is a new version.
    @objc func again() {
        guard let e = selected, let eid = hear.selectedItem?.representedObject as? String, Catalog.byId(eid) != nil else { return }
        let cor = useCorrection.state == .on ? StyleEngine(rawValue: style.selectedItem?.representedObject as? String ?? "") : nil
        let sty = useStyling.state == .on ? StyleEngine(rawValue: styling.selectedItem?.representedObject as? String ?? "") : nil
        let he = HearEngine(id: eid, lang: hearLang.selectedItem?.representedObject as? String ?? "auto")
        // what the new version is called in the list: the models that touched it
        let styleTitle = [cor.map { "correction " + $0.title }, sty.map { "styling " + $0.title }].compactMap { $0 }.joined(separator: " + ")
        retranscribe.isEnabled = false
        status.stringValue = "re-transcribing with \(he.title)" + (styleTitle.isEmpty ? ", words as heard…" : ", then \(styleTitle)…")
        appendLog("history: re-transcribe \(e.id) with \(he.id) \(he.lang), \(styleTitle.isEmpty ? "as heard" : styleTitle)")
        DispatchQueue.global().async {
            let heard = Hear.run(he, wav: History.audio(e.id))
            var result: String
            var words = ""
            switch heard {
            case .failure(let err): result = "✗ " + err.message
            case .success(let w):
                words = w
                let lang = he.lang == "auto" ? (Hear.lastLang.flatMap { ["en", "hr"].contains($0) ? $0 : nil } ?? "auto") : he.lang
                result = corrected(w)
                // correction first (its own model), then styling (its own model); both on and the same model: one call
                if let c = cor, let s = sty, c == s {
                    switch Style.run(c, text: w, lang: lang, mode: .styleCorrect) {
                    case .success(let t): result = t
                    case .failure(let err): words += "  (correction and styling failed: \(err.message))"
                    }
                } else {
                    if let c = cor {
                        switch Style.run(c, text: result, lang: lang, mode: .correct) {
                        case .success(let t): result = t
                        case .failure(let err): words += "  (correction failed: \(err.message))"
                        }
                    }
                    if let s = sty {
                        switch Style.run(s, text: result, lang: lang, mode: .style) {
                        case .success(let t): result = t
                        case .failure(let err): words += "  (styling failed: \(err.message))"
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                if !result.hasPrefix("✗ ") {
                    var updated = e
                    updated.versions.append(Version(at: Date(), hear: Hear.used ?? he.title, style: styleTitle.isEmpty ? StyleEngine.off.title : styleTitle,
                                                    lang: he.lang, heard: words, text: result))
                    History.save(updated)
                    if let i = self.everything.firstIndex(where: { $0.id == e.id }) { self.everything[i] = updated }
                    self.filter()
                    self.status.stringValue = "a new version, from the same audio"
                } else {
                    self.status.stringValue = result
                    self.retranscribe.isEnabled = true
                }
            }
        }
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { status.stringValue = "nothing to copy: this take was not transcribed"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status.stringValue = "copied: ⌘V where you want it"
    }

    @objc func copySelected() { if let e = selected { copy(e.latest.text) } }

    @objc func copyRow(_ b: NSButton) {
        guard let e = entries.first(where: { $0.id == b.identifier?.rawValue }) else { return }
        copy(e.latest.text)
        if let i = entries.firstIndex(where: { $0.id == e.id }) { table.selectRowIndexes([i], byExtendingSelection: false) }
    }

    @objc func deleteRow(_ b: NSButton) {
        guard let id = b.identifier?.rawValue else { return }
        History.remove(id)
        everything.removeAll { $0.id == id }
        filter()
        status.stringValue = "deleted"
    }

    @objc func cleanAll() {
        guard !everything.isEmpty else { return }
        let a = NSAlert()
        a.messageText = "Delete all \(everything.count) transcriptions?"
        a.informativeText = "Their words and their audio are gone for good."
        a.addButton(withTitle: "Delete all")
        a.addButton(withTitle: "Keep them")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        History.clean()
        search.stringValue = ""
        reload()
        status.stringValue = "the history is clean"
    }

    // The window steps aside so the text goes into the app he was in before.
    @objc func typeIt() {
        guard let e = selected, !e.latest.text.isEmpty else { return }
        stepAside()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.typeText(e.latest.text) }
    }
}
