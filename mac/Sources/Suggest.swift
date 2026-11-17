// Typing suggestions, like his phone (v51).
//
// Marko, 17.11.2026: "It detects if I'm typing text, and then it offers me corrected words or finishing what I'm typing ...
// it will be available in blob and also in the menu bar. And when I'm typing, every time I press alt space, it's going to
// apply correction automatically. It is going to correct or finish my work, and it's just listing their same as my phone
// is doing." And: "bring some free model ... auto completion on Croatian and English, understanding and learning about my
// sentences and my habits ... Even better than SwiftKey, working with local engine."
//
// What is here needs no download: a noisy-channel corrector (edits weighted by which keys are neighbours) and a completer,
// both ranked by a language model made of TTT's dictionaries (word frequency, word pairs and triples, Croatian and English)
// and a PERSONAL layer (his own words, pairs and triples from History and from the suggestions he accepted, newer counts
// more). Croatian letters come back by themselves (zelim → želim). His names and personal words are never "corrected".
// Nothing he types is stored or logged: the word being typed and the two words before it live in memory only.
//
// The keys are read by an event tap (the Accessibility permission the app already has); Option+Space is swallowed only
// while a suggestion is showing. Off in password boxes (secure input), in terminals, in Vox's own windows and while a
// take is recorded.
import AppKit
import Carbon

// MARK: the personal layer

final class Personal {
    static let shared = Personal()
    /// ONE queue for the ranking and for everything that changes this layer (it is read while he types)
    static let queue = DispatchQueue(label: "typing-suggest", qos: .userInitiated)
    private let lock = NSLock()
    private(set) var uni: [String: Double] = [:]
    private(set) var bi: [String: Double] = [:]
    private(set) var tri: [String: Double] = [:]
    private var casedCount: [String: [String: Double]] = [:]
    private(set) var cased: [String: String] = [:]            // lower → as he writes it, when that is not all lower case
    private(set) var sorted: [String] = []
    private(set) var nextBi: [String: [(String, Double)]] = [:]
    private(set) var nextTri: [String: [(String, Double)]] = [:]
    private(set) var built = false
    static let wordRe = try! NSRegularExpression(pattern: "\\p{L}[\\p{L}'’]*")
    static var acceptedFile: URL { appSupport.appendingPathComponent("accepted.json") }

