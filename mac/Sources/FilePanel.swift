// TRANSCRIBE A FILE, the part of the History tab you see (v15, Marko, 13.11.2026: "I want to see this thing open up and it's
// working"): the button, the engine and the language, and while a job runs one table of labelled cells (FILE, PIECE, ENGINE,
// ELAPSED, TIME LEFT, DONE), a hairline that fills, and the words appearing piece by piece. Dropping a file on the window
// does the same as the button (DropBox). MANTRA_MANIFEST modules/workflow-interface.md: hairlines, labels above values.
import AppKit
import UniformTypeIdentifiers

/// the window's content view: a file dropped anywhere on it starts a transcription
final class DropBox: NSView {
    var onDrop: ((URL) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    func firstFile(_ s: NSDraggingInfo) -> URL? {
        (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { firstFile(s) == nil ? [] : .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let u = firstFile(s) else { return false }
        onDrop?(u)
        return true
    }
}

final class FilePanel: NSObject {
    let view = NSStackView()
    let pick = NSButton(title: "Transcribe a file…", target: nil, action: nil)
    let engine = NSPopUpButton()
    let lang = NSPopUpButton()
    let hint = NSTextField(labelWithString: "or drop an audio or video file on this window")
    let cancel = NSButton(title: "STOP", target: nil, action: nil)
    let open = NSButton(title: "SHOW FILES", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    let live = NSTextView()
    let liveScroll = NSScrollView()
    let progress = NSView(), fill = NSView()
    var fillWidth: NSLayoutConstraint!
    let jobBox = NSStackView()
    var cells: [String: NSTextField] = [:]
    var job: FileJob?
    var timer: Timer?
    var shown = 0
    var savedJSON = ""
    var onDone: () -> Void = {}

    override init() {
        super.init()
        pick.target = self; pick.action = #selector(choose)
        pick.bezelStyle = .rounded
        pick.setAccessibilityIdentifier("transcribe-file"); pick.setAccessibilityLabel("Transcribe a file")
        pick.toolTip = "Choose an audio or video file of any length: it is cut into pieces, transcribed in order, and saved beside the file"
        engine.toolTip = "The engine for the file"
        lang.toolTip = "The language of the file"
        fillEngines()
        for l in ["auto", "en", "hr"] { lang.addItem(withTitle: l == "auto" ? "AUTO" : l.uppercased()); lang.lastItem?.representedObject = l }
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        let top = NSStackView(views: [pick, engine, lang, hint])
        top.orientation = .horizontal; top.spacing = 8

        // the table: a small grey LABEL above, the value under it
        let names = ["FILE", "PIECE", "ENGINE", "ELAPSED", "TIME LEFT", "DONE"]
        var cols: [NSView] = []
        for n in names {
            let l = NSTextField(labelWithString: n); l.font = .systemFont(ofSize: 9, weight: .semibold); l.textColor = .secondaryLabelColor
            let v = NSTextField(labelWithString: "—"); v.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            v.lineBreakMode = .byTruncatingMiddle
            v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            v.setAccessibilityIdentifier("cell-" + n.lowercased().replacingOccurrences(of: " ", with: "-"))
            cells[n] = v
            let c = NSStackView(views: [l, v]); c.orientation = .vertical; c.alignment = .leading; c.spacing = 1
            cols.append(c)
        }
        let table = NSStackView(views: cols)
        table.orientation = .horizontal; table.spacing = 18; table.distribution = .fill
        cells["FILE"]!.superview?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // the hairline that fills
        progress.wantsLayer = true; fill.wantsLayer = true
        progress.layer?.backgroundColor = NSColor.separatorColor.cgColor
        fill.layer?.backgroundColor = Ink.green.cgColor
        progress.translatesAutoresizingMaskIntoConstraints = false; fill.translatesAutoresizingMaskIntoConstraints = false
        progress.addSubview(fill)
        fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([progress.heightAnchor.constraint(equalToConstant: 1), fill.heightAnchor.constraint(equalToConstant: 1),
                                     fill.leadingAnchor.constraint(equalTo: progress.leadingAnchor), fill.topAnchor.constraint(equalTo: progress.topAnchor), fillWidth])

        live.isEditable = false
        live.font = .systemFont(ofSize: 13)
        live.textContainerInset = NSSize(width: 6, height: 6)
        live.autoresizingMask = [.width]
        liveScroll.documentView = live
        liveScroll.hasVerticalScroller = true
        liveScroll.borderType = .noBorder
        liveScroll.translatesAutoresizingMaskIntoConstraints = false
        liveScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        for b in [cancel, open] {
            b.isBordered = false; b.target = self
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: Ink.grey])
        }
        cancel.action = #selector(stop); cancel.setAccessibilityIdentifier("stop-file"); cancel.setAccessibilityLabel("Stop")
        open.action = #selector(showFiles); open.setAccessibilityIdentifier("show-files"); open.setAccessibilityLabel("Show the saved files")
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 11); status.lineBreakMode = .byTruncatingTail
        let bottom = NSStackView(views: [status, NSView(), open, cancel]); bottom.orientation = .horizontal; bottom.spacing = 12

        jobBox.orientation = .vertical; jobBox.alignment = .leading; jobBox.spacing = 6
        for v in [table, progress, liveScroll, bottom] as [NSView] { jobBox.addArrangedSubview(v) }
        for v in [table, progress, liveScroll, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: jobBox.widthAnchor).isActive = true }
        jobBox.isHidden = true

        let rule = NSBox(); rule.boxType = .separator
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        for v in [top, jobBox, rule] as [NSView] { view.addArrangedSubview(v) }
        for v in [jobBox, rule] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true }
    }

    /// the engines of the catalogue, the unavailable ones greyed (the History picker's list); the engine picked in the app first
    func fillEngines() {
        let keep = engine.selectedItem?.representedObject as? String ?? HearEngine.current.id
        engine.removeAllItems()
        engine.menu?.autoenablesItems = false
        for s in Catalog.all {
            engine.addItem(withTitle: Catalog.shown(s, lang: "auto") + (Catalog.available(s) ? "" : (s.local ? "  (not on this Mac)" : "  (no key)")))
            engine.lastItem?.representedObject = s.id
            engine.lastItem?.isEnabled = Catalog.available(s)
        }
        if let i = engine.itemArray.firstIndex(where: { $0.representedObject as? String == keep && $0.isEnabled }) { engine.selectItem(at: i) }
    }

    @objc func choose() {
        let p = NSOpenPanel()
        p.title = "Transcribe a file"
        p.message = "Choose an audio or video file, any length"
        p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        guard p.runModal() == .OK, let u = p.url else { return }
        start(u)
    }

    /// the engine and the language from the two pickers
    func start(_ url: URL) {
        if let j = job, !j.finished { status.stringValue = "one file is being transcribed: wait for it or press STOP"; jobBox.isHidden = false; return }
        let id = engine.selectedItem?.representedObject as? String ?? HearEngine.current.id
        let l = lang.selectedItem?.representedObject as? String ?? "auto"
        let j = FileJobs.start(path: url.path, engine: HearEngine(id: id, lang: l))
        watch(j)
    }

    func watch(_ j: FileJob) {
        job = j; shown = 0; savedJSON = ""
        live.string = ""
        jobBox.isHidden = false
        open.isHidden = true; cancel.isHidden = false
        cells["FILE"]?.stringValue = j.name
        cells["ENGINE"]?.stringValue = j.engine.title
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func clock(_ s: Double) -> String {
        let t = Int(s.rounded()); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    func tick() {
        guard let j = job else { return }
        let s = j.snapshot()
        cells["PIECE"]?.stringValue = s.pieces > 0 ? "\(max(s.piece, 1)) / \(s.pieces)" : "…"
        cells["ELAPSED"]?.stringValue = clock(s.elapsed)
        cells["TIME LEFT"]?.stringValue = s.eta.map(clock) ?? "…"
        cells["DONE"]?.stringValue = String(format: "%.0f %%", s.percent)
        fillWidth.constant = progress.bounds.width * CGFloat(s.percent / 100)
        if s.segs.count > shown {
            let add = s.segs.dropFirst(shown).map { "\(FileJobs.mmss($0.start))  \($0.text)" }.joined(separator: "\n")
            live.textStorage?.append(NSAttributedString(string: (shown == 0 ? "" : "\n") + add, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
            shown = s.segs.count
            live.scrollToEndOfDocument(nil)
        }
        switch s.state {
        case "queued": status.stringValue = "waiting for the file before it"
        case "extracting": status.stringValue = "ffmpeg is taking the sound out (mono, 16 kHz)…"
        case "running": status.stringValue = s.note.isEmpty ? "hearing piece \(s.piece) of \(s.pieces) with \(j.engine.title)…" : s.note
        case "done":
            status.stringValue = "saved: \(s.json)"
            finished(s)
        case "cancelled", "failed":
            status.stringValue = (s.state == "failed" ? "stopped: " : "") + s.error + (s.json.isEmpty ? "" : "  ·  partial saved")
            status.textColor = s.state == "failed" ? Ink.red : .secondaryLabelColor
            finished(s)
        default: break
        }
        if s.state == "running" || s.state == "queued" || s.state == "extracting" { status.textColor = .secondaryLabelColor }
    }

    func finished(_ s: FileJob.Snapshot) {
        timer?.invalidate(); timer = nil
        cancel.isHidden = true
        savedJSON = s.json
        open.isHidden = s.json.isEmpty
        fillWidth.constant = progress.bounds.width * CGFloat(s.percent / 100)
        onDone()
    }

    @objc func stop() { job?.cancel(); status.stringValue = "stopping after this piece…" }

    @objc func showFiles() {
        if !savedJSON.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: savedJSON)]) }
    }
}
