// The hands of Marko Transcribe: the microphone, the hotkey, and the typing into the app he is in.
import AppKit
import AVFoundation
import Carbon

// MARK: the microphone: 16 kHz mono, what Whisper wants, into a temporary file

// The recording device (request 9: "recording device menu"): the system's default input unless another one is chosen
// in ⚙, remembered by its unique ID. AVAudioRecorder cannot choose a device, so the take goes through a capture session.
enum InputDevice {
    static var chosenID: String? {
        get { UserDefaults.standard.string(forKey: "inputDevice") }
        set { UserDefaults.standard.set(newValue, forKey: "inputDevice") }
    }
    static func all() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }
    static func current() -> AVCaptureDevice? {
        if let id = chosenID, let d = all().first(where: { $0.uniqueID == id }) { return d }
        return AVCaptureDevice.default(for: .audio)
    }
}

// v26 (Marko, 31.10.2026: "if I am doing transcription at the moment, you need to wait with your talking. You cannot talk
// while I am talking"; "Only when it's actually recording, you cannot talk. When it's idle, you can talk"): while a take
// is recording (not paused, not idle) this file exists with the app's pid; the voice engine
// (MANTRA_VOICE voiced.py) holds every reading while it is there. Voice activation's own listening never makes it.
enum TakeMark {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Voice to Text (Mantra)/take-open")
    static func set(_ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: url, atomically: true, encoding: .utf8)
        } else { try? FileManager.default.removeItem(at: url) }
    }
}

final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var finished: ((URL?) -> Void)?
    // Request 12 ("recorded to best quality aiff or flac and then using ffmpeg re-encoded to whisper format"): lossless
    // AIFF at the device's own rate, mono, 24-bit; Audio (below) makes the small 16 kHz FLAC that is sent.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-to-text-mantra-take.aiff")
    var started: Date?                     // when the running stretch began (nil while paused)
    var accumulated: TimeInterval = 0      // the stretches before a pause (TTT Mini: the clock stops while paused)
    var paused = false
    var deviceName = ""
    let bands = MicBands()                 // v12: the same microphone in eleven bands, for the pill's wave (Pill.swift)

    func start() -> Bool {
        try? FileManager.default.removeItem(at: file)
        guard let dev = InputDevice.current(), let input = try? AVCaptureDeviceInput(device: dev) else { return false }
        let s = AVCaptureSession(), out = AVCaptureAudioFileOutput()
        guard s.canAddInput(input), s.canAddOutput(out) else { return false }
        s.addInput(input); s.addOutput(out)
        let data = AVCaptureAudioDataOutput()
        data.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
                              AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true]
        data.setSampleBufferDelegate(bands, queue: bands.queue)
        bands.reset()
        if s.canAddOutput(data) { s.addOutput(data) }
        // the device's own rate (no rate given), mono, 24-bit, lossless
        out.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24,
                             AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsNonInterleaved: false]
        s.startRunning()
        out.startRecording(to: file, outputFileType: .aiff, recordingDelegate: self)
        session = s; output = out; deviceName = dev.localizedName
        started = Date(); accumulated = 0; paused = false
        TakeMark.set(true)
        return true
    }

    func pause() {
        guard let o = output, !paused else { return }
        o.pauseRecording()
        accumulated += Date().timeIntervalSince(started ?? Date())
        started = nil; paused = true
        TakeMark.set(false)          // paused is not talking: the voice may speak (Marko, 31.10.2026)
    }

    func resume() {
        guard let o = output, paused else { return }
        o.resumeRecording()
        started = Date(); paused = false
        TakeMark.set(true)
    }

    // The file is complete only when the output says so: `done` gets it then (on the main thread).
    func stop(_ done: @escaping (URL?) -> Void) {
        guard let o = output else { done(nil); return }
        finished = done
        o.stopRecording()
        started = nil; paused = false
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        session?.stopRunning()
        session = nil; self.output = nil
        TakeMark.set(false)
        let done = finished
        finished = nil
        DispatchQueue.main.async { done?(FileManager.default.fileExists(atPath: url.path) ? url : nil) }
    }

    var recording: Bool { output != nil }
    var elapsed: TimeInterval { accumulated + (started.map { Date().timeIntervalSince($0) } ?? 0) }
    var megabytes: Double {
        Double((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0) / 1_000_000
    }
    // The loudest moment of the last instant, in dB (0 is the top); nil while paused.
    var peakDB: Float? {
        guard let o = output, !paused, let ch = o.connections.first?.audioChannels.first else { return nil }
        return ch.peakHoldLevel
    }
}

// MARK: the hotkey (a Carbon hot key: it works without Accessibility and the key does not reach the front app)

final class HotKey {
    static var handlers: [UInt32: () -> Void] = [:]
    private var ref: EventHotKeyRef?
    private static var installed = false
    let id: UInt32

