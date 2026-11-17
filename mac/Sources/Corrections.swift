// TTT's correction algorithm on the Mac (v50).
//
// Marko, 17.11.2026: "look at my TTT. I want you to copy algorithm for corrections to this app. So it corrects everything
// nicely from the database and copy database of TTT." This file is TTT's dictate/nlp code in Swift, kept in TTT's order
// (DictateController.kt): Cyrillic to Latin, the Croatian fix from the keyboard's own dictionary (MaCroatianFix), [the
// Claude correction, when it is on], his names (MaNameSpelling), spoken times (MaSpokenTime), the spelling table
// (MaSpelling, pairs.json), his learned corrections (MaCorrectionRules), then the open chat's name (Names.swift).
// The database is TTT's: Resources/dict (hr.json, en.json, the bigrams and trigrams) and the shared repository
// MANTRA_CORRECTIONS (Shared.swift). Not ported: MaSpokenFormat (spoken commands, "the word parenthesis"), MaSpokenEmail
// (it matches the phone's address book) and MaParagraphs.
import Foundation

// MARK: small helpers

extension String {
    /// every match of `pattern` replaced by what `f` returns for it
    func replacing(_ re: NSRegularExpression, _ f: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = self as NSString
        var out = "", last = 0
        for m in re.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(m, ns)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
    var capitalizedFirst: String { guard let f = first else { return self }; return String(f).uppercased() + dropFirst() }
}

func wordPattern(_ words: String) -> NSRegularExpression? {
    let parts = words.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        .map { NSRegularExpression.escapedPattern(for: $0) }
    guard !parts.isEmpty else { return nil }
    return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + parts.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
}

// MARK: the dictionaries (TTT's ime/dict), loaded when first needed, let go after ten idle minutes

final class Lexicon {
    let lang: String
    private(set) var words: [String: Int] = [:]                 // lower case → 128…255 (a log scale)
    private(set) var folded: [String: (String, Int)] = [:]      // without diacritics → the commonest word that folds to it
    private(set) var bigrams: [String: Int] = [:]
    private(set) var trigrams: [String: Int] = [:]
    private(set) var sorted: [String] = []                      // for completions by prefix
    private(set) var foldedSorted: [(String, String)] = []      // Croatian: (without diacritics, the word), for a prefix typed without them
    private(set) var nextBi: [String: [(String, Int)]] = [:]    // the commonest words after one word
    private(set) var nextTri: [String: [(String, Int)]] = [:]   // and after two
    private(set) var misspellings: [String: String] = [:]       // English only (Wikipedia's list)