    static func sentences(_ text: String) -> [[String]] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { s in
            let ns = s as NSString
            return wordRe.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }.filter { !$0.isEmpty }
    }

    private func add(_ words: [String], _ w: Double) {
        let lower = words.map { $0.lowercased() }
        for (i, l) in lower.enumerated() {
            uni[l, default: 0] += w
            // a capital inside a sentence is his spelling of a name ("Claude"); the first word of a sentence says nothing
            if i > 0, words[i] != l { casedCount[l, default: [:]][words[i], default: 0] += w }
            if i > 0 { bi[lower[i - 1] + " " + l, default: 0] += w }
            if i > 1 { tri[lower[i - 2] + " " + lower[i - 1] + " " + l, default: 0] += w }
        }
    }

    /// from History (every take's last version) and the accepted suggestions; a month halves a count
    func build(excluding: Set<String> = []) {
        lock.lock(); defer { lock.unlock() }
        uni = [:]; bi = [:]; tri = [:]; casedCount = [:]
        let now = Date()
        for e in History.all() where !excluding.contains(e.id) {
            let v = e.latest
            guard !v.text.isEmpty else { continue }
            let w = pow(0.5, now.timeIntervalSince(v.at) / (30 * 86400))
            for s in Personal.sentences(v.text) { add(s, max(w, 0.05)) }
        }
        if let d = try? Data(contentsOf: Personal.acceptedFile), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            for o in a {
                guard let words = o["w"] as? [String], let at = o["at"] as? Double else { continue }
                add(words, max(pow(0.5, (now.timeIntervalSince1970 - at) / (30 * 86400)), 0.05))
            }
        }
        finish()
    }

    private func finish() {
        cased = [:]
        for (l, forms) in casedCount {
            let total = forms.values.reduce(0, +)
            if let best = forms.max(by: { $0.value < $1.value }), total >= (uni[l] ?? 0) * 0.6 { cased[l] = best.key }
        }
        sorted = uni.keys.sorted()
        var nb: [String: [(String, Double)]] = [:], nt: [String: [(String, Double)]] = [:]
        for (k, c) in bi { if let sp = k.firstIndex(of: " ") { nb[String(k[..<sp]), default: []].append((String(k[k.index(after: sp)...]), c)) } }
        for (k, c) in tri { if let sp = k.lastIndex(of: " ") { nt[String(k[..<sp]), default: []].append((String(k[k.index(after: sp)...]), c)) } }
        nextBi = nb.mapValues { Array($0.sorted { $0.1 > $1.1 }.prefix(12)) }
        nextTri = nt.mapValues { Array($0.sorted { $0.1 > $1.1 }.prefix(12)) }
        built = true
    }

    /// a take he dictated, or a suggestion he took (with the two words before it): counted at once
    func learn(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard built else { return }
        for s in Personal.sentences(text) { add(s, 1) }
        finish()
    }
    func accepted(_ words: [String]) {
        guard !words.isEmpty else { return }
        lock.lock()
        if built { add(words, 1); add(words, 1); finish() }      // taken by hand counts double
        lock.unlock()
        // on disk only the word he took, never the words he typed before it (those stay in memory until the app quits)
        var a = (try? Data(contentsOf: Personal.acceptedFile)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        a.append(["w": [words.last!], "at": Date().timeIntervalSince1970])
        if a.count > 3000 { a.removeFirst(a.count - 3000) }
        if let d = try? JSONSerialization.data(withJSONObject: a) { try? d.write(to: Personal.acceptedFile, options: .atomic) }
    }

    func completions(_ prefix: String) -> ArraySlice<String> {
        var lo = 0, hi = sorted.count
        while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] < prefix { lo = mid + 1 } else { hi = mid } }
        var end = lo
        while end < sorted.count, end - lo < 400, sorted[end].hasPrefix(prefix) { end += 1 }
        return sorted[lo..<end]
    }
}

// MARK: the ranking

struct Suggestion: Equatable {
    enum Kind: String { case completion, correction, next }
    let text: String
    let kind: Kind
    let score: Double
}

enum Predictor {
    /// what the benchmark compares: the dictionary alone (frequency), then with word pairs and triples, then with his own layer
    struct Options { var context = true; var personal = true; var corrections = true }

    /// the weights of the ranking; measured on his own sentences (--bench-complete), and changeable for a measurement without
    /// a new build: VOX_W="bi=40,tri=40,pu=30,pb=70,pt=70,next=90,lean=14,len=0"
    static var w: [String: Double] = {
        var d: [String: Double] = ["bi": 40, "tri": 40, "pu": 30, "pb": 70, "pt": 70, "next": 90, "lean": 14, "len": 0, "su": 4, "sb": 6, "st": 8]
        for part in (ProcessInfo.processInfo.environment["VOX_W"] ?? "").split(separator: ",") {
            let kv = part.split(separator: "=")
            if kv.count == 2, let v = Double(kv[1]) { d[String(kv[0])] = v }
        }
        return d
    }()
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { Array($0) }
    static let neighbours: [Character: Set<Character>] = {
        var m: [Character: Set<Character>] = [:]
        for (r, row) in rows.enumerated() {
            for (i, c) in row.enumerated() {
                var s = Set<Character>()
                if i > 0 { s.insert(row[i - 1]) }
                if i + 1 < row.count { s.insert(row[i + 1]) }
                for rr in [r - 1, r + 1] where rr >= 0 && rr < rows.count {
                    for j in [i - 1, i, i + 1] where j >= 0 && j < rows[rr].count { s.insert(rows[rr][j]) }
                }
                m[c] = s
            }
        }
        // a Croatian keyboard has z where the English one has y
        m["z", default: []].formUnion(m["y"] ?? []); m["y", default: []].formUnion(["x", "s", "a"])
        return m
    }()
    static let letters = Array("abcdefghijklmnopqrstuvwxyz")