    // The function keys by name, for Settings. F1 by default (Marko, 18.10.2026: "f1 is default key for transcribing").
    static let keys: [(String, UInt32)] = [("F1", UInt32(kVK_F1)), ("F2", UInt32(kVK_F2)), ("F3", UInt32(kVK_F3)), ("F4", UInt32(kVK_F4)),
                                           ("F5", UInt32(kVK_F5)), ("F6", UInt32(kVK_F6)), ("F7", UInt32(kVK_F7)),
                                           ("F8", UInt32(kVK_F8)), ("F9", UInt32(kVK_F9)), ("F10", UInt32(kVK_F10)),
                                           ("F11", UInt32(kVK_F11)), ("F12", UInt32(kVK_F12)), ("F13", UInt32(kVK_F13)),
                                           ("F14", UInt32(kVK_F14)), ("F15", UInt32(kVK_F15))]

    static var chosen: String {
        get { UserDefaults.standard.string(forKey: "hotkey") ?? "F1" }
        set { UserDefaults.standard.set(newValue, forKey: "hotkey") }
    }

    init?(code: UInt32, id: UInt32, _ handler: @escaping () -> Void) {
        self.id = id
        if !HotKey.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.installed = true
        }
        HotKey.handlers[id] = handler
        let hkID = EventHotKeyID(signature: OSType(0x4D54_5243), id: id)       // 'MTRC'
        guard RegisterEventHotKey(code, 0, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }
}

// MARK: a key pressed for another app (⌘V when a field takes no typing)

func pressKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

// MARK: typing into the app he is in. Through the accessibility API first (MANTRA_MANIFEST modules/
// mac-through-accessibility.md: "Anything we do in Mac, we do through the accessibility feature"): the text replaces the
// selection of the focused field. Fields that do not take it (some web pages, Electron apps) get it pasted, and the
// clipboard is put back as it was.

// DID IT LAND (request 11, "detect same as Speechify if transcription didn't land and offer copy transcription to
// clipboard as quick fix"): typed (accessibility, read back), pasted (⌘V, read back where the field can be read), or
// nowhere (no text field had the focus, or the field did not change): then the stripe offers Copy.
enum Landing { case typed, pasted, nowhere }

enum Typer {
    /// v19: the field the last take landed in, so STYLE can find "the words typed last" there
    static var lastField: AXUIElement?
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func value(_ el: AXUIElement) -> String? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success ? v as? String : nil
    }

    static func insert(_ text: String, _ done: @escaping (Landing) -> Void) {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { done(.nowhere); return }
        let field = el as! AXUIElement
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &settable)
        let before = value(field)
        let snippet = String(text.prefix(20))
        if settable.boolValue, AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success,
           let after = value(field), after != (before ?? ""), after.contains(snippet) {
            lastField = field
            done(.typed); return
        }
        // a focus that is no text field at all (a button, the desktop, a list): nothing would land, so nothing is pasted
        if !textRoles.contains(role) && !settable.boolValue && role != "AXWebArea" { done(.nowhere); return }
        paste(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let after = value(field), after == (before ?? ""), !after.contains(snippet) { done(.nowhere) }
            else { lastField = field; done(.pasted) }                       // read back, or a field that cannot be read (believed)
        }
    }

    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        } ?? []
        pb.clearContents()
        pb.setString(text, forType: .string)
        pressKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {          // after the paste, his clipboard as it was
            pb.clearContents()
            let items = saved.map { d -> NSPasteboardItem in
                let i = NSPasteboardItem()
                for (t, v) in d { i.setData(v, forType: t) }
                return i
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }
}

// MARK: v19, STYLE IN ANY TEXT BOX (Marko, 31.10.2026: "this styling works always. I can click anywhere where there is a
// text box in the screen and it will correct styling"). Everything by Accessibility, no keystrokes (MANTRA_MANIFEST
// mac-through-accessibility.md; System Events keystrokes land in iTerm2):
//   1. the focused element of the whole Mac (the blob is a non-activating panel, so a click on it leaves that focus alone)
//   2. what to restyle: the selection if there is one; else the words this app typed last, when they are in this field;
//      else the whole text of the field
//   3. written back: that range selected and AXSelectedText set, read back; else AXValue with the range replaced, read
//      back; else nothing is written and the caller puts the styled text on the clipboard (⌘V by hand)
enum Restyle {
    struct Target {
        let field: AXUIElement
        let range: CFRange?          // nil: the selection as it stands (its range could not be read)
        let text: String
        let what: String             // "the selection", "the words typed last", "the whole box"
    }

