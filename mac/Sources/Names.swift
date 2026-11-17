// The name of the person he is writing to, spelled as the contact spells it (v50).
//
// Marko, 17.11.2026: "when you type any messages anywhere, check the spelling of the name. Usually, I mention the name of
// the person, especially in WhatsApp, and misspelling can be easily checked. What's the name of the person?"
// The open chat's name is read from the box itself (WhatsApp Web calls its box "Type a message to <name>"), else from the
// chat's header or the window title of a chat app. A word of the take that is a near miss of that name becomes the name;
// in Croatian the case ending he said stays on it. Conservative: ordinary words (anything in the dictionaries), short
// words, words without a capital and his other known names are never touched. The name also goes to the engines that
// take keywords.
import AppKit
import ApplicationServices

enum ChatName {
    static let patterns: [NSRegularExpression] = [
        "^Type a message to (.+)$", "^Type to (.+)$", "^Message to (.+)$", "^Write to (.+)$", "^Reply to (.+)$",
        "^Upišite poruku za (.+)$", "^Napišite poruku za (.+)$", "^Poruka za (.+)$",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    static let chatApps: Set<String> = ["net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.tdesktop.Telegram", "com.apple.MobileSMS",
                                        "org.whispersystems.signal-desktop", "com.facebook.archon", "com.viber.osx"]
    /// the last name read, for the engines' keywords of the next take (the take is heard before the box is looked at again)
    static var last: String?

    private static func strings(_ el: AXUIElement) -> [String] {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute].compactMap { TextTarget.attr(el, $0) as? String }
    }

    static func clean(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "\\(.*?\\)", with: " ", options: .regularExpression)
        t = String(t.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.whitespaces.contains($0) || $0 == "-" || $0 == "'" || $0 == "." })
        t = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        guard t.count >= 3, t.count <= 60, t.contains(where: { $0.isLetter }) else { return nil }
        return t
    }

    /// the name of the chat whose box this is, or nil (off the main thread; every call bounded)
    static func read(_ box: TextTarget.Box?) -> String? {
        guard let box else { return nil }
        let el = box.element
        AXUIElementSetMessagingTimeout(el, 0.4)
        for s in strings(el) {
            let ns = s as NSString
            for re in patterns {
                if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), let n = clean(ns.substring(with: m.range(at: 1))) { return n }
            }
        }
        let bundle = NSRunningApplication(processIdentifier: box.pid)?.bundleIdentifier ?? ""
        // a web chat: the header of the page's main part (WhatsApp Web: #main, its banner, the first words in it)
        if Writer.webApps.contains(bundle) || chatApps.contains(bundle) {
            var e: AXUIElement? = el
            for _ in 0..<30 {
                guard let cur = e else { break }
                if (TextTarget.attr(cur, "AXDOMIdentifier") as? String) == "main" {
                    if let banner = find(cur, depth: 3, budget: 60, where: { (TextTarget.attr($0, kAXSubroleAttribute) as? String) == "AXLandmarkBanner" }),
                       let text = find(banner, depth: 8, budget: 200, where: { TextTarget.role($0) == "AXStaticText" && !((TextTarget.attr($0, kAXValueAttribute) as? String) ?? "").isEmpty }),
                       let n = clean(TextTarget.attr(text, kAXValueAttribute) as? String ?? "") { return n }
                    break
                }
                e = TextTarget.element(TextTarget.attr(cur, kAXParentAttribute))
            }
        }
        // a chat app: its window is named after the chat
        if chatApps.contains(bundle), let w = TextTarget.element(TextTarget.attr(el, kAXWindowAttribute)),
           let title = TextTarget.attr(w, kAXTitleAttribute) as? String, let n = clean(title),
           n.lowercased() != box.app.lowercased(), !["whatsapp", "telegram", "messages", "signal", "viber", "messenger"].contains(n.lowercased()) { return n }
        return nil
    }

    private static func find(_ root: AXUIElement, depth: Int, budget: Int, where test: (AXUIElement) -> Bool) -> AXUIElement? {
        var left = budget
        func walk(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
            guard left > 0 else { return nil }
            left -= 1
            if test(e) { return e }
            guard d > 0, let kids = TextTarget.attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
            for k in kids { if let hit = walk(k, d - 1) { return hit } }
            return nil
        }
        return walk(root, depth)
    }
}

