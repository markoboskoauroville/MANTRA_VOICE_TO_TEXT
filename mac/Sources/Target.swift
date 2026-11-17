// v28, THE TARGET TEXT BOX (Marko, 15.11.2026: "If there is a text box on the screen that I selected, sometimes it doesn't
// find it. When I press Style, it also doesn't find it ... If I click on a text box and then click on Style, of course it
// should write into the last text box I clicked on ... Pressing Copy is just the last resort if nothing else works.").
//
// One engine for BOTH the typing after a take and the STYLE button:
//   1. remembered: the last text box he clicked or focused in any app. The focus of the front app is watched (an
//      AXObserver on kAXFocusedUIElementChangedNotification, moved to each app as it comes to the front) and every left
//      click anywhere (a global monitor) looks at the element under the pointer and its parents for a box that takes
//      text. Clicks on Vox itself never reach the monitor, so pressing STYLE or the pill never replaces the box.
//   2. resolved at use: the focused box of the Mac if it is one (and not Vox), else the front app's own focused box
//      (Chrome and Electron answer the app, not always the system), else the remembered one while its app runs.
//   3. written (Writer): Accessibility first, read back; else the box's app and the box brought to the front (AXRaise,
//      AXFocused, a real click at its centre only when that fails and the click would land on the same box) and the text
//      pasted with ⌘V, his clipboard put back; else nothing, and the caller shows COPY.
// Chrome and Electron build their accessibility tree only when asked: AXManualAccessibility is set on every app that comes
// to the front (an unknown attribute is ignored by the others).
import AppKit
import ApplicationServices
import Carbon

final class TextTarget {
    struct Box {
        let element: AXUIElement
        let pid: pid_t
        let role: String
        let app: String
        let frame: CGRect?
        let at: Date
        let how: String              // "focus", "click", "now"
        var describe: String {
            let age = Int(Date().timeIntervalSince(at))
            return "\(app) · \(role.replacingOccurrences(of: "AX", with: "")) · by \(how) \(age < 60 ? "\(age) s" : "\(age / 60) min") ago"
        }
        var json: [String: Any] {
            ["app": app, "pid": Int(pid), "role": role, "how": how, "age_seconds": Int(Date().timeIntervalSince(at)),
             "frame": frame.map { ["x": Int($0.minX), "y": Int($0.minY), "w": Int($0.width), "h": Int($0.height)] } ?? [:]]
        }
    }

    static let shared = TextTarget()
    let own = getpid()
    let queue = DispatchQueue(label: "text-target")
    private let lock = NSLock()
    private var _last: Box?
    private var observer: AXObserver?
    private var observedPid: pid_t = 0
    private var mouseMonitor: Any?
    private var started = false

    var last: Box? { lock.lock(); defer { lock.unlock() }; return _last }
    private func remember(_ b: Box) {
        lock.lock()
        let changed = _last.map { !CFEqual($0.element, b.element) } ?? true
        _last = b
        lock.unlock()
        if changed { appendLog("target: \(b.app) \(b.role) (\(b.how))") }
    }