    static func fold(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "č", "ć": out.append("c")
            case "š": out.append("s")
            case "ž": out.append("z")
            case "đ": out.append("d")
            default: out.append(c)
            }
        }
        return out
    }

    static var folder: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("dict"), FileManager.default.fileExists(atPath: r.path) { return r }
        return nil
    }

    private init?(_ lang: String) {
        self.lang = lang
        guard let dir = Lexicon.folder,
              let data = try? Data(contentsOf: dir.appendingPathComponent(lang + ".json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        words.reserveCapacity(obj.count)
        for (w, v) in obj {
            let l = w.lowercased(), f = (v as? NSNumber)?.intValue ?? 0
            if (words[l] ?? 0) < f { words[l] = f }
        }
        for (w, n) in words {
            let k = Lexicon.fold(w)
            if n > (folded[k]?.1 ?? 0) { folded[k] = (w, n) }
        }
        bigrams = Lexicon.counts(dir.appendingPathComponent(lang + "_bigrams.txt"))
        trigrams = Lexicon.counts(dir.appendingPathComponent(lang + "_trigrams.txt"))
        sorted = words.keys.sorted()
        if lang == "hr" { foldedSorted = words.keys.map { (Lexicon.fold($0), $0) }.filter { $0.0 != $0.1 }.sorted { $0.0 < $1.0 } }
        var nb: [String: [(String, Int)]] = [:], nt: [String: [(String, Int)]] = [:]
        for (k, c) in bigrams { if let sp = k.firstIndex(of: " ") { nb[String(k[..<sp]), default: []].append((String(k[k.index(after: sp)...]), c)) } }
        for (k, c) in trigrams { if let sp = k.lastIndex(of: " ") { nt[String(k[..<sp]), default: []].append((String(k[k.index(after: sp)...]), c)) } }
        nextBi = nb.mapValues { Array($0.sorted { $0.1 > $1.1 }.prefix(12)) }
        nextTri = nt.mapValues { Array($0.sorted { $0.1 > $1.1 }.prefix(12)) }
        if lang == "en", let t = try? String(contentsOf: dir.appendingPathComponent("en_misspellings.txt"), encoding: .utf8) {
            for line in t.split(separator: "\n") {
                let p = line.split(separator: "\t")
                if p.count == 2, let right = p[1].split(separator: "|").first { misspellings[String(p[0])] = String(right) }
            }
        }
    }

    private static func counts(_ url: URL) -> [String: Int] {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var m: [String: Int] = [:]
        m.reserveCapacity(90_000)
        for line in t.split(separator: "\n") {
            guard let tab = line.lastIndex(of: "\t"), let n = Int(line[line.index(after: tab)...]) else { continue }
            m[String(line[..<tab])] = n
        }
        return m
    }

    private static var cache: [String: Lexicon] = [:]
    private static let lock = NSLock()
    static var lastUse = Date()
    static func get(_ lang: String) -> Lexicon? {
        guard lang == "hr" || lang == "en" else { return nil }
        lock.lock(); defer { lock.unlock() }
        lastUse = Date()
        if let l = cache[lang] { return l }
        let t0 = Date()
        guard let l = Lexicon(lang) else { return nil }
        cache[lang] = l
        appendLog(String(format: "dictionary %@: %d words, %d pairs, %d triples, %.0f ms", lang, l.words.count, l.bigrams.count, l.trigrams.count, Date().timeIntervalSince(t0) * 1000))
        return l
    }
    /// the dictionaries leave memory after ten minutes without a take or a keystroke that needed them
    static func unloadIfIdle() {
        lock.lock(); defer { lock.unlock() }
        if !cache.isEmpty, Date().timeIntervalSince(lastUse) > 600 { cache.removeAll(); appendLog("dictionaries unloaded (idle)") }
    }

    /// words that start with `prefix` (lower case), in alphabetical order
    func completions(_ prefix: String, limit: Int = 400) -> ArraySlice<String> {
        var lo = 0, hi = sorted.count
        while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] < prefix { lo = mid + 1 } else { hi = mid } }
        var end = lo
        while end < sorted.count, end - lo < limit, sorted[end].hasPrefix(prefix) { end += 1 }
        return sorted[lo..<end]
    }
}

// MARK: MaCyrillic: Latin letters only, whatever the engine wrote

enum Cyrillic {
    static let map: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ђ": "đ", "е": "e", "ж": "ž", "з": "z", "и": "i", "ј": "j", "к": "k",
        "л": "l", "љ": "lj", "м": "m", "н": "n", "њ": "nj", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "ћ": "ć", "у": "u",
        "ф": "f", "х": "h", "ц": "c", "ч": "č", "џ": "dž", "ш": "š", "я": "ja", "ю": "ju", "ё": "jo", "й": "j", "щ": "šč",
        "ы": "i", "э": "e", "ь": "", "ъ": "", "є": "je", "і": "i", "ї": "ji", "ґ": "g", "ѓ": "đ", "ќ": "ć", "ѕ": "dz"]
    static func has(_ t: String) -> Bool { t.unicodeScalars.contains { $0.value >= 0x400 && $0.value <= 0x4FF } }
    static func toLatin(_ text: String) -> String {
        guard has(text) else { return text }
        let chars = Array(text)
        var out = ""
        for (i, c) in chars.enumerated() {
            let lower = Character(String(c).lowercased())
            guard let latin = map[lower] else { out.append(c); continue }
            if c == lower || latin.isEmpty { out += latin; continue }
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let wholeWordUpper = next.map { $0.isLetter && $0.isUppercase } ?? false
            out += wholeWordUpper ? latin.uppercased() : latin.capitalizedFirst
        }
        return out
    }
}

// MARK: MaCroatianFix: diacritics, misheard words, glued and split words, from the dictionary and its word pairs

