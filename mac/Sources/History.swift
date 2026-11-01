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
    let style = NSPopUpButton()
    let retranscribe = NSButton(title: "Transcribe again", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    var everything: [Entry] = []
    var entries: [Entry] = []                  // what the search lets through
    let typeText: (String) -> Void
    let stepAside: () -> Void

    init(typeText: @escaping (String) -> Void, stepAside: @escaping () -> Void) {
        self.typeText = typeText
        self.stepAside = stepAside
        super.init()

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
        table.rowHeight = 54
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self
        table.delegate = self
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.widthAnchor.constraint(equalToConstant: 380).isActive = true

        detail.isEditable = false
        detail.font = .systemFont(ofSize: 13)
        detail.textContainerInset = NSSize(width: 8, height: 8)
        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detail.autoresizingMask = [.width]
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder

        for e in HearEngine.allCases { hear.addItem(withTitle: e.title); hear.lastItem?.representedObject = e.rawValue }
        for e in StyleEngine.allCases { style.addItem(withTitle: e.title); style.lastItem?.representedObject = e.rawValue }
        hear.toolTip = "The ear (and language) for the new version"
        style.toolTip = "The style for the new version"
        retranscribe.target = self; retranscribe.action = #selector(again)
        let copy = NSButton(title: "Copy", target: self, action: #selector(copySelected))
        let typeAgain = NSButton(title: "Type it", target: self, action: #selector(typeIt))
        typeAgain.toolTip = "Type the version shown into the app you were in"
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let buttons = NSStackView(views: [hear, style, retranscribe, NSView(), copy, typeAgain])
        buttons.orientation = .horizontal
        let right = NSStackView(views: [detailScroll, buttons, status])
        right.orientation = .vertical
        right.alignment = .leading
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([detailScroll.widthAnchor.constraint(equalTo: right.widthAnchor),
                                     buttons.widthAnchor.constraint(equalTo: right.widthAnchor)])
        let split = NSStackView(views: [tableScroll, right])
        split.orientation = .horizontal
        split.alignment = .top
        split.spacing = 12
        tableScroll.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        right.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true

        let page = NSStackView(views: [top, split])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        page.translatesAutoresizingMaskIntoConstraints = false
        top.translatesAutoresizingMaskIntoConstraints = false
        split.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor), page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.topAnchor.constraint(equalTo: view.topAnchor), page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            top.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -24),
            split.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -24),
        ])
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
        let l = NSTextField(labelWithString: "")
        l.lineBreakMode = .byTruncatingTail
        let head = "\(f.string(from: e.versions.first!.at)) · \(v.lang.uppercased()) · \(v.hear) · \(v.style)\(History.hasAudio(e.id) ? "" : " · no audio")\n"
        let s = NSMutableAttributedString(string: head, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
        if v.text.isEmpty {
            s.append(NSAttributedString(string: "not transcribed: select it, Transcribe again", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemRed]))
        } else {
            s.append(NSAttributedString(string: v.text.replacingOccurrences(of: "\n", with: " "), attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        }
        l.attributedStringValue = s
        l.maximumNumberOfLines = 2
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
            "\(i == 0 ? "THE TAKE" : "VERSION \(i + 1)") · \(f.string(from: v.at)) · \(v.lang.uppercased()) · \(v.hear) · \(v.style)\n\n\(v.text)\n\nheard: \(v.heard)"
        }.joined(separator: "\n\n────────\n\n")
        retranscribe.isEnabled = History.hasAudio(e.id)
        status.stringValue = History.hasAudio(e.id) ? "The audio is kept until \(f.string(from: e.versions.first!.at.addingTimeInterval(History.audioDays)))." : "The audio is gone (kept one day); the words stay."
        if let i = hear.itemArray.firstIndex(where: { $0.title == e.latest.hear }) { hear.selectItem(at: i) }
        if let i = style.itemArray.firstIndex(where: { $0.title == StyleEngine.current.title }) { style.selectItem(at: i) }
    }

    // TTT Mini's re-transcribe: the same audio, another ear or language, another style; the result is a new version.
    @objc func again() {
        guard let e = selected, let he = HearEngine(rawValue: hear.selectedItem?.representedObject as? String ?? ""),
              let st = StyleEngine(rawValue: style.selectedItem?.representedObject as? String ?? "") else { return }
        retranscribe.isEnabled = false
        status.stringValue = "transcribing again with \(he.title), \(st.title)…"
        DispatchQueue.global().async {
            let heard = Hear.run(he, wav: History.audio(e.id))
            var result: String
            var words = ""
            switch heard {
            case .failure(let err): result = "✗ " + err.message
            case .success(let w):
                words = w
                switch Style.run(st, text: w, lang: he.lang) {
                case .success(let t): result = t
                case .failure(let err): result = corrected(w); words += "  (style failed: \(err.message))"
                }
            }
            DispatchQueue.main.async {
                if !result.hasPrefix("✗ ") {
                    var updated = e
                    updated.versions.append(Version(at: Date(), hear: he.title, style: st.title, lang: he.lang, heard: words, text: result))
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