    enum Found { case target(Target), noFocus, ownWindow, empty(String), unreadable(String) }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "?" }

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 2)
        guard let el = attr(system, kAXFocusedUIElementAttribute) else { return nil }
        return (el as! AXUIElement)
    }

    static func selectedRange(_ el: AXUIElement) -> CFRange? {
        guard let v = attr(el, kAXSelectedTextRangeAttribute) else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }

    /// the focused field of the whole Mac and what in it is to be restyled
    static func find(lastTyped: String) -> Found {
        guard let field = focusedElement() else { return .noFocus }
        var pid: pid_t = 0
        AXUIElementGetPid(field, &pid)
        if pid == getpid() { return .ownWindow }       // our own windows: AX to ourselves on the main thread would hang
        return find(in: field, lastTyped: lastTyped)
    }

    static func find(in field: AXUIElement, lastTyped: String) -> Found {
        AXUIElementSetMessagingTimeout(field, 2)
        let value = Typer.value(field)
        let blank = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let sel = attr(field, kAXSelectedTextAttribute) as? String, !blank(sel) {
            var r = selectedRange(field)
            if r == nil || r!.length == 0, let v = value {     // a field that names the text but not its range
                let n = (v as NSString).range(of: sel, options: .backwards)
                r = n.location == NSNotFound ? nil : CFRange(location: n.location, length: n.length)
            }
            return .target(Target(field: field, range: r, text: sel, what: "the selection"))
        }
        guard let v = value else { return .unreadable(role(field)) }
        if blank(v) { return .empty(role(field)) }
        if !blank(lastTyped), let last = Typer.lastField, CFEqual(last, field) {
            let n = (v as NSString).range(of: lastTyped, options: .backwards)
            if n.location != NSNotFound {
                return .target(Target(field: field, range: CFRange(location: n.location, length: n.length), text: lastTyped, what: "the words typed last"))
            }
        }
        return .target(Target(field: field, range: CFRange(location: 0, length: (v as NSString).length), text: v, what: "the whole box"))
    }

    /// replaced: read back in the field; believed: the field took it but cannot be read back; failed: nothing written
    enum Written { case replaced, believed, failed }

    /// the styled text put in place of the target
    static func write(_ new: String, to t: Target) -> Written {
        let field = t.field
        let before = Typer.value(field)
        let probe = String(new.prefix(24))
        // 1. the range selected, the selection replaced (what a person typing over a selection does)
        var selected = t.range == nil
        if var cf = t.range, let rv = AXValueCreate(.cfRange, &cf) {
            selected = AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, rv) == .success
        }
        if selected, AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, new as CFTypeRef) == .success {
            usleep(100_000)
            let after = Typer.value(field)
            if let after, after != before, after.contains(probe) { return .replaced }
            if before == nil && after == nil { return .believed }
        }
        // 2. the whole value with the range replaced (fields that take no AXSelectedText)
        if let b = before, let r = t.range, r.location + r.length <= (b as NSString).length {
            let whole = (b as NSString).replacingCharacters(in: NSRange(location: r.location, length: r.length), with: new)
            if AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, whole as CFTypeRef) == .success {
                usleep(100_000)
                if Typer.value(field) == whole { return .replaced }
            }
        }
        return .failed
    }
}

// MARK: the start and stop sounds (Marko, 18.10.2026: a sound when it starts and when it stops). macOS's own Tink and
// Pop; nothing is taken from Speechify any more (30.10.2026: "No Speechify at all").
enum Chime {
    private static var playing: NSSound?               // held, or it stops when it is released

    /// v25 (Marko, 31.10.2026: "compare your sound levels with the sound levels from Speechify blob. Everything must match
    /// ... Even the sound must match"): Speechify's own start_dictation.wav / end_dictation.wav, read from the installed
    /// Speechify app (never copied into this repository); Tink and Pop only when Speechify is not installed. At 100 % the
    /// sound and its level are Speechify's own (both files peak at -21 dBFS, played at volume 1).
    static func sound(start: Bool) -> NSSound? { NSSound(named: start ? "Tink" : "Pop") }

    static func play(start: Bool, position: Float? = nil) {
        let s = sound(start: start)
        s?.volume = gain(position ?? (start ? Prefs.startVolume : Prefs.stopVolume))      // v15: the levels in ⚙
        playing = s
        s?.stop(); s?.play()
    }

    /// v24 (Marko, 31.10.2026: "See if volume slider is actually linearly raising or lowering the sound"): the slider is
    /// a position, the sound follows it in decibels. NSSound's volume is amplitude, so the slider used to move only 6 dB
    /// over its whole top half (measured through BlackHole: Tink -33.6 dBFS at 50 %, -27.6 at 100 %) and everything
    /// happened in its bottom fifth. Now 100 % is the sound as it is, every 10 % is 4 dB, 0 % is silent.
    static func gain(_ position: Float) -> Float {
        let p = max(0, min(1, position))
        return p <= 0 ? 0 : powf(10, (p - 1) * 40 / 20)
    }
}