enum CroatianFix {
    static let minFreq = 170, minFreqSameLength = 150, rare = 140, rareMargin = 60, common = 200, diacriticMargin = 30
    static let lengthChangeCost = 30.0
    static let letters = Array("abcdefghijklmnoprstuvzj")
    static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    static let singleLetterWords: Set<String> = ["i", "u", "a", "s", "k", "o", "v"]
    static let wordRe = try! NSRegularExpression(pattern: "[\\p{L}]+|[^\\p{L}]+")
    static let mergeRe = try! NSRegularExpression(pattern: "\\b(\\p{L}{3,}) (\\p{L}{1,3})\\b")
    static let lettersRe = try! NSRegularExpression(pattern: "\\p{L}+")

    /// more of the words Croatian than English (a Croatian take on the English key)
    static func looksCroatian(_ text: String) -> Bool {
        guard let hr = Lexicon.get("hr"), let en = Lexicon.get("en") else { return false }
        let ns = text.lowercased() as NSString
        let words = lettersRe.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.filter { $0.count >= 2 }
        guard words.count >= 2 else { return false }
        let hrOnly = words.filter { (hr.words[$0] != nil || hr.folded[Lexicon.fold($0)] != nil) && en.words[$0] == nil }.count
        let enOnly = words.filter { en.words[$0] != nil && hr.words[$0] == nil }.count
        return hrOnly > enOnly
    }

    static func apply(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let hr = Lexicon.get("hr"), let en = Lexicon.get("en") else { return text }
        let f = Fixer(hr: hr, en: en)
        return f.correct(f.resegment(f.merge(text)))
    }

    struct Fixer {
        let hr: Lexicon, en: Lexicon

        func ctx(_ prev2: String?, _ prev: String?, _ next: String?, _ cand: String) -> Double {
            var s = 0.0
            if let prev { s += 40 * log10(1.0 + Double(hr.bigrams[prev + " " + cand] ?? 0)) }
            if let next { s += 15 * log10(1.0 + Double(hr.bigrams[cand + " " + next] ?? 0)) }
            if let prev2, let prev { s += 40 * log10(1.0 + Double(hr.trigrams[prev2 + " " + prev + " " + cand] ?? 0)) }
            return s
        }

        func edits(_ word: String) -> Set<String> {
            let w = Array(word)
            var out = Set<String>()
            for i in 0...w.count {
                if i < w.count { var d = w; d.remove(at: i); out.insert(String(d)) }
                if i + 1 < w.count { var t = w; t.swapAt(i, i + 1); out.insert(String(t)) }
                for c in CroatianFix.letters {
                    if i < w.count, c != w[i] { var s = w; s[i] = c; out.insert(String(s)) }
                    var ins = w; ins.insert(c, at: i); out.insert(String(ins))
                }
            }
            return out
        }

        /// endings are misheard far more often ("kavo" for "kavu") than consonants ("kavo" for "kako")
        func shape(_ fs: String, _ cs: String) -> Double {
            let f = Array(fs), c = Array(cs)
            guard c.count == f.count else { return 0 }
            let diff = f.indices.filter { f[$0] != c[$0] }
            guard diff.count == 1 else { return 0 }
            let i = diff[0]
            let fv = CroatianFix.vowels.contains(f[i]), cv = CroatianFix.vowels.contains(c[i])
            if fv && cv { return i == f.count - 1 ? 20 : 5 }
            if !fv && !cv { return -30 }
            return 0
        }