    /// one edit away, with what the slip costs: a neighbouring key and two letters swapped are the cheapest
    static func edits(_ word: String) -> [String: Double] {
        let w = Array(word)
        var out: [String: Double] = [:]
        func put(_ s: [Character], _ cost: Double) { let k = String(s); if k != word, (out[k] ?? .infinity) > cost { out[k] = cost } }
        for i in 0...w.count {
            if i < w.count { var d = w; d.remove(at: i); put(d, i > 0 && w[i] == w[i - 1] ? 22 : 34) }        // a letter typed twice
            if i + 1 < w.count { var t = w; t.swapAt(i, i + 1); put(t, 20) }
            for c in letters {
                if i < w.count, c != w[i] { var s = w; s[i] = c; put(s, neighbours[w[i]]?.contains(c) == true ? 24 : 40) }
                var ins = w; ins.insert(c, at: i); put(ins, 34)
            }
        }
        return out
    }

    private static func lg(_ x: Double) -> Double { log10(1 + x) }

    /// up to three suggestions for the word being typed (`prefix`, as typed) after `prev` (lower case, the newest last);
    /// `bias` leans the ranking towards Croatian (+1) or English (-1) from the words just typed
    static func suggest(_ prefix: String, prev: [String], sentenceStart: Bool = false, bias: Double = 0, options: Options = Options()) -> [Suggestion] {
        let p = prefix.lowercased()
        let lex = ["en", "hr"].compactMap { Lexicon.get($0) }
        guard !lex.isEmpty else { return [] }
        let me = Personal.shared
        let p1 = options.context ? prev.last : nil
        let p2 = options.context && prev.count > 1 ? prev[prev.count - 2] : nil
        let W = Predictor.w
        let wBi = W["bi"]!, wTri = W["tri"]!, pu = W["pu"]!, pb = W["pb"]!, pt = W["pt"]!, su = W["su"]!, sb = W["sb"]!, st = W["st"]!
        func lean(_ l: Lexicon) -> Double { (l.lang == "hr" ? 1 : -1) * W["lean"]! * bias }
        func context(_ l: Lexicon, _ w: String) -> Double {
            var s = 0.0
            if let p1 { s += wBi * lg(Double(l.bigrams[p1 + " " + w] ?? 0)); if let p2 { s += wTri * lg(Double(l.trigrams[p2 + " " + p1 + " " + w] ?? 0)) } }
            return s
        }
        func own(_ w: String) -> Double {
            guard options.personal else { return 0 }
            var s = pu * lg((me.uni[w] ?? 0) * su)
            if let p1 { s += pb * lg((me.bi[p1 + " " + w] ?? 0) * sb); if let p2 { s += pt * lg((me.tri[p2 + " " + p1 + " " + w] ?? 0) * st) } }
            return s
        }
        var scores: [String: (Double, Suggestion.Kind)] = [:]
        func offer(_ w: String, _ s: Double, _ k: Suggestion.Kind) { if s > (scores[w]?.0 ?? -.infinity) { scores[w] = (s, k) } }
        func base(_ w: String) -> (Double, Lexicon?) {
            var best: (Double, Lexicon?) = (-1, nil)
            for l in lex { if let f = l.words[w], Double(f) + lean(l) > best.0 { best = (Double(f) + lean(l), l) } }
            return best
        }

        if p.isEmpty {
            // the next word, from the two before it
            guard let p1 else { return [] }
            var cands = Set<String>()
            if options.personal {
                for (w, _) in me.nextBi[p1] ?? [] { cands.insert(w) }
                if let p2 { for (w, _) in me.nextTri[p2 + " " + p1] ?? [] { cands.insert(w) } }
            }
            for l in lex {
                for (w, _) in l.nextBi[p1] ?? [] { cands.insert(w) }
                if let p2 { for (w, _) in l.nextTri[p2 + " " + p1] ?? [] { cands.insert(w) } }
            }
            for w in cands {
                let (b, l) = base(w)
                let c = (l.map { context($0, w) } ?? 0) + own(w)
                if c >= W["next"]! { offer(w, max(b, 150) * 0.3 + c, .next) }      // only what the words before clearly lead to
            }
        } else {
            let fp = Lexicon.fold(p)
            let known = lex.contains { $0.words[p] != nil } || (me.uni[p] ?? 0) > 0
            // completions: the commonest words that start like this, then the words before decide
            var pool: [String: Double] = [:]
            for l in lex {
                for w in l.completions(p, limit: 20000) { let f = Double(l.words[w] ?? 0) + lean(l); if f > (pool[w] ?? -1) { pool[w] = f } }
                if l.lang == "hr", fp == p {
                    // Croatian letters come back: what he types without them finds the words that have them
                    for (w, f) in l.foldedCompletions(fp, limit: 20000) { let s = Double(f) + lean(l) + (Lexicon.fold(w) == p ? 6 : 0); if s > (pool[w] ?? -1) { pool[w] = s } }
                }
                if let p1 { for (w, _) in l.nextBi[p1] ?? [] where w.hasPrefix(p) { pool[w] = max(pool[w] ?? -1, Double(l.words[w] ?? 150) + lean(l)) } }
            }
            if options.personal { for w in me.completions(p) { pool[w] = max(pool[w] ?? -1, max(base(w).0, 150)) } }
            let top = pool.sorted { $0.value > $1.value }.prefix(300)
            var strong = 0
            for (w, f) in top where w != p {
                let l = base(w).1
                if f >= 170 { strong += 1 }
                // "len": a word that saves more keys may be worth a little more
                offer(w, f + (l.map { context($0, w) } ?? 0) + own(w) + W["len"]! * Double(min(w.count - p.count, 6)), .completion)
            }
            // corrections: only for a word nobody knows, never for his own words or a name (a capital inside a sentence)
            let name = prefix.first?.isUppercase == true && !sentenceStart
            if options.corrections, !known, !name, p.count >= 3 {
                if let en = lex.first(where: { $0.lang == "en" }), let right = en.misspellings[p] { offer(right, 400, .correction) }
                // while common words still begin like this he is simply not finished: no "corrections" of a word half typed
                for (e, cost) in (strong >= 3 ? [:] : edits(fp)) {
                    for l in lex {
                        let hit: (String, Int)? = l.lang == "hr" ? l.folded[e] : l.words[e].map { (e, $0) }
                        guard let (w, f) = hit, f >= 150 else { continue }
                        offer(w, Double(f) + lean(l) + context(l, w) + own(w) - cost + 28, .correction)
                    }
                }
            }
        }
        let ranked = scores.sorted { $0.value.0 > $1.value.0 }.prefix(3)
        return ranked.map { w, v in
            var text = me.cased[w] ?? w
            if prefix.count >= 2, prefix == prefix.uppercased(), prefix != prefix.lowercased() { text = text.uppercased() }
            else if prefix.first?.isUppercase == true || (p.isEmpty && sentenceStart) { text = text.capitalizedFirst }
            return Suggestion(text: text, kind: v.1, score: v.0)
        }
    }
}