enum NameFix {
    static let wordRe = try! NSRegularExpression(pattern: "\\p{L}+")
    /// Croatian case endings he may say after a name (the name's own spelling stays in front of them)
    static let endings = ["", "a", "u", "e", "i", "om", "em", "ov", "ova", "ovu", "ove", "ovi", "ovim", "ovom", "ovog", "ovoj", "in", "ina", "inu", "ine"]

    /// how a name sounds, roughly: no accents, lj → l, nj → n, y → i, w → v, ph → f, double letters once
    static func norm(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "đ", with: "d").folding(options: .diacriticInsensitive, locale: nil)
        for (a, b) in [("lj", "l"), ("nj", "n"), ("ph", "f"), ("y", "i"), ("w", "v"), ("ck", "k")] { t = t.replacingOccurrences(of: a, with: b) }
        var out = ""
        for c in t where out.last != c { out.append(c) }
        return out
    }

    /// Damerau-Levenshtein (a swap of two neighbours counts once)
    static func distance(_ x: String, _ y: String) -> Int {
        let a = Array(x), b = Array(y)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    /// the parts of a contact's name that can be checked: words of four letters or more that begin with a capital
    static func parts(_ contact: String) -> [String] {
        contact.components(separatedBy: .whitespaces).filter { $0.count >= 4 && $0.allSatisfy { $0.isLetter } && ($0.first?.isUppercase ?? false) }.prefix(3).map { $0 }
    }

    static func ordinary(_ lower: String) -> Bool {
        if let en = Lexicon.get("en"), en.words[lower] != nil { return true }
        if let hr = Lexicon.get("hr"), hr.words[lower] != nil || hr.folded[Lexicon.fold(lower)] != nil { return true }
        return false
    }

    /// `text` with near misses of the contact's name spelled as the contact spells it
    static func apply(_ text: String, contact: String, lang: String) -> String {
        let tokens = parts(contact)
        guard !tokens.isEmpty else { return text }
        var known = Set((Adapters.ownNames() + Shared.table.terms).flatMap { $0.lowercased().components(separatedBy: .whitespaces) })
        for t in tokens { known.remove(t.lowercased()) }
        let croatian = lang == "hr" || (lang == "auto" && CroatianFix.looksCroatian(text))
        var fixes: [String] = []
        let out = text.replacing(wordRe) { m, ns in
            let w = ns.substring(with: m.range), lower = w.lowercased()
            guard w.count >= 4, w.first?.isUppercase ?? false, !tokens.contains(w), !known.contains(lower) else { return w }
            var best: (String, Int, Int)?        // replacement, distance, ending length
            for token in tokens {
                let nt = norm(token)
                let allowed = nt.count <= 4 ? 0 : nt.count <= 7 ? 1 : 2
                for ending in (croatian ? endings : [""]) {
                    guard lower.hasSuffix(ending), w.count - ending.count >= 3 else { continue }
                    let stem = String(w.dropLast(ending.count))
                    // a name that ends in a vowel loses it before an ending (Marta, Marte, Marti)
                    let base = !ending.isEmpty && "aeo".contains(token.last!) ? String(token.dropLast()) : token
                    let ns2 = norm(stem), nb = norm(base)
                    guard let f1 = ns2.first, let f2 = nb.first, f1 == f2 || Set([f1, f2]) == Set(["b", "v"]) else { continue }
                    let d = distance(ns2, nb)
                    guard d <= allowed else { continue }
                    let replacement = base + ending
                    if replacement == w { best = nil; return w }
                    if best == nil || d < best!.1 || (d == best!.1 && ending.count < best!.2) { best = (replacement, d, ending.count) }
                }
            }
            guard let b = best else { return w }
            // an ordinary word is left alone unless it SOUNDS exactly like the name and stands inside a sentence
            if ordinary(lower) {
                let before = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
                let inside = !before.isEmpty && !".!?\n:".contains(before.last!)
                if !(b.1 == 0 && inside) { return w }
            }
            fixes.append("\(w) → \(b.0)")
            return b.0
        }
        if !fixes.isEmpty { appendLog("name (the open chat is \(contact)): " + fixes.joined(separator: ", ")) }
        return out
    }
}