        func fixWord(_ w: String, _ prev2: String?, _ prev: String?, _ next: String?) -> String {
            let h = hr.words, folded = hr.folded
            let l = w.lowercased()
            let f = Lexicon.fold(l)
            let known = h[l]
            if let known, known < CroatianFix.rare, f.count >= 3 {
                let here = ctx(prev2, prev, next, l)
                var best: String?, bestScore = -Double.infinity
                for c in edits(f) {
                    guard c.count == f.count, let (d, df) = folded[c] else { continue }
                    if df < known + CroatianFix.rareMargin { continue }
                    let there = ctx(prev2, prev, next, d)
                    if there <= here { continue }
                    if Double(df) + there > bestScore { best = d; bestScore = Double(df) + there }
                }
                if let best { return best }
            }
            if let known {
                guard let (d, df) = folded[f] else { return l }
                if d == l || df < known + CroatianFix.diacriticMargin { return l }
                let there = ctx(prev2, prev, next, d), here = ctx(prev2, prev, next, l)
                return (there > here || (there == here && known < CroatianFix.common)) ? d : l
            }
            if let hit = folded[f] { return hit.0 }
            if f.count < 4 || en.words[l] != nil { return l }
            var best: String?, bestScore = -Double.infinity
            var candidates = edits(f)
            let fa = Array(f)
            for (i, ch) in fa.enumerated() where ch == "i" {
                candidates.insert(String(fa[..<i]) + "ije" + String(fa[(i + 1)...]))
                candidates.insert(String(fa[..<i]) + "je" + String(fa[(i + 1)...]))
            }
            for c in candidates {
                guard let (d, df) = folded[c] else { continue }
                let same = c.count == f.count
                if df < (same ? CroatianFix.minFreqSameLength : CroatianFix.minFreq) { continue }
                let score = Double(df) + ctx(prev2, prev, next, d) - (same ? 0 : CroatianFix.lengthChangeCost) + shape(f, c)
                if score > bestScore { best = d; bestScore = score }
            }
            return best ?? l
        }

        /// "adres u restorana": an unknown word and a short next piece that together make a known word
        func merge(_ text: String) -> String {
            text.replacing(CroatianFix.mergeRe) { m, ns in
                let a = ns.substring(with: m.range(at: 1)), b = ns.substring(with: m.range(at: 2))
                let al = a.lowercased()
                if hr.words[al] == nil, en.words[al] == nil, hr.folded[Lexicon.fold((a + b).lowercased())] != nil { return a + b }
                return ns.substring(with: m.range)
            }
        }

        /// the best split of `letters` (folded) into one to three known words
        func segment(_ letters: String) -> [String]? {
            let ls = Array(letters), n = ls.count
            guard n > 0 else { return nil }
            var scores = [(Int, [String])?](repeating: nil, count: n + 1)
            scores[0] = (0, [])
            for i in 1...n {
                for j in max(0, i - 14)..<i {
                    guard let from = scores[j], from.1.count < 3 else { continue }
                    let piece = String(ls[j..<i])
                    if piece.count == 1, !CroatianFix.singleLetterWords.contains(piece) { continue }
                    guard let (word, f) = hr.folded[piece], f >= 150 else { continue }
                    let score = from.0 + f - 40
                    if scores[i] == nil || score > scores[i]!.0 { scores[i] = (score, from.1 + [word]) }
                }
            }
            return scores[n]?.1
        }

        func resegment(_ text: String) -> String {
            var toks = text.components(separatedBy: " ")
            func core(_ t: String) -> String { String(t.filter { $0.isLetter }).lowercased() }
            func plain(_ t: String) -> Bool {
                guard let first = t.first, first.isLetter else { return false }
                var s = Substring(t)
                while let last = s.last, !last.isLetter { s.removeLast() }
                return s.allSatisfy { $0.isLetter }
            }
            var i = 0
            while i < toks.count {
                let c = core(toks[i])
                if !c.isEmpty, plain(toks[i]), hr.words[c] == nil, hr.folded[Lexicon.fold(c)] == nil, en.words[c] == nil {
                    var changed = false
                    for (a, b) in [(i - 2, i), (i - 1, i), (i, i + 1), (i - 1, i + 1)] {
                        if a < 0 || b >= toks.count { continue }
                        let win = Array(toks[a...b])
                        if win.dropLast().contains(where: { !$0.allSatisfy { $0.isLetter } }) || !win.allSatisfy(plain) { continue }
                        if win.dropFirst().contains(where: { $0.first?.isUppercase ?? false }) { continue }
                        guard let seg = segment(Lexicon.fold(win.map(core).joined())), seg.count < win.count else { continue }
                        let trail = String(win.last!.drop(while: { $0.isLetter }))
                        var joined = seg.joined(separator: " ")
                        if win.first!.first!.isUppercase { joined = joined.capitalizedFirst }
                        toks.replaceSubrange(a...b, with: [joined + trail])
                        i = a + 1
                        changed = true
                        break
                    }
                    if changed { continue }
                }
                i += 1
            }
            return toks.joined(separator: " ")
        }