extension Lexicon {
    /// Croatian words by their letters without diacritics, for a prefix typed without them
    func foldedCompletions(_ prefix: String, limit: Int) -> [(String, Int)] {
        let keys = foldedSorted
        var lo = 0, hi = keys.count
        while lo < hi { let mid = (lo + hi) / 2; if keys[mid].0 < prefix { lo = mid + 1 } else { hi = mid } }
        var out: [(String, Int)] = []
        var i = lo
        while i < keys.count, out.count < limit, keys[i].0.hasPrefix(prefix) { out.append((keys[i].1, words[keys[i].1] ?? 0)); i += 1 }
        return out
    }
}

// MARK: the strip on the blob

final class SuggestStrip {
    let panel: NSPanel
    private let stack = NSStackView()
    var onPick: ((Int) -> Void)?
    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: PILL_W, height: 26), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        let back = NSView(frame: panel.contentView!.bounds)
        back.wantsLayer = true
        back.layer?.backgroundColor = Host.bg.withAlphaComponent(0.96).cgColor
        back.layer?.cornerRadius = 13
        back.layer?.borderWidth = 1; back.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        back.autoresizingMask = [.width, .height]
        stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 0
        stack.frame = back.bounds.insetBy(dx: 8, dy: 0); stack.autoresizingMask = [.width, .height]
        back.addSubview(stack)
        panel.contentView = back
        panel.setAccessibilityLabel("Typing suggestions")
    }
    func show(_ words: [String], over blob: NSRect) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, w) in words.enumerated() {
            let b = HoverButton(title: w, target: self, action: #selector(picked(_:)))
            b.tag = i; b.isBordered = false
            b.attributedTitle = NSAttributedString(string: w, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: i == 0 ? .bold : .regular), .foregroundColor: i == 0 ? Host.ink : Host.muted])
            b.setAccessibilityIdentifier("suggestion-\(i)"); b.setAccessibilityLabel("Suggestion: " + w)
            b.toolTip = i == 0 ? "Option+Space puts this in" : "Click to put this in"
            stack.addArrangedSubview(b)
        }
        // on the blob's own centre line: above it, or below when the blob is in the upper half of its screen
        let below = BlobPanel.upperHalf(blob)
        let pill = NSRect(x: blob.midX - PILL_W / 2, y: blob.minY, width: PILL_W, height: PILL_H)
        panel.setFrame(NSRect(x: pill.minX, y: below ? pill.minY - 26 - 4 : pill.maxY + 4, width: PILL_W, height: 26), display: true)
        panel.orderFrontRegardless()
    }
    func hide() { if panel.isVisible { panel.orderOut(nil) } }
    @objc func picked(_ b: NSButton) { onPick?(b.tag) }
}