    // MARK: AX helpers (each call bounded by the element's messaging timeout)

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "?" }
    static func pid(_ el: AXUIElement) -> pid_t { var p: pid_t = 0; AXUIElementGetPid(el, &p); return p }
    static func element(_ v: AnyObject?) -> AXUIElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)              // AX coordinates: top-left of the main display is 0,0
    }
    static func settable(_ el: AXUIElement, _ name: String) -> Bool {
        var s = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el, name as CFString, &s) == .success && s.boolValue
    }

    static let stopRoles: Set<String> = ["AXWebArea", "AXWindow", "AXApplication", "AXScrollArea", "AXSheet", "AXDrawer", "AXBrowser"]
    static let notText: Set<String> = ["AXStaticText", "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton",
                                       "AXMenuButton", "AXImage", "AXLink", "AXMenuItem", "AXCell", "AXRow", "AXTable", "AXOutline", "AXList"]

    /// is this a box that takes text (a text field or area, a combo or search box, a web contenteditable)?
    static func isEditable(_ e: AXUIElement, role r: String) -> Bool {
        if let en = attr(e, kAXEnabledAttribute) as? Bool, !en { return false }
        if Typer.textRoles.contains(r) { return true }
        if notText.contains(r) || stopRoles.contains(r) { return false }
        // a group or a web element that edits text: it holds a string value and lets its caret be moved
        return attr(e, kAXValueAttribute) is String && settable(e, kAXSelectedTextRangeAttribute)
    }

    /// the box this element is, or is inside (a few parents up; Chrome names its editable ancestor itself)
    static func editable(_ el: AXUIElement) -> AXUIElement? {
        var cur: AXUIElement? = el
        for _ in 0..<7 {
            guard let e = cur else { return nil }
            AXUIElementSetMessagingTimeout(e, 0.4)
            let r = role(e)
            if r == "?" { return nil }
            if isEditable(e, role: r) { return e }
            if let anc = element(attr(e, "AXEditableAncestor")), isEditable(anc, role: role(anc)) { return anc }
            if stopRoles.contains(r) { return nil }
            cur = element(attr(e, kAXParentAttribute))
        }
        return nil
    }

    func box(_ e: AXUIElement, how: String) -> Box {
        let p = TextTarget.pid(e)
        let app = NSRunningApplication(processIdentifier: p)?.localizedName ?? "pid \(p)"
        return Box(element: e, pid: p, role: TextTarget.role(e), app: app, frame: TextTarget.frame(e), at: Date(), how: how)
    }

    /// Chrome and Electron (VS Code, Slack, WhatsApp) expose their text boxes only to an app that asks for them
    static func wakeAccessibility(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: watching

    func start() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.watch(app)
        }
        if let f = NSWorkspace.shared.frontmostApplication { watch(f) }
        // clicks in other apps only: a click on Vox (STYLE, the pill, Settings) never reaches this monitor
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            let m = NSEvent.mouseLocation
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            self?.clicked(at: CGPoint(x: m.x, y: top - m.y))
        }
        appendLog("target: watching the focus and the clicks")
    }

    private func watch(_ app: NSRunningApplication) {
        let p = app.processIdentifier
        guard p != own, p != observedPid else { return }
        if let o = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observer = nil; observedPid = p
        TextTarget.wakeAccessibility(p)
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<TextTarget>.fromOpaque(refcon).takeUnretainedValue()
            me.queue.async { me.consider(element, how: "focus") }
        }
        guard AXObserverCreate(p, cb, &obs) == .success, let o = obs else { return }
        let ax = AXUIElementCreateApplication(p)
        AXObserverAddNotification(o, ax, kAXFocusedUIElementChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        // the box already focused in the app that just came to the front
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            AXUIElementSetMessagingTimeout(ax, 0.4)
            if let f = TextTarget.element(TextTarget.attr(ax, kAXFocusedUIElementAttribute)) { self?.consider(f, how: "focus") }
        }
    }

    private func consider(_ el: AXUIElement, how: String) {
        guard TextTarget.pid(el) != own, let e = TextTarget.editable(el) else { return }
        remember(box(e, how: how))
    }

    private func clicked(at p: CGPoint) {
        queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let sys = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(sys, 0.4)
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &hit) == .success, let h = hit,
               TextTarget.pid(h) != self.own, let e = TextTarget.editable(h) {
                self.remember(self.box(e, how: "click")); return
            }
            // the element under the pointer told nothing (some web views): the box the click focused
            if let f = TextTarget.element(TextTarget.attr(sys, kAXFocusedUIElementAttribute)), TextTarget.pid(f) != self.own,
               let e = TextTarget.editable(f) { self.remember(self.box(e, how: "click")) }
        }
    }

    // MARK: at use

    /// the box to type into or to style now (called off the main thread)
    func resolve() -> Box? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.5)
        if let f = TextTarget.element(TextTarget.attr(sys, kAXFocusedUIElementAttribute)), TextTarget.pid(f) != own,
           let e = TextTarget.editable(f) {
            let b = box(e, how: "now"); remember(b); return b
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            TextTarget.wakeAccessibility(front.processIdentifier)
            let ax = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.5)
            if let f = TextTarget.element(TextTarget.attr(ax, kAXFocusedUIElementAttribute)), let e = TextTarget.editable(f) {
                let b = box(e, how: "now"); remember(b); return b
            }
        }
        if let b = last, NSRunningApplication(processIdentifier: b.pid) != nil, TextTarget.role(b.element) != "?" { return b }
        return nil
    }
}

// MARK: writing into a box (off the main thread)

