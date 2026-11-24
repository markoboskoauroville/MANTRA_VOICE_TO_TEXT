// SystemAudio.swift (kit system-audio, MANTRA_MANIFEST kits/system-audio). Marko, 24.11.2026: "in voice to text, want to have
// under sound ability to choose input and output, basically affecting the whole system right from that setting" and "Multiply
// the settings everywhere. Input, output. I want to see which devices are active ... In the main user interface in front, I
// want to see microphone and speak[er]".
// One module everywhere: copy this file unchanged into the app's Swift sources (AppKit apps also use SystemAudioView below;
// SwiftUI apps also copy SystemAudioSwiftUI.swift). Change it only in the kit, then copy it again into every app that has it.
//
//   SystemAudio.current(input: true)            the Mac's default input now (name, uid, virtual or not)
//   SystemAudio.choose(device, input: false)    sets the macOS default output for EVERY app (as System Settings, Sound does)
//   SystemAudio.undo(input: false)              back to the device that was the default before the last change
//   SystemAudio.popMenu(input: true)            the picker as a menu at the mouse (real devices; virtual ones in a submenu,
//                                               asked again before use); "Back to …"; Sound Settings…
//   SystemAudioLive.shared                      ObservableObject: input, output, status line, level, "no sound arriving";
//                                               follows CoreAudio listeners, so a change made anywhere shows at once
//   SystemAudioLive.shared.feed(db:frames:)     an app that already listens (Talk Mode) feeds its own level
//   SystemAudioMeter.shared.start()/stop()      an app that does not listen (Vox) gets a level from the default input
//                                               (AVCaptureSession, only while its window is on screen)
//
// The guards: BlackHole, NDI, Zoom, Iriun, Loopback, aggregates (transport virtual or aggregate, or one of those names) are
// VIRTUAL: listed apart and confirmed before use. The previous device is kept in ~/.mantra/system_audio.json, so Undo works
// from any app that has this kit. The alert sound device ("system output") moves with the output only when it was the same
// device before (System Settings' "selected sound output device"); otherwise it stays where Marko put it.
import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreMedia

enum SystemAudio {
    struct Device: Equatable, Identifiable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let inputs: Int
        let outputs: Int
        let virtual: Bool
    }

    static let virtualWords = ["blackhole", "ndi audio", "zoomaudio", "zoom audio", "iriun", "loopback", "soundflower", "aggregate",
                               "multi-output", "teams audio", "krisp", "camo"]
    static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func addr(_ sel: AudioObjectPropertySelector,
                             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    static func uint32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = addr(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v
    }

    static func channels(_ id: AudioObjectID, input: Bool) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func isVirtual(_ id: AudioObjectID, name: String) -> Bool {
        let t = uint32(id, kAudioDevicePropertyTransportType)
        if t == kAudioDeviceTransportTypeVirtual || t == kAudioDeviceTransportTypeAggregate || t == kAudioDeviceTransportTypeAutoAggregate {
            return true
        }
        let n = name.lowercased()
        return virtualWords.contains { n.contains($0) }
    }

    /// every device CoreAudio has now (names trimmed: the ADAM calls itself "ADAM Audio D3V  ")
    static func devices() -> [Device] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let name = (string(id, kAudioObjectPropertyName) ?? "Device \(id)").trimmingCharacters(in: .whitespacesAndNewlines)
            let i = channels(id, input: true), o = channels(id, input: false)
            guard i > 0 || o > 0 else { return nil }
            return Device(id: id, uid: string(id, kAudioDevicePropertyDeviceUID) ?? "\(id)", name: name, inputs: i, outputs: o,
                          virtual: isVirtual(id, name: name))
        }
    }

    static func list(input: Bool) -> [Device] { devices().filter { input ? $0.inputs > 0 : $0.outputs > 0 } }

    static func defaultID(input: Bool) -> AudioDeviceID {
        uint32(system, input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func current(input: Bool) -> Device? {
        let id = defaultID(input: input)
        return devices().first { $0.id == id }
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> Bool {
        var a = addr(sel)
        var v = id
        return AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v) == noErr
    }

    // ---------------------------------------------------------------- the previous device (Undo), shared by every app
    static let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mantra/system_audio.json")
    static func readState() -> [String: String] {
        guard let d = try? Data(contentsOf: stateURL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return j
    }
    static func writeState(_ j: [String: String]) {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: stateURL, options: .atomic) }
    }
    static func previous(input: Bool) -> Device? {
        guard let uid = readState()[input ? "previous_input_uid" : "previous_output_uid"] else { return nil }
        return list(input: input).first { $0.uid == uid }
    }

    /// makes `d` the Mac's default input or output (every app that follows the system follows it). Returns the status line
    /// "Output: ADAM Audio D3V → MacBook Pro Speakers", or why it did not work.
    @discardableResult
    static func choose(_ d: Device, input: Bool, by app: String = ProcessInfo.processInfo.processName) -> String {
        let before = current(input: input)
        let word = input ? "Input" : "Output"
        if before?.id == d.id { return "\(word): \(d.name) (already)" }
        let systemWasSame = !input && uint32(system, kAudioHardwarePropertyDefaultSystemOutputDevice) == before?.id
        let ok = setDefault(d.id, input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        guard ok else { return "\(word): could not switch to \(d.name)" }
        if systemWasSame { setDefault(d.id, kAudioHardwarePropertyDefaultSystemOutputDevice) }
        var s = readState()
        if let b = before {
            s[input ? "previous_input_uid" : "previous_output_uid"] = b.uid
            s[input ? "previous_input_name" : "previous_output_name"] = b.name
        }
        let line = "\(word): \(before?.name ?? "none") → \(d.name)"
        s["last_change"] = line
        s["last_change_by"] = app
        s["last_change_time"] = ISO8601DateFormatter().string(from: Date())
        writeState(s)
        NSLog("[SystemAudio] %@ (by %@)", line, app)
        DispatchQueue.main.async { SystemAudioLive.shared.said(line) }
        return line
    }

    /// for an app that must record even when the default input is a loop (Vox's dictation): the default input when it is real,
    /// else the input that was the default before (when real), else the Mac's own microphone, else any real input
    static func realInputFallback() -> Device? {
        let all = list(input: true).filter { !$0.virtual }
        if let cur = current(input: true), !cur.virtual { return cur }
        if let p = previous(input: true), !p.virtual { return p }
        return all.first { uint32($0.id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn } ?? all.first
    }

    @discardableResult
    static func undo(input: Bool) -> String {
        guard let p = previous(input: input) else { return "\(input ? "Input" : "Output"): nothing to go back to" }
        return choose(p, input: input)
    }

    // ---------------------------------------------------------------- the picker (a menu: the same in every app)
    static func menu(input: Bool) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let head = NSMenuItem(title: input ? "MICROPHONE for the whole Mac" : "SPEAKER for the whole Mac", action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)
        let all = list(input: input)
        let cur = defaultID(input: input)
        let t = SystemAudioMenuTarget.shared
        for d in all where !d.virtual {
            let i = NSMenuItem(title: d.name, action: #selector(SystemAudioMenuTarget.pick(_:)), keyEquivalent: "")
            i.target = t; i.representedObject = (input ? "in:" : "out:") + d.uid; i.state = d.id == cur ? .on : .off
            m.addItem(i)
        }
        let virt = all.filter(\.virtual)
        if !virt.isEmpty {
            let v = NSMenuItem(title: "Virtual and loop devices (not a \(input ? "microphone" : "speaker"))", action: nil, keyEquivalent: "")
            let vm = NSMenu(); vm.autoenablesItems = false
            for d in virt {
                let i = NSMenuItem(title: d.name + "  ·  virtual", action: #selector(SystemAudioMenuTarget.pick(_:)), keyEquivalent: "")
                i.target = t; i.representedObject = (input ? "in:" : "out:") + d.uid; i.state = d.id == cur ? .on : .off
                vm.addItem(i)
            }
            v.submenu = vm
            if virt.contains(where: { $0.id == cur }) { v.state = .mixed }
            m.addItem(v)
        }
        m.addItem(.separator())
        if let p = previous(input: input), p.id != cur {
            let u = NSMenuItem(title: "Back to \(p.name)", action: #selector(SystemAudioMenuTarget.undo(_:)), keyEquivalent: "")
            u.target = t; u.representedObject = input ? "in" : "out"
            m.addItem(u)
        }
        let s = NSMenuItem(title: "Sound Settings…", action: #selector(SystemAudioMenuTarget.openSettings(_:)), keyEquivalent: "")
        s.target = t
        m.addItem(s)
        return m
    }

    /// the picker at the mouse pointer (a click on the MICROPHONE or SPEAKER line)
    static func popMenu(input: Bool) {
        menu(input: input).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class SystemAudioMenuTarget: NSObject {
    static let shared = SystemAudioMenuTarget()
    @objc func pick(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        let input = raw.hasPrefix("in:")
        let uid = String(raw.dropFirst(input ? 3 : 4))
        guard let d = SystemAudio.list(input: input).first(where: { $0.uid == uid }) else { return }
        if d.virtual {
            let a = NSAlert()
            a.messageText = "\(d.name) is a virtual loop device"
            a.informativeText = input
                ? "It is not a microphone: every app that listens would hear the loop instead of your voice. Use it anyway?"
                : "It is not a speaker: every app would play into the loop and you would hear nothing. Use it anyway?"
            a.addButton(withTitle: "Cancel")
            a.addButton(withTitle: "Use \(d.name)")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertSecondButtonReturn else { return }
        }
        SystemAudio.choose(d, input: input)
    }
    @objc func undo(_ item: NSMenuItem) { SystemAudio.undo(input: (item.representedObject as? String) == "in") }
    @objc func openSettings(_ item: NSMenuItem) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(u) }
    }
}

/// what every window shows: the default input and output now, the last change, the level of the input
final class SystemAudioLive: ObservableObject {
    static let shared = SystemAudioLive()
    @Published private(set) var input: SystemAudio.Device?
    @Published private(set) var output: SystemAudio.Device?
    @Published private(set) var status = ""
    @Published private(set) var canUndoInput = false
    @Published private(set) var canUndoOutput = false
    @Published private(set) var levelDB: Float = -160
    @Published private(set) var levelActive = false
    @Published private(set) var noSound = false
    private(set) var samples = 0
    private var lastSignal = Date.distantPast
    private var activeSince = Date.distantPast
    private var lastPush = Date.distantPast
    private var observers: [(Bool) -> Void] = []          // true = the input changed
    private var timer: Timer?

    private init() {
        refresh()
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
                    kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectAddPropertyListenerBlock(SystemAudio.system, &a, DispatchQueue.main) { [weak self] _, _ in self?.changed(sel) }
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// called (main thread) when the default input or output changes anywhere; `true` = the input changed
    func onChange(_ f: @escaping (Bool) -> Void) { observers.append(f) }

    func refresh() {
        let all = SystemAudio.devices()
        let i = SystemAudio.defaultID(input: true), o = SystemAudio.defaultID(input: false)
        let ni = all.first { $0.id == i }, no = all.first { $0.id == o }
        if ni != input { input = ni }
        if no != output { output = no }
        canUndoInput = SystemAudio.previous(input: true).map { $0.id != i } ?? false
        canUndoOutput = SystemAudio.previous(input: false).map { $0.id != o } ?? false
    }

    private func changed(_ sel: AudioObjectPropertySelector) {
        let oldIn = input?.id, oldOut = output?.id
        refresh()
        if input?.id != oldIn { activeSince = Date(); noSound = false }
        let inChanged = input?.id != oldIn || sel == kAudioHardwarePropertyDefaultInputDevice
        let outChanged = output?.id != oldOut || sel == kAudioHardwarePropertyDefaultOutputDevice
        if inChanged || outChanged {
            if status.isEmpty || !status.contains("→") || Date().timeIntervalSince(saidAt) > 5 {     // a change made elsewhere
                let s = SystemAudio.readState()
                if let line = s["last_change"], let t = s["last_change_time"], let d = ISO8601DateFormatter().date(from: t),
                   Date().timeIntervalSince(d) < 5 {
                    said(line)
                } else {
                    said(inChanged ? "Input is now \(input?.name ?? "none") (changed outside)" : "Output is now \(output?.name ?? "none") (changed outside)")
                }
            }
            for f in observers { f(inChanged) }
        }
    }

    private var saidAt = Date.distantPast
    func said(_ line: String) { status = line; saidAt = Date(); refresh() }

    /// the level of the default input, from the app that listens (main thread or not)
    func feed(db: Float, frames: Int) {
        let now = Date()
        DispatchQueue.main.async {
            self.samples += frames
            if !self.levelActive { self.levelActive = true; self.activeSince = now }
            if db.isFinite && db > -120 { self.lastSignal = now }
            if now.timeIntervalSince(self.lastPush) >= 0.08 { self.lastPush = now; self.levelDB = db.isFinite ? db : -160 }
        }
    }
    /// the app stopped listening (no level to show, no "no sound" warning)
    func inactive() { levelActive = false; levelDB = -160; noSound = false }

    private func tick() {
        let now = Date()
        let silent = levelActive && now.timeIntervalSince(activeSince) > 3 && now.timeIntervalSince(lastSignal) > 3
        if silent != noSound { noSound = silent }
    }

    /// the words next to MICROPHONE when something is wrong ("" when all is well)
    var inputWarning: String {
        guard let i = input else { return "no input device" }
        if i.virtual { return "virtual loop, not a microphone" }
        if noSound { return "no sound arriving" }
        return ""
    }
    var outputWarning: String {
        guard let o = output else { return "no output device" }
        return o.virtual ? "virtual loop, you hear nothing" : ""
    }
}

/// a level from the default input for an app that does not listen by itself (Vox's window): AVCaptureSession, only while started
final class SystemAudioMeter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = SystemAudioMeter()
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "system-audio.meter")
    private(set) var running = false

    override private init() {
        super.init()
        SystemAudioLive.shared.onChange { [weak self] inputChanged in if inputChanged { self?.restart() } }
    }

    func start() {
        guard !running else { return }
        running = true
        build()
    }

    func stop() {
        running = false
        let s = session
        session = nil
        queue.async { s?.stopRunning() }
        SystemAudioLive.shared.inactive()
    }

    func restart() {
        guard running else { return }
        let s = session
        session = nil
        queue.async { s?.stopRunning() }
        SystemAudioLive.shared.inactive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in if self?.running == true { self?.build() } }
    }

    private func build() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard let cur = SystemAudio.current(input: true), !cur.virtual else { return }       // a loop has no voice to show
        guard let dev = AVCaptureDevice(uniqueID: cur.uid) ?? AVCaptureDevice.default(for: .audio),
              let inp = try? AVCaptureDeviceInput(device: dev) else { return }
        let s = AVCaptureSession()
        guard s.canAddInput(inp) else { return }
        s.addInput(inp)
        let out = AVCaptureAudioDataOutput()
        out.setSampleBufferDelegate(self, queue: queue)
        guard s.canAddOutput(out) else { return }
        s.addOutput(out)
        session = s
        queue.async { s.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var db: Float = -160
        for ch in connection.audioChannels { db = max(db, ch.averagePowerLevel) }
        SystemAudioLive.shared.feed(db: db, frames: CMSampleBufferGetNumSamples(sampleBuffer))
    }
}

/// the two lines for an AppKit window: MICROPHONE <name> <level> <warning> and SPEAKER <name> <warning>, the status line and
/// UNDO. A click on a name opens its picker. Names wrap, never cut.
final class SystemAudioView: NSView {
    private let micTitle = NSTextField(labelWithString: "MICROPHONE")
    private let spkTitle = NSTextField(labelWithString: "SPEAKER")
    private let micName = NSTextField(wrappingLabelWithString: "")
    private let spkName = NSTextField(wrappingLabelWithString: "")
    private let micWarn = NSTextField(wrappingLabelWithString: "")
    private let spkWarn = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let undoIn = NSButton(title: "UNDO INPUT", target: nil, action: nil)
    private let undoOut = NSButton(title: "UNDO OUTPUT", target: nil, action: nil)
    private let meter = SystemAudioMeterBar()
    private var bag: [AnyCancellable] = []
    static let green = NSColor(srgbRed: 0.2, green: 0.82, blue: 0.48, alpha: 1)
    static let amber = NSColor(srgbRed: 0.94, green: 0.63, blue: 0.19, alpha: 1)

    init(fontSize: CGFloat = 13) {
        super.init(frame: .zero)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .bold)
        for t in [micTitle, spkTitle] { t.font = mono; t.textColor = .secondaryLabelColor; t.setContentHuggingPriority(.required, for: .horizontal)
            t.setContentCompressionResistancePriority(.required, for: .horizontal) }
        for (n, id) in [(micName, "system-input"), (spkName, "system-output")] {
            n.font = .systemFont(ofSize: fontSize, weight: .bold); n.textColor = .labelColor
            n.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            n.setAccessibilityIdentifier(id); n.setAccessibilityRole(.button)
        }
        micName.setAccessibilityLabel("Microphone of the whole Mac: click to choose")
        spkName.setAccessibilityLabel("Speaker of the whole Mac: click to choose")
        for w in [micWarn, spkWarn] { w.font = .systemFont(ofSize: fontSize - 1, weight: .semibold); w.textColor = SystemAudioView.amber }
        micWarn.setAccessibilityIdentifier("system-input-warning"); spkWarn.setAccessibilityIdentifier("system-output-warning")
        status.font = .systemFont(ofSize: fontSize - 2); status.textColor = .secondaryLabelColor
        status.setAccessibilityIdentifier("system-audio-status")
        for (b, sel, id) in [(undoIn, #selector(undoInput), "system-undo-input"), (undoOut, #selector(undoOutput), "system-undo-output")] {
            b.target = self; b.action = sel; b.controlSize = .small; b.bezelStyle = .rounded; b.setAccessibilityIdentifier(id)
        }
        meter.setAccessibilityIdentifier("system-input-level")
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.widthAnchor.constraint(equalToConstant: 120).isActive = true
        meter.heightAnchor.constraint(equalToConstant: 6).isActive = true
        func row(_ v: [NSView]) -> NSStackView {
            let r = NSStackView(views: v); r.orientation = .horizontal; r.alignment = .firstBaseline; r.spacing = 8
            r.detachesHiddenViews = true; return r
        }
        let micRow = row([micTitle, micName, meter, micWarn])
        micRow.alignment = .centerY
        let spkRow = row([spkTitle, spkName, spkWarn])
        spkRow.alignment = .centerY
        let statusRow = row([status, undoIn, undoOut])
        statusRow.alignment = .centerY
        let col = NSStackView(views: [micRow, spkRow, statusRow])
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 4; col.detachesHiddenViews = true
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: leadingAnchor), col.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                                     col.topAnchor.constraint(equalTo: topAnchor), col.bottomAnchor.constraint(equalTo: bottomAnchor)])
        // the titles end on one line
        spkTitle.widthAnchor.constraint(equalTo: micTitle.widthAnchor).isActive = true
        micName.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pickInput)))
        spkName.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pickOutput)))
        micTitle.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pickInput)))
        spkTitle.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pickOutput)))
        let live = SystemAudioLive.shared
        live.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.paint() } }.store(in: &bag)
        paint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() {
        for v in [micName, spkName, micTitle, spkTitle] { addCursorRect(convert(v.bounds, from: v), cursor: .pointingHand) }
    }

    func paint() {
        let l = SystemAudioLive.shared
        micName.stringValue = (l.input?.name ?? "none") + "  ▾"
        spkName.stringValue = (l.output?.name ?? "none") + "  ▾"
        micName.setAccessibilityValue(l.input?.name ?? "none"); spkName.setAccessibilityValue(l.output?.name ?? "none")
        micWarn.stringValue = l.inputWarning; micWarn.isHidden = l.inputWarning.isEmpty
        spkWarn.stringValue = l.outputWarning; spkWarn.isHidden = l.outputWarning.isEmpty
        micWarn.setAccessibilityValue(l.inputWarning)
        meter.db = l.levelActive ? l.levelDB : nil
        meter.setAccessibilityValue(l.levelActive ? String(format: "%.0f dB", l.levelDB) : "not measured")
        status.stringValue = l.status; status.isHidden = l.status.isEmpty
        status.setAccessibilityValue(l.status)
        undoIn.isHidden = !l.canUndoInput; undoOut.isHidden = !l.canUndoOutput
        if let p = SystemAudio.readState()["previous_input_name"] { undoIn.toolTip = "Input back to \(p)" }
        if let p = SystemAudio.readState()["previous_output_name"] { undoOut.toolTip = "Output back to \(p)" }
        window?.invalidateCursorRects(for: self)
    }

    @objc func pickInput() { SystemAudio.popMenu(input: true) }
    @objc func pickOutput() { SystemAudio.popMenu(input: false) }
    @objc func undoInput() { SystemAudio.undo(input: true) }
    @objc func undoOutput() { SystemAudio.undo(input: false) }
}

/// a hairline level: green, orange above -12 dB, red above -3 dB, floor -60 dB; empty when not measured
final class SystemAudioMeterBar: NSView {
    var db: Float? { didSet { needsDisplay = true } }
    override func draw(_ r: NSRect) {
        let b = bounds
        NSColor(white: 1, alpha: 0.15).setFill()
        NSBezierPath(roundedRect: b, xRadius: 2, yRadius: 2).fill()
        guard let d = db, d > -60 else { return }
        let f = CGFloat(max(0, min(1, (d + 60) / 60)))
        (d > -3 ? NSColor.systemRed : d > -12 ? NSColor.orange : SystemAudioView.green).setFill()
        NSBezierPath(roundedRect: NSRect(x: b.minX, y: b.minY, width: b.width * f, height: b.height), xRadius: 2, yRadius: 2).fill()
    }
}