/// a borderless button that lights when the pointer is on it (every pressable control highlights)
final class HoverButton: NSButton {
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with e: NSEvent) { wantsLayer = true; layer?.cornerRadius = 6; layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor }
    override func mouseExited(with e: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: the keys

final class TypingSuggest {
    static let shared = TypingSuggest()
    static let mark: Int64 = 0x566F7854                    // "VoxT": the keys this app posts itself, never read back
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "typingSuggestions") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "typingSuggestions"); DispatchQueue.main.async { shared.apply() } }
    }
    private(set) var tapFailed = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var word = ""
    private var prev: [String] = []
    private var sentenceStart = true
    private var bias = 0.0
    private var textBox: Bool?                 // is the focus a text box (asked once per place: after a click or an app change)
    private var boxPid: pid_t = 0
    private var generation = 0
    private(set) var shown: [Suggestion] = []
    private let strip = SuggestStrip()
    private let queue = Personal.queue
    private weak var stripe: Stripe?
    private var observer: NSObjectProtocol?

    func setup(_ s: Stripe) {
        stripe = s
        strip.onPick = { [weak self] i in self?.take(i) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.reset(place: true) }
        apply()
    }

    /// the switch: the tap exists only while it is on
    func apply() {
        if TypingSuggest.on { start() } else { stop() }
        stripe?.settings?.paintTyping()
    }

    private func start() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, ref in
            let me = Unmanaged<TypingSuggest>.fromOpaque(ref!).takeUnretainedValue()
            return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                        callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            tapFailed = true
            appendLog("typing suggestions: macOS did not give the keys (Accessibility or Input Monitoring is missing): PERMISSIONS")
            return
        }
        tapFailed = false
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        appendLog("typing suggestions: on (Option+Space takes the first)")
        queue.async { _ = Lexicon.get("en"); _ = Lexicon.get("hr"); if !Personal.shared.built { Personal.shared.build() } }
    }

    private func stop() {
        clear()
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if tap != nil { appendLog("typing suggestions: off") }
        tap = nil; source = nil
    }

    private func reset(place: Bool) {
        word = ""; prev = []; sentenceStart = true
        if place { textBox = nil }
        clear()
    }

    private func clear() {
        generation += 1
        if !shown.isEmpty { shown = []; strip.hide(); stripe?.showSuggestions([]) }
    }

    private var quiet: Bool {
        if IsSecureEventInputEnabled() { return true }
        if let s = stripe, s.recorder.recording || s.busy || Typer.inserting > 0 { return true }
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        if app.processIdentifier == getpid() { return true }
        return Writer.terminals.contains(app.bundleIdentifier ?? "")
    }

    /// true = the key is swallowed (only Option+Space while a suggestion is showing)
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }; return false }
        if event.getIntegerValueField(.eventSourceUserData) == TypingSuggest.mark { return false }
        if type != .keyDown {
            // a click ON a suggestion (the strip, or the menu bar item) must find it still there; any other click moves the caret
            if !shown.isEmpty, ownClick(event.location) { return false }
            reset(place: true); return false
        }
        if quiet { if !word.isEmpty || !shown.isEmpty || !prev.isEmpty { reset(place: true) }; return false }
        let flags = event.flags
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { reset(place: false); return false }
        if code == Int64(kVK_Space), flags.contains(.maskAlternate), !flags.contains(.maskShift) {
            if let first = shown.first { put(first); return true }
            return false
        }
        if code == Int64(kVK_Delete) {
            if word.isEmpty { reset(place: false) } else { word.removeLast(); changed() }
            return false
        }
        var len = 0
        var buf = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &buf)
        let s = String(utf16CodeUnits: buf, count: len)
        guard let c = s.first, s.count == 1 else { reset(place: false); return false }
        if c.isLetter || ((c == "'" || c == "’") && !word.isEmpty) {
            if word.isEmpty { askBox() }
            word.append(c)
            changed()
        } else if c == " " || c == "\u{00A0}" {
            endWord()
            changed()
        } else if ".!?".contains(c) {
            endWord(); prev = []; sentenceStart = true; clear()
        } else if c == "\r" || c == "\n" || c == "\t" {
            reset(place: false)
        } else if c.isPunctuation || c.isSymbol || c.isNumber {
            endWord(); clear()
        } else {
            reset(place: false)            // arrows, Esc, function keys: the caret may be anywhere now
        }
        return false
    }

    private func ownClick(_ p: CGPoint) -> Bool {
        guard let top = NSScreen.screens.first?.frame.maxY else { return false }
        let c = NSPoint(x: p.x, y: top - p.y)                    // the event's point has its origin at the top left
        if strip.panel.isVisible, strip.panel.frame.insetBy(dx: -2, dy: -2).contains(c) { return true }
        if let f = MenuDisplay.shared.itemFrame, f.insetBy(dx: -2, dy: -2).contains(c) { return true }
        return false
    }

    private func endWord() {
        guard !word.isEmpty else { return }
        let l = word.lowercased()
        // which language he is typing: words only one of the two dictionaries knows pull the ranking that way
        if let hr = Lexicon.get("hr"), let en = Lexicon.get("en") {
            let h = hr.words[l] != nil || hr.folded[Lexicon.fold(l)] != nil, e = en.words[l] != nil
            bias = max(-1, min(1, bias * 0.8 + (h && !e ? 0.35 : e && !h ? -0.35 : 0)))
        }
        prev.append(l); if prev.count > 2 { prev.removeFirst() }
        word = ""; sentenceStart = false
    }

    /// is the focus a text box at all (a game, Finder's list, a shortcut field are not): asked once per place
    private func askBox() {
        guard textBox == nil else { return }
        textBox = true
        queue.async {
            let sys = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(sys, 0.3)
            var ok = true
            if let f = TextTarget.element(TextTarget.attr(sys, kAXFocusedUIElementAttribute)) {
                let role = TextTarget.role(f), sub = TextTarget.attr(f, kAXSubroleAttribute) as? String ?? ""
                if sub == "AXSecureTextField" { ok = false }
                else if TextTarget.editable(f) == nil, !["AXWebArea", "AXGroup", "AXScrollArea", "?"].contains(role) { ok = false }
            }
            DispatchQueue.main.async { self.textBox = ok; if !ok { self.clear() } }
        }
    }

    private func changed() {
        generation += 1
        let g = generation, w = word, p = prev, start = sentenceStart, b = bias
        guard textBox != false, !(w.isEmpty && p.isEmpty) else { clear(); return }
        queue.async {
            let s = Predictor.suggest(w, prev: p, sentenceStart: start, bias: b)
            DispatchQueue.main.async {
                guard g == self.generation else { return }
                self.shown = s
                self.display()
            }
        }
    }

    private func display() {
        let words = shown.map(\.text)
        stripe?.showSuggestions(words)
        if words.isEmpty { strip.hide(); return }
        if let s = stripe, s.minimizedFrame == nil, s.panel.isVisible { strip.show(words, over: s.panel.frame) } else { strip.hide() }
    }

    /// a click on a suggestion (the strip on the blob, or the menu bar item for the first)
    func take(_ i: Int) { if i < shown.count { put(shown[i]) } }

    /// the word being typed is replaced by the suggestion (only that word), a space after it
    private func put(_ s: Suggestion) {
        let typed = word.count
        let src = CGEventSource(stateID: .privateState)
        func key(_ code: CGKeyCode, _ text: String? = nil) {
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
                e.flags = []
                if let text { let u = Array(text.utf16); e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u) }
                e.setIntegerValueField(.eventSourceUserData, value: TypingSuggest.mark)
                e.post(tap: .cgSessionEventTap)
            }
        }
        for _ in 0..<typed { key(CGKeyCode(kVK_Delete)) }
        let text = s.text + " "
        var chunk = ""
        for c in text { chunk.append(c); if chunk.utf16.count >= 16 { key(0, chunk); chunk = "" } }
        if !chunk.isEmpty { key(0, chunk) }
        let context = prev
        word = s.text
        endWord()
        let took = context + [s.text]
        queue.async { Personal.shared.accepted(took) }       // what he took teaches the ranking
        changed()
    }
}