        func correct(_ text: String) -> String {
            let ns = text as NSString
            var toks = CroatianFix.wordRe.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
            let wordIdx = toks.indices.filter { toks[$0].first?.isLetter ?? false }
            var before = "", cursor = 0
            for (n, i) in wordIdx.enumerated() {
                while cursor < i { before += toks[cursor]; cursor += 1 }
                let t = toks[i]
                let tail = before.reversed().drop(while: { $0.isWhitespace }).first
                let sentenceStart = n == 0 || tail == "." || tail == "!" || tail == "?"
                if t.first!.isUppercase && !sentenceStart { continue }
                if t.count > 1, t.allSatisfy({ $0.isUppercase }) { continue }
                let prev = n > 0 ? toks[wordIdx[n - 1]].lowercased() : nil
                let prev2 = n > 1 ? toks[wordIdx[n - 2]].lowercased() : nil
                let next = n + 1 < wordIdx.count ? toks[wordIdx[n + 1]].lowercased() : nil
                let fixed = fixWord(t, prev2, prev, next)
                if fixed == t.lowercased() { continue }
                toks[i] = t.first!.isUppercase ? fixed.capitalizedFirst : fixed
            }
            return toks.joined()
        }
    }
}

// MARK: MaNameSpelling and MaSpokenTime

enum OwnNames {
    static let patterns: [(NSRegularExpression, String)] = [("marco", "marko"), ("bosco", "bosko")].map {
        (try! NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])\($0.0)(?![\\p{L}\\p{N}])"), $0.1)
    }
    static func sameCase(_ heard: String, _ to: String) -> String {
        if heard.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return to.uppercased() }
        if heard.first?.isUppercase ?? false { return to.capitalizedFirst }
        return to
    }
    static func apply(_ text: String) -> String {
        var out = text
        for (re, to) in patterns { out = out.replacing(re) { m, ns in sameCase(ns.substring(with: m.range), to) } }
        return out
    }
}

enum SpokenTime {
    static let re = try! NSRegularExpression(pattern: "(?i)\\b(at|by|until|till|from|before|after|around|about|since)\\s+(\\d{1,2})(\\d{2})\\b(?![:.,]\\d)")
    static func apply(_ text: String) -> String {
        text.replacing(re) { m, ns in
            let h = ns.substring(with: m.range(at: 2)), mm = ns.substring(with: m.range(at: 3))
            let hour = Int(h) ?? 0, minutes = Int(mm) ?? 0, digits = h + mm
            if (1...23).contains(hour), (0...55).contains(minutes), minutes % 5 == 0, !(digits.count == 4 && digits.hasPrefix("0")) {
                return ns.substring(with: m.range(at: 1)) + " \(hour):" + mm
            }
            return ns.substring(with: m.range)
        }
    }
}

// MARK: MaSpelling: the curated table (pairs.json, TTT's dictation_corrections.json)

struct SpellingPair {
    let id: String
    let from: [String]
    let to: String
    let unless: [String]
    let onlyIf: [String]
    let engine: Bool
}

struct SpellingTable {
    var updated = ""
    var keyterms: [String] = []
    var pairs: [SpellingPair] = []