enum Writer {
    /// a terminal's text box is its whole screen: STYLE never selects all of it and pastes over it (typing a take there is fine)
    static let terminals: Set<String> = ["com.googlecode.iterm2", "com.apple.Terminal", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
                                         "com.github.wez.wezterm", "io.alacritty", "com.mitchellh.ghostty"]
    static func isTerminal(_ el: AXUIElement) -> Bool {
        terminals.contains(NSRunningApplication(processIdentifier: TextTarget.pid(el))?.bundleIdentifier ?? "")
    }
    static func value(_ el: AXUIElement) -> String? { TextTarget.attr(el, kAXValueAttribute) as? String }

    /// the box's app in front and the box focused, so keys (⌘V, ⌘A, ⌘C) go there; false when that could not be made sure
    static func focus(_ el: AXUIElement) -> Bool {
        let p = TextTarget.pid(el)
        guard let app = NSRunningApplication(processIdentifier: p) else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != p {
            _ = app.activate(options: [])          // NSRunningApplication may be asked from any thread
            for _ in 0..<10 where NSWorkspace.shared.frontmostApplication?.processIdentifier != p { usleep(50_000) }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == p else { appendLog("target: \(app.localizedName ?? "") did not come to the front"); return false }
        if let w = TextTarget.element(TextTarget.attr(el, kAXWindowAttribute)) { AXUIElementPerformAction(w, kAXRaiseAction as CFString) }
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(80_000)
        if isFocused(el) { return true }
        // a real click at the box's centre, only when Settings allows it and the click lands on this very box
        guard Prefs.clickToFocus, let f = TextTarget.frame(el), f.width > 4, f.height > 4 else { return true }
        let c = CGPoint(x: f.midX, y: f.midY)
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.4)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(c.x), Float(c.y), &hit) == .success, let h = hit,
              let under = TextTarget.editable(h), CFEqual(under, el) else { return true }
        let back = CGEvent(source: nil)?.location
        let src = CGEventSource(stateID: .hidSystemState)
        for t in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        if let back { CGWarpMouseCursorPosition(back) }
        usleep(80_000)
        appendLog("target: clicked into \(TextTarget.role(el)) to focus it")
        return true
    }

    static func isFocused(_ el: AXUIElement) -> Bool {
        if let f = TextTarget.attr(el, kAXFocusedAttribute) as? Bool, f { return true }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.4)
        guard let f = TextTarget.element(TextTarget.attr(sys, kAXFocusedUIElementAttribute)) else { return false }
        if CFEqual(f, el) { return true }
        return TextTarget.editable(f).map { CFEqual($0, el) } ?? false
    }

    /// keys to the box's app only: false (and nothing sent) when another app is in front
    static func keys(_ el: AXUIElement, _ code: Int) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == TextTarget.pid(el) else { return false }
        pressKey(CGKeyCode(code), flags: .maskCommand)
        return true
    }

    /// his clipboard kept, `work` done with the clipboard holding `text` (nil: emptied), his clipboard put back
    static func withClipboard<T>(_ text: String?, _ work: () -> T) -> T {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        } ?? []
        pb.clearContents()
        if let text { pb.setString(text, forType: .string) }
        let out = work()
        pb.clearContents()
        let items = saved.map { d -> NSPasteboardItem in
            let i = NSPasteboardItem()
            for (t, v) in d { i.setData(v, forType: t) }
            return i
        }
        if !items.isEmpty { pb.writeObjects(items) }
        return out
    }

    /// the text pasted where the box's caret or selection is (selectAll: the whole box first); false when keys could not go there
    static func paste(_ text: String, into el: AXUIElement, selectAll: Bool) -> Bool {
        guard Prefs.pasteFallback, focus(el) else { return false }
        return withClipboard(text) { () -> Bool in
            if selectAll { guard keys(el, kVK_ANSI_A) else { return false }; usleep(80_000) }
            guard keys(el, kVK_ANSI_V) else { return false }
            usleep(600_000)                    // the app reads the clipboard on its own time (Electron later than AppKit)
            return true
        }
    }

    /// STYLE in a box that does not let its text be read: ⌘A ⌘C in it, his clipboard put back
    static func copyOut(_ el: AXUIElement) -> String? {
        guard Prefs.pasteFallback, !isTerminal(el), focus(el) else { return nil }
        let pb = NSPasteboard.general
        return withClipboard(nil) { () -> String? in
            let before = pb.changeCount
            guard keys(el, kVK_ANSI_A) else { return nil }
            usleep(80_000)
            guard keys(el, kVK_ANSI_C) else { return nil }
            for _ in 0..<8 where pb.changeCount == before { usleep(50_000) }
            return pb.changeCount == before ? nil : pb.string(forType: .string)
        }
    }

    // v43 (Marko, 17.11.2026: "every sentence is replacing the old sentence. I want to work in insert mode all the time. Wherever my
    // cursor is, sentence is inserted ... it deletes my own two minutes. This is unacceptable."): DICTATION ONLY INSERTS.
    // Firefox leaves a text it was given through Accessibility selected; the next take then replaced it. Now a take first
    // collapses any selection to its end, inserts, checks that everything that was in the box is still there, and moves the
    // caret behind the insertion. Where it cannot be sure, it undoes and falls back, never leaving a replaced text.
    static func caret(_ el: AXUIElement) -> CFRange? {
        guard let v = TextTarget.attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(v as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }
    /// any selection collapsed to its end (the text stays); true when the caret now has no selection
    @discardableResult static func collapse(_ el: AXUIElement) -> Bool {
        guard let r = caret(el) else { return false }
        if r.length == 0 { return true }
        var c = CFRange(location: r.location + r.length, length: 0)
        guard TextTarget.settable(el, kAXSelectedTextRangeAttribute), let v = AXValueCreate(.cfRange, &c),
              AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, v) == .success else { return false }
        usleep(40_000)
        return (caret(el)?.length ?? 1) == 0
    }
    /// everything that was in the box before is still in it, only text added at the caret (when both can be read)
    static func intact(before: String?, after: String?, at: CFRange?) -> Bool {
        guard let b = before, let a = after else { return true }
        if let at, at.location >= 0, at.location <= (b as NSString).length {
            let ns = b as NSString
            return a.hasPrefix(ns.substring(to: at.location)) && a.hasSuffix(ns.substring(from: at.location))
        }
        return (a as NSString).length >= (b as NSString).length
    }
    private static func undoReplace(_ el: AXUIElement, before: String?) {
        guard let before, focus(el) else { return }
        _ = keys(el, kVK_ANSI_Z); usleep(150_000)
        appendLog("typing: a replaced text was undone (box " + (value(el) == before ? "as before" : "NOT as before, check it") + ")")
    }

    /// a take's words at the caret of the box: INSERTED, never replacing anything (v43)
    static func insert(_ typed: String, into b: TextTarget.Box) -> Landing {
        let el = b.element
        var text = typed
        AXUIElementSetMessagingTimeout(el, 0.6)
        let before = value(el)
        let sure = collapse(el)
        let at = caret(el)
        if !sure && (at?.length ?? 0) > 0 { appendLog("typing: \(b.app) \(b.role) kept a selection I could not collapse") }
        // v44 (the master's check, 17.11.2026): two takes in a row must not glue ("minutes.Second"): a space first when the
        // character before the caret is not whitespace (nothing at the start of an empty box or after a newline)
        if !isTerminal(el), let before, let at, at.length == 0, at.location > 0, at.location <= (before as NSString).length,
           let first = text.unicodeScalars.first, !CharacterSet.whitespacesAndNewlines.contains(first),
           let prev = (before as NSString).substring(with: NSRange(location: at.location - 1, length: 1)).unicodeScalars.first,
           !CharacterSet.whitespacesAndNewlines.contains(prev), !"([{“‘\"'/-".unicodeScalars.contains(prev) {
            text = " " + text
        }
        let snippet = String(text.prefix(20))
        var replaced = false
        if TextTarget.settable(el, kAXSelectedTextAttribute),
           AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            for _ in 0..<4 {
                if let a = value(el), a != (before ?? ""), a.contains(snippet) {
                    if intact(before: before, after: a, at: at) {
                        collapse(el)             // the inserted text is left selected by some apps: the next take must not replace it
                        appendLog("typing: Accessibility into \(b.app) \(b.role)"); return .typed
                    }
                    replaced = true; break
                }
                usleep(60_000)
            }
        }
        if replaced { undoReplace(el, before: before) }
        guard paste(text, into: el, selectAll: false) else {
            appendLog("typing: \(b.app) \(b.role) took no writing and could not be brought to the front: COPY")
            return .nowhere
        }
        if let a = value(el), a == (before ?? ""), !a.contains(snippet) {
            appendLog("typing: pasted into \(b.app) \(b.role) but the box did not change: COPY"); return .nowhere
        }
        if !intact(before: before, after: value(el), at: at) {
            undoReplace(el, before: before)
            appendLog("typing: \(b.app) \(b.role) replaced text on insert: undone, COPY"); return .nowhere
        }
        collapse(el)
        appendLog("typing: pasted into \(b.app) \(b.role)")
        return .pasted
    }
}