// MARK: the benchmark: his own sentences cut halfway, the second half typed key by key

enum CompleteBench {
    static func percentile(_ a: [Double], _ p: Double) -> Double { guard !a.isEmpty else { return 0 }; let s = a.sorted(); return s[min(s.count - 1, Int(Double(s.count) * p))] }

    /// --bench-complete [n]: n sentences from History (the newest, ten words or more), held out of the personal layer; the first
    /// half is the context, the second half is typed. Top-1 = Option+Space would put the word in; top-3 = it is on the strip.
    static func run(_ n: Int) -> Int32 {
        var seen = Set<String>(), picked: [(String, String, [String])] = []
        for e in History.all().sorted(by: { $0.latest.at > $1.latest.at }) {
            let v = e.latest
            let words = Personal.sentences(v.text).flatMap { $0 }
            guard words.count >= 10, seen.insert(v.text).inserted else { continue }
            picked.append((e.id, v.lang, Array(words.prefix(40))))
            if picked.count == n { break }
        }
        guard !picked.isEmpty else { print("no sentences in History"); return 1 }
        Personal.shared.build(excluding: Set(picked.map { $0.0 }))
        _ = Lexicon.get("en"); _ = Lexicon.get("hr")
        let variants: [(String, Predictor.Options)] = [
            ("dictionary only (word frequency)", Predictor.Options(context: false, personal: false, corrections: false)),
            ("+ word pairs and triples", Predictor.Options(context: true, personal: false, corrections: false)),
            ("+ his own layer (History)", Predictor.Options(context: true, personal: true, corrections: true)),
        ]
        var report: [[String: Any]] = []
        print("\(picked.count) sentences from History (\(picked.filter { $0.1 == "hr" }.count) Croatian), second halves typed key by key\n")
        for (name, opt) in variants {
            var words = 0, next1 = 0, in2top1 = 0, in2top3 = 0, keys = 0, used1 = 0, used3 = 0
            var ms: [Double] = []
            for (_, _, sentence) in picked {
                let half = sentence.count / 2
                var prev: [String] = [], bias = 0.0
                func push(_ w: String) {
                    let l = w.lowercased()
                    if let hr = Lexicon.get("hr"), let en = Lexicon.get("en") {
                        let h = hr.words[l] != nil || hr.folded[Lexicon.fold(l)] != nil, e = en.words[l] != nil
                        bias = max(-1, min(1, bias * 0.8 + (h && !e ? 0.35 : e && !h ? -0.35 : 0)))
                    }
                    prev.append(l); if prev.count > 2 { prev.removeFirst() }
                }
                for w in sentence[..<half] { push(w) }
                for w in sentence[half...] {
                    let cs = Array(w), target = w.lowercased()
                    let full = cs.count + 1
                    var u1 = full, u3 = full, got1 = false, got3 = false
                    for k in 0..<cs.count {
                        let t0 = Date()
                        let s = Predictor.suggest(String(cs[..<k]), prev: prev, bias: bias, options: opt).map { $0.text.lowercased() }
                        ms.append(Date().timeIntervalSince(t0) * 1000)
                        if k == 0, s.first == target { next1 += 1 }
                        if k <= 2 { if s.first == target { got1 = true }; if s.contains(target) { got3 = true } }
                        if u1 == full, s.first == target { u1 = k + 1 }
                        if u3 == full, s.contains(target) { u3 = k + 1 }
                    }
                    words += 1; keys += full; used1 += u1; used3 += u3
                    if got1 { in2top1 += 1 }
                    if got3 { in2top3 += 1 }
                    push(w)
                }
            }
            func pct(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : (Double(a) / Double(b) * 1000).rounded() / 10 }
            let row: [String: Any] = ["variant": name, "words": words, "next_word_top1_pct": pct(next1, words), "top1_within_2_keys_pct": pct(in2top1, words),
                                      "top3_within_2_keys_pct": pct(in2top3, words), "keystrokes_saved_top1_pct": pct(keys - used1, keys),
                                      "keystrokes_saved_top3_pct": pct(keys - used3, keys),
                                      "latency_ms_mean": (ms.reduce(0, +) / Double(max(ms.count, 1)) * 100).rounded() / 100,
                                      "latency_ms_p95": (percentile(ms, 0.95) * 100).rounded() / 100, "latency_ms_max": (percentile(ms, 1) * 100).rounded() / 100]
            report.append(row)
            print(name)
            print("  words typed \(words) · next word right before any key \(row["next_word_top1_pct"]!) % · first suggestion right within 2 keys \(row["top1_within_2_keys_pct"]!) % · on the strip within 2 keys \(row["top3_within_2_keys_pct"]!) %")
            print("  keystrokes saved: \(row["keystrokes_saved_top1_pct"]!) % with Option+Space only, \(row["keystrokes_saved_top3_pct"]!) % with a pick from the strip · time per key mean \(row["latency_ms_mean"]!) ms, p95 \(row["latency_ms_p95"]!) ms, slowest \(row["latency_ms_max"]!) ms\n")
        }
        if let d = try? JSONSerialization.data(withJSONObject: ["at": Shared.stamp(), "sentences": picked.count, "results": report], options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: appSupport.appendingPathComponent("bench/completion.json"), options: .atomic)
        }
        return 0
    }
}