    static func parse(_ data: Data) -> SpellingTable? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func strings(_ v: Any?) -> [String] { (v as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        var t = SpellingTable()
        t.updated = o["updated"] as? String ?? ""
        t.keyterms = strings(o["keyterms"])
        for case let p as [String: Any] in (o["pairs"] as? [Any] ?? []) {
            let from = strings(p["from"]), to = (p["to"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty, !to.isEmpty else { continue }
            let id = (p["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(from[0].lowercased().filter { $0.isLetter || $0.isNumber })
            t.pairs.append(SpellingPair(id: id, from: from, to: to, unless: strings(p["unless"]), onlyIf: strings(p["onlyIf"]), engine: p["engine"] as? Bool ?? true))
        }
        return t
    }

    static func caseLike(_ matched: String, _ to: String) -> String {
        let letters = matched.filter { $0.isLetter }
        if letters.count >= 2, letters.allSatisfy({ $0.isUppercase }), to.count >= 2, !to.contains(where: { $0.isUppercase }) { return to.uppercased() }
        if matched.first?.isUppercase ?? false, to.first?.isLowercase ?? false { return to.capitalizedFirst }
        return to
    }

    func apply(_ text: String) -> String {
        var out = text
        for p in pairs {
            if p.unless.contains(where: { out.range(of: $0, options: .caseInsensitive) != nil }) { continue }
            if !p.onlyIf.isEmpty, !p.onlyIf.contains(where: { out.range(of: $0, options: .caseInsensitive) != nil }) { continue }
            for f in p.from.sorted(by: { $0.count > $1.count }) {
                guard let re = wordPattern(f) else { continue }
                out = out.replacing(re) { m, ns in SpellingTable.caseLike(ns.substring(with: m.range), p.to) }
            }
        }
        return out
    }

    /// the names for the engines' keyword lists: the table's list, then the right form of every pair
    var terms: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in keyterms + pairs.map(\.to) {
            let s = t.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty, seen.insert(s.lowercased()).inserted { out.append(s) }
        }
        return Array(out.prefix(100))
    }
}

// MARK: MaCorrectionRules: his corrections, learned: what was written, what he made of it, the same fix done next time

enum CorrectionRules {
    static let activeAt = 2          // once is a coincidence
    static let maxWords = 3
    static let any = "*"

    struct Rule {
        var wrong: String
        var right: String
        var language: String
        var count: Int
        var enabled: Bool
        var mine: Bool
        var updated: String = ""
        var isActive: Bool { enabled && (mine || count >= CorrectionRules.activeAt) }
        var key: String { CorrectionRules.keyOf(wrong, language) }
    }
    static func keyOf(_ wrong: String, _ language: String) -> String { language + "|" + wrong.lowercased() }

    struct Token { let text: String; let start: Int; let end: Int; var isWord: Bool { text.contains { $0.isLetter || $0.isNumber } } }

    static func inWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "’" || c == "-" || c == "_" || c == "." || c == "@" }

    /// words (with the marks that live inside them, the dot of "auroville.community" too) and single punctuation marks
    static func tokenize(_ text: String) -> [Token] {
        let cs = Array(text)
        var out: [Token] = [], i = 0
        while i < cs.count {
            let ch = cs[i]
            if ch.isWhitespace { i += 1 }
            else if ch.isLetter || ch.isNumber {
                var j = i + 1
                while j < cs.count, inWord(cs[j]) { j += 1 }
                while j > i + 1, !(cs[j - 1].isLetter || cs[j - 1].isNumber) { j -= 1 }
                out.append(Token(text: String(cs[i..<j]), start: i, end: j))
                i = j
            } else { out.append(Token(text: String(ch), start: i, end: i + 1)); i += 1 }
        }
        return out
    }

    struct Swap { let wrong: String; let right: String }

    /// The corrections between `written` (a take as it went into the box) and `now` (the same stretch of the box, read
    /// later; it may run on past the take). Aligned word by word (longest common subsequence); a small swap inside
    /// otherwise unchanged text is a correction; more than half rewritten teaches nothing.
    static func diff(_ written: String, _ now: String) -> [Swap] {
        let a = tokenize(written), b = tokenize(now)
        let n = a.count, m = b.count
        guard n > 0, m > 0, n <= 400, m <= 600 else { return [] }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i].text == b[j].text ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        if dp[0][0] * 2 < n { return [] }
        var gaps: [([Token], [Token])] = []
        var i = 0, j = 0, gapA: [Token] = [], gapB: [Token] = [], lastA = -1
        while i < n, j < m {
            if a[i].text == b[j].text {
                if !gapA.isEmpty || !gapB.isEmpty { gaps.append((gapA, gapB)) }
                gapA = []; gapB = []
                lastA = i; i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] { gapA.append(a[i]); i += 1 }
            else { gapB.append(b[j]); j += 1 }
        }
        if lastA < 0 { return [] }
        var out: [Swap] = []
        let cs = Array(written)
        for (old, new) in gaps {
            if old.isEmpty || new.isEmpty || old.count > maxWords || new.count > maxWords { continue }
            if !old.allSatisfy(\.isWord) || !new.allSatisfy(\.isWord) { continue }
            let wrong = old.map(\.text).joined(separator: " "), right = new.map(\.text).joined(separator: " ")
            if wrong == right { continue }
            if wrong.lowercased() == right.lowercased() {
                // a change of case alone counts only when it gives a word a capital in the middle of a sentence ("emina" → "Emina")
                guard right.first?.isUppercase ?? false, !(wrong.first?.isUppercase ?? false) else { continue }
                let before = String(cs[..<old[0].start]).trimmingCharacters(in: .whitespaces)
                guard let last = before.last, !".!?\n:".contains(last) else { continue }
            }
            out.append(Swap(wrong: wrong, right: right))
        }
        return out
    }

    /// `rules` with `swap` made once more: the same fix again adds one; a different fix of the same words replaces the old
    /// one and starts again from one; a rule of his own is never overwritten by a learned one; a fix that undoes an active
    /// rule switches that rule off
    static func record(_ rules: [Rule], _ swap: Swap, _ language: String, now: String) -> (rules: [Rule], changed: [Rule]) {
        let key = keyOf(swap.wrong, language)
        let existing = rules.first { $0.key == key }
        var updated: Rule
        if let e = existing {
            if e.mine { return (rules, []) }
            updated = e
            if e.right == swap.right { updated.count += 1 } else { updated.right = swap.right; updated.count = 1 }
            updated.enabled = true
        } else {
            updated = Rule(wrong: swap.wrong, right: swap.right, language: language, count: 1, enabled: true, mine: false)
        }
        updated.updated = now
        let reverse = keyOf(swap.right, language)
        var changed = [updated]
        var out: [Rule] = []
        for var r in rules where r.key != key {
            if r.key == reverse, r.right.lowercased() == swap.wrong.lowercased(), r.enabled { r.enabled = false; r.updated = now; changed.append(r) }
            out.append(r)
        }
        return (out + [updated], changed)
    }

    /// whole words only, any case, the longest wrong words first; a match already followed by the rest of the right form
    /// is left ("DaVinci Resolve" does not become "DaVinci Resolve Resolve"); a match at a capital keeps the capital
    static func apply(_ text: String, _ rules: [Rule], _ language: String) -> String {
        let active = rules.filter { $0.isActive && ($0.language == language || $0.language == any) }.sorted { $0.wrong.count > $1.wrong.count }
        guard !active.isEmpty, !text.isEmpty else { return text }
        var out = text
        for rule in active {
            guard let re = wordPattern(rule.wrong) else { continue }
            out = out.replacing(re) { m, ns in
                let matched = ns.substring(with: m.range)
                let rest = ns.substring(from: m.range.location)
                if rest.lowercased().hasPrefix(rule.right.lowercased()) { return matched }
                if matched.first?.isUppercase ?? false, rule.right.first?.isLowercase ?? false, !rule.right.contains(".") { return rule.right.capitalizedFirst }
                return rule.right
            }
        }
        return out
    }

    static func glossary(_ rules: [Rule], _ language: String) -> [String] {
        var seen = Set<String>()
        return rules.filter { $0.isActive && ($0.language == language || $0.language == any) }.map(\.right).filter { seen.insert($0).inserted }
    }
}

// MARK: the order, as TTT's DictateController does it

enum Fix {
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "tttCorrections") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tttCorrections") }
    }

    /// before the Claude correction: Latin letters, then the Croatian fix (a Croatian take, text that was Cyrillic, or
    /// text that looks Croatian)
    static func before(_ raw: String, lang: String) -> String {
        guard on else { return raw }
        let latin = Cyrillic.toLatin(raw)
        if lang == "hr" || latin != raw || CroatianFix.looksCroatian(latin) { return CroatianFix.apply(latin) }
        return latin
    }

    /// after it: his names, spoken times, the spelling table, his learned corrections, then the open chat's name
    static func after(_ text: String, lang: String, chat: String? = nil) -> String {
        guard on else { return text }
        var body = SpokenTime.apply(OwnNames.apply(Cyrillic.toLatin(text)))
        body = Shared.table.apply(body)
        body = CorrectionRules.apply(body, Shared.rules, lang)
        if let chat, !chat.isEmpty { body = NameFix.apply(body, contact: chat, lang: lang) }
        return body
    }

    /// what the take was changed by, for the log (never the whole text twice)
    static func note(_ a: String, _ b: String, _ what: String) {
        if a != b {
            let swaps = CorrectionRules.diff(a, b).map { "\($0.wrong) → \($0.right)" }
            appendLog("corrections (\(what)): " + (swaps.isEmpty ? "changed" : swaps.joined(separator: ", ")))
        }
    }
}
