// THE TALK BLOB (v12, 30.10.2026). Marko: "change your user interface so it looks the same as ... Talk Blob, basically
// emulating Speechify. My Speechify should be almost identical ... there is a setting button, so everything is there. I
// want it to look like and act like Speechify." Asked which blob, he answered "yes" to the pill of Claude to Marko voice
// (CLAUDE_TO_MARKO_VOICE app/Blob.swift, itself Speechify's dictation blob copied from his screenshot).
//
// The pill: a grey round ✕ at the left (throw the take away, as Esc), eleven white bars that are his voice (the
// microphone in eleven bands, low at the left, high at the right, the meter of the Claude blob), HR / EN, ⏸, ⚙ (every
// choice: who hears, who cleans, the history, the settings), and the blue round button at the right that sends the take
// (as F1). A small line above it says who hears and cleans, the clock while listening, and what happened afterwards.
import AppKit
import AVFoundation
import Accelerate

let PILL_W: CGFloat = 430, PILL_H: CGFloat = 40, LINE_H: CGFloat = 20, PANEL_W: CGFloat = 460
let BLUE = NSColor(calibratedRed: 0x3D / 255, green: 0x7B / 255, blue: 0xF7 / 255, alpha: 1)

// THE CRASH OF 30.10.2026 (22:33, caught in stderr): "NSInvalidArgumentException ... attempt to insert nil object" in
// BlobButton.draw → "EN".size(withAttributes:). The pill is drawn 24 times a second while the bars move, and every draw
// made a new system font and laid the word out again; once in a long while CoreText got an empty font and the app died.
// Now the button is drawn ONCE into a bitmap when its word, symbol or colour really changes, from one font made at
// launch, and every later draw only paints that bitmap: no text layout at 24 fps. Setting the same value again (the tick
// sets the language every frame) changes nothing and asks for no drawing.
final class BlobButton: NSView {
    static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    var symbol: String { didSet { if symbol != oldValue { cache = nil } } }
    var circle: NSColor? { didSet { if circle != oldValue { cache = nil } } }
    var tint: NSColor { didSet { if tint != oldValue { cache = nil } } }
    var text: String? { didSet { if text != oldValue { cache = nil } } }      // a word instead of a symbol (HR / EN)
    private var cache: NSImage? { didSet { if cache == nil { needsDisplay = true } } }
    var action: () -> Void
    /// v17: a button that cannot act now stays in its place, grey, and a press does nothing
    var live = true { didSet { if live != oldValue { cache = nil } } }
    /// v17: the word drawn in square brackets ([AUTO]); the Accessibility label stays the word
    var bracketed = false { didSet { if bracketed != oldValue { cache = nil } } }
    static let dim = NSColor(white: 0.42, alpha: 1)
    static let lit = NSColor(white: 0.95, alpha: 1)       // v29: the white of a STYLE / COPY that has something to do
    init(_ symbol: String, _ frame: NSRect, circle: NSColor?, tint: NSColor, tip: String, _ action: @escaping () -> Void) {
        self.symbol = symbol; self.circle = circle; self.tint = tint; self.action = action; super.init(frame: frame)
        toolTip = tip
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    // v15 (MANTRA_MANIFEST swift-apps.md, "Accessibility built in"): every button of the blob is an Accessibility button
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { text ?? toolTip }
    override func accessibilityPerformPress() -> Bool { guard live else { return false }; action(); return true }
    override func isAccessibilityEnabled() -> Bool { live }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if live, bounds.contains(convert(e.locationInWindow, from: nil)) { action() } }
    override func viewDidChangeBackingProperties() { cache = nil }
    override func draw(_ r: NSRect) {
        if cache == nil { cache = render() }
        cache?.draw(in: bounds)
    }

    // the button once, into a bitmap at the screen's scale
    private func render() -> NSImage? {
        let scale = window?.backingScaleFactor ?? 2
        guard bounds.width > 0, bounds.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // v16 (Marko, 31.10.2026: "After last update the old buttons shrink. They are very tiny"): the size in points
        // BEFORE the context is made. Made after (v14, v15), the context drew 1:1 into the 2× bitmap: every button at half
        // its size, in the bottom-left corner of its place.
        rep.size = bounds.size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }
        let d = min(bounds.width, bounds.height) - 6
        let c = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        if let circle { circle.setFill(); NSBezierPath(ovalIn: c).fill() }
        if let word = text {
            let text = bracketed ? "[" + word + "]" : word
            let a: [NSAttributedString.Key: Any] = [.font: BlobButton.font, .foregroundColor: live ? tint : BlobButton.dim]
            let s = (text as NSString).size(withAttributes: a)
            (text as NSString).draw(at: NSPoint(x: c.midX - s.width / 2, y: c.midY - s.height / 2), withAttributes: a)
        } else {
            let cfg = NSImage.SymbolConfiguration(pointSize: circle == nil ? 14 : 12, weight: .bold)
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let at = NSRect(x: c.midX - img.size.width / 2, y: c.midY - img.size.height / 2, width: img.size.width, height: img.size.height)
                let tint = live ? self.tint : BlobButton.dim      // the symbol tinted alone, then onto the circle
                let t = NSImage(size: img.size, flipped: false) { rect in img.draw(in: rect); tint.set(); rect.fill(using: .sourceAtop); return true }
                t.draw(in: at)
            }
        }
        ctx.flushGraphics()
        let img = NSImage(size: bounds.size); img.addRepresentation(rep)
        return img
    }
}

// HIS VOICE IN ELEVEN BANDS: the microphone's samples (an audio data output beside the file output, Recorder), 2048 at a
// time through an FFT, the power summed in eleven bands spaced evenly in octaves from 80 Hz to 11 kHz, in dB where a
// full-scale sine is 0. Read by the wave 24 times a second.
final class MicBands: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let N = 2048, LOG2N = vDSP_Length(11)
    static let edges: [Double] = (0...11).map { 80 * pow(11000.0 / 80, Double($0) / 11) }
    let queue = DispatchQueue(label: "mic-bands")
    private let setup = vDSP_create_fftsetup(LOG2N, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: N)
    private var ring = [Float](repeating: 0, count: N)
    private var filled = 0
    private let lock = NSLock()
    private var latest: [Double]?

    override init() {
        super.init()
        vDSP_hann_window(&window, vDSP_Length(MicBands.N), Int32(vDSP_HANN_DENORM))
    }

    var db: [Double]? { lock.lock(); defer { lock.unlock() }; return latest }
    func reset() { lock.lock(); latest = nil; lock.unlock(); queue.async { self.filled = 0 } }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let fd = CMSampleBufferGetFormatDescription(sb), let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else { return }
        var list = AudioBufferList(), block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: nil, bufferListOut: &list,
              bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
              flags: 0, blockBufferOut: &block) == noErr, let data = list.mBuffers.mData else { return }
        let ch = Int(max(asbd.mChannelsPerFrame, 1)), interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let n = Int(list.mBuffers.mDataByteSize) / 4 / (interleaved ? ch : 1)
        let p = data.assumingMemoryBound(to: Float.self)
        for i in 0..<n { ring.append(p[interleaved ? i * ch : i]) }
        if ring.count > MicBands.N { ring.removeFirst(ring.count - MicBands.N) }      // once a buffer, not once a sample
        filled = min(filled + n, MicBands.N)
        latestFrom(rate: asbd.mSampleRate)
    }

    // the bands of the last 2048 samples (also used by --bands on a file)
    func latestFrom(rate: Double) {
        guard filled >= MicBands.N / 2 else { return }
        let r = MicBands.analyse(ring, window: window, setup: setup, rate: rate)
        lock.lock(); latest = r; lock.unlock()
    }

    static func analyse(_ samples: [Float], window: [Float], setup: FFTSetup, rate: Double) -> [Double] {
        let N = MicBands.N
        var x = [Float](repeating: 0, count: N)
        vDSP_vmul(samples, 1, window, 1, &x, 1, vDSP_Length(N))
        var re = [Float](repeating: 0, count: N / 2), im = [Float](repeating: 0, count: N / 2)
        var power = [Float](repeating: 0, count: N / 2)
        re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            x.withUnsafeBufferPointer { xp in
                xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(N / 2)) }
            }
            vDSP_fft_zrip(setup, &split, 1, MicBands.LOG2N, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(N / 2))
        } }
        // zrip is twice the usual transform; the Hann window (normalised to a peak of 1) passes half the amplitude
        // and spreads a sine's power over 1.5 bins' worth: a full-scale sine sums to (N/2)^2 * 1.5 here, i.e. 0 dB
        let full = Double(N / 2) * Double(N / 2) * 1.5
        let hz = rate / Double(N)
        return (0..<11).map { b in
            let lo = max(1, Int(ceil(edges[b] / hz))), hi = min(N / 2 - 1, Int(floor(edges[b + 1] / hz)))
            var sum = 0.0
            if lo <= hi { for k in lo...hi { sum += Double(power[k]) } }
            return sum > 0 ? 10 * log10(sum / full) : -140
        }
    }

    // --bands <audio>: the bands of a recording, a line every 0.1 s, to see the meter's numbers without a microphone
    static func printBands(_ url: URL) {
        guard let f = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: f.fileFormat.sampleRate, channels: 1)!,
                                         frameCapacity: AVAudioFrameCount(f.length)) else { print("cannot read"); return }
        let conv = AVAudioConverter(from: f.processingFormat, to: buf.format)
        let src = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try? f.read(into: src)
        var err: NSError?
        var given = false
        conv?.convert(to: buf, error: &err) { _, st in if given { st.pointee = .noDataNow; return nil }; given = true; st.pointee = .haveData; return src }
        let m = MicBands(), rate = f.fileFormat.sampleRate, step = Int(rate / 10)
        let s = UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength))
        var i = 0
        while i + N <= s.count {
            let r = analyse(Array(s[i..<(i + N)]), window: m.window, setup: m.setup, rate: rate)
            print(String(format: "%5.1f s ", Double(i) / rate) + r.map { String(format: "%5.0f", $0) }.joined())
            i += step
        }
    }
}

// The wave: short white bars, round-ended, each one band of his voice, rising from one line; dots while silent.
// The ballistics of the Claude blob (SPECTRAL_ANALYZER's spectrum meter, small): a 4.5 dB/oct tilt about 1 kHz, an attack
// at once, a release of 120 dB/s, no peak hold. A voice at the microphone sits lower than a voice at the speaker, so the
// top here is -18 dB (a close voice in its loudest band reaches it) and the range 50 dB below it.
final class WaveView: NSView {
    static let TILT = 4.5, RELEASE = 120.0, TOP = -18.0, RANGE = 50.0
    static let centres: [Double] = (0..<11).map { 80 * pow(11000.0 / 80, (Double($0) + 0.5) / 11) }
    var moving = false
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }       // v23: a press on the wave drags the blob (PillView)
    // v22 (Marko, 31.10.2026: "If voice commands are active ... this spectral meter is always running, but only in
    // different colors ... yellow and when it starts to transcribe it's green"): white as before without voice activation
    static let white = NSColor(white: 1, alpha: 0.92)
    static let yellow = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.22, alpha: 1)
    var color = WaveView.white { didSet { if color != oldValue { needsDisplay = true } } }
    var spec = [Double](repeating: -140, count: 11)
    var last = CFAbsoluteTimeGetCurrent()
    static func height(_ db: Double) -> Double { min(1, max(0, (db - (TOP - RANGE)) / RANGE)) }
    func take(_ db: [Double]?) {
        let t = CFAbsoluteTimeGetCurrent(), dt = min(0.2, t - last); last = t
        let db = db ?? []
        for c in 0..<spec.count {
            var m = moving && c < db.count ? db[c] : -140
            if m > -140 { m += WaveView.TILT * log2(WaveView.centres[c] / 1000) }
            spec[c] = m > spec[c] ? m : max(m, spec[c] - WaveView.RELEASE * dt)
        }
        needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        let n = spec.count, gap: CGFloat = 4, w: CGFloat = 2.6
        let x0 = (bounds.width - CGFloat(n) * w - CGFloat(n - 1) * gap) / 2
        color.setFill()
        for i in 0..<n {
            let h = max(w, CGFloat(WaveView.height(spec[i])) * (bounds.height - 16) + w)
            let rect = NSRect(x: x0 + CGFloat(i) * (w + gap), y: 9, width: w, height: h)
            NSBezierPath(roundedRect: rect, xRadius: w / 2, yRadius: w / 2).fill()
        }
    }
}

// The dark pill, dragged by its body anywhere; the panel's move is kept by Place (main.swift).
final class PillView: NSView {
    var start: NSPoint?; var origin = NSPoint.zero
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.97).setFill(); p.fill()
        NSColor(white: 1, alpha: 0.10).setStroke(); p.lineWidth = 1; p.stroke()
    }
    override func mouseDown(with e: NSEvent) { start = NSEvent.mouseLocation; origin = window?.frame.origin ?? .zero }
    override func mouseDragged(with e: NSEvent) {
        guard let s = start, let w = window else { return }
        let m = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: origin.x + m.x - s.x, y: origin.y + m.y - s.y))
    }
    override func mouseUp(with e: NSEvent) { start = nil }
}

// v15 (Marko, 31.10.2026: "put half transparent black background below the text above the Blob because it is not
// visible"): the line above the pill sits on a black band at 55 %, as wide as its words, rounded.
final class BandField: NSTextField {
    // v22 (Marko, 31.10.2026: "if I click and hold on the status line on the blob, this is for moving the whole user
    // interface. If I click shortly, then I am changing the position of status line"): a short click (under 0.3 s, under
    // 4 pt of movement) calls `clicked`; holding or dragging moves the panel (its place is saved by the stripe's move
    // observer), and a drag never ends in a click
    var clicked: (() -> Void)?
    private var downAt: Date?, downMouse = NSPoint.zero, downOrigin = NSPoint.zero, dragged = false
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func mouseDown(with e: NSEvent) {
        downAt = Date(); downMouse = NSEvent.mouseLocation; downOrigin = window?.frame.origin ?? .zero; dragged = false
    }
    override func mouseDragged(with e: NSEvent) {
        guard let w = window, downAt != nil else { return }
        let m = NSEvent.mouseLocation
        if !dragged && hypot(m.x - downMouse.x, m.y - downMouse.y) < 4 { return }
        dragged = true
        w.setFrameOrigin(NSPoint(x: downOrigin.x + m.x - downMouse.x, y: downOrigin.y + m.y - downMouse.y))
    }
    override func mouseUp(with e: NSEvent) {
        defer { downAt = nil }
        guard let t = downAt, !dragged, Date().timeIntervalSince(t) < 0.3 else { return }
        let m = NSEvent.mouseLocation
        if hypot(m.x - downMouse.x, m.y - downMouse.y) < 4 { clicked?() }
    }
    override func draw(_ r: NSRect) {
        if !stringValue.isEmpty {
            let w = min(bounds.width, ceil(attributedStringValue.size().width) + 16)
            NSColor(white: 0, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(r)
    }
}

// The panel's content: the line above, the pill below, centred; the rest of the panel is clear and lets clicks through.
final class PillFace: NSView {
    let pill = PillView(frame: NSRect(x: (PANEL_W - PILL_W) / 2, y: 0, width: PILL_W, height: PILL_H))
    let line = BandField(labelWithString: "")
    let wave = WaveView(frame: NSRect(x: 96, y: 0, width: 80, height: PILL_H))
    var close: BlobButton!, lang: BlobButton!, pause: BlobButton!, style: BlobButton!, copy: BlobButton!, gear: BlobButton!, send: BlobButton!
    override var isFlipped: Bool { false }

    // v23 (Marko, 31.10.2026: "it's also anywhere where there is no button in upper part of the user interface. I can
    // drag it around"): any part of the blob that is not a button drags it (the status line keeps its short click)
    private var dragStart: NSPoint?, dragOrigin = NSPoint.zero
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { dragStart = NSEvent.mouseLocation; dragOrigin = window?.frame.origin ?? .zero }
    override func mouseDragged(with e: NSEvent) {
        guard let s = dragStart, let w = window else { return }
        let m = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: dragOrigin.x + m.x - s.x, y: dragOrigin.y + m.y - s.y))
    }
    override func mouseUp(with e: NSEvent) { dragStart = nil }
    // the empty parts must reach this view: a clear pixel lets the click through to the app below, so the panel's empty
    // area gets a fill the eye does not see (1 %), not a shape and no shadow
    override func draw(_ r: NSRect) { NSColor(white: 0, alpha: 0.01).setFill(); bounds.fill() }

    init(close: @escaping () -> Void, lang: @escaping () -> Void, pause: @escaping () -> Void, style: @escaping () -> Void,
         copy: @escaping () -> Void, gear: @escaping () -> Void, send: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: PANEL_W, height: PILL_H + LINE_H))
        let grey = NSColor(white: 0.36, alpha: 1), white = NSColor(white: 0.95, alpha: 1)
        self.close = BlobButton("xmark", NSRect(x: 4, y: 2, width: 36, height: 36), circle: grey, tint: white, tip: "Throw this take away (Esc)", close)
        // v17 (Marko, 31.10.2026: "put the language badge next to the X on the right side and put it in square
        // brackets"): [AUTO] right after ✕
        self.lang = BlobButton("globe", NSRect(x: 42, y: 2, width: 52, height: 36), circle: nil, tint: white, tip: "The language of this take: Croatian or English", lang)
        // v17 (Marko, 31.10.2026: "the pose and style are in the same area. They are overlapping ... never overlap two
        // buttons"): PAUSE and STYLE each in a place of its own, both always there; one that cannot act now is grey
        self.pause = BlobButton("pause.fill", NSRect(x: 180, y: 2, width: 40, height: 36), circle: nil, tint: white, tip: "Pause; press again to go on", pause)
        // v15 STYLE (Marko, 31.10.2026: "one more action button inside the blob ... style ... It's going to use my prompt to
        // style the text pasted in that text field. And when I press style it means the blob will stay"): in the pause's
        // own place beside the pause (v17; v15 put it in the pause's place)
        // v22 (Marko, 31.10.2026: "switch the spaces with style and copy. Copy first style second"): COPY at 222, STYLE at 282
        self.style = BlobButton("", NSRect(x: 282, y: 2, width: 60, height: 36), circle: nil, tint: white,
                                tip: "Style: the text box you clicked into (its selection, or all of it) is corrected in place; the blob then stays until ✕", style)
        self.style.text = "STYLE"
        self.lang.bracketed = true
        // v17 COPY (Marko, 31.10.2026: "same as style, copy button is always available ... if it doesn't land in any
        // window ... this blob will not disappear, it will wait for action. and then I simply can press copy"): grey at
        // rest, green while it copies
        self.copy = BlobButton("", NSRect(x: 222, y: 2, width: 56, height: 36), circle: nil, tint: BlobButton.dim,
                               tip: "Copy the last words to the clipboard, then ⌘V where you want them", copy)
        self.copy.text = "COPY"
        self.gear = BlobButton("gearshape.fill", NSRect(x: 348, y: 2, width: 36, height: 36), circle: nil, tint: white, tip: "Who hears you, who cleans the words, the history, the settings", gear)
        self.send = BlobButton("arrow.up", NSRect(x: 390, y: 2, width: 36, height: 36), circle: BLUE, tint: white, tip: "Send: write it down and type it (F1)", send)
        pill.addSubview(self.close); pill.addSubview(wave)
        for b in [self.lang!, self.pause!, self.style!, self.copy!, self.gear!, self.send!] { pill.addSubview(b) }
        for (b, id) in [(self.close!, "close"), (self.lang!, "language"), (self.pause!, "pause"), (self.style!, "style"), (self.copy!, "copy"),
                        (self.gear!, "settings"), (self.send!, "send")] { b.setAccessibilityIdentifier(id) }
        addSubview(pill)
        placeLine(below: false)
        line.alignment = .center
        line.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        line.textColor = NSColor(white: 1, alpha: 0.75)
        line.lineBreakMode = .byTruncatingTail
        let sh = NSShadow(); sh.shadowColor = .black; sh.shadowBlurRadius = 3; line.shadow = sh
        addSubview(line)
    }
    required init?(coder: NSCoder) { fatalError() }

    // v29 (Marko, 1.11.2026: "If there is an auto correct option under the settings gear icon, then the style ... needs to
    // light up so it is white. In the same way, copy should also become white if my transcription didn't fall into any
    // box"): green while working; white when there is something for it (an auto correct chosen in ⚙ / a take that landed
    // nowhere waiting for COPY); grey otherwise
    func light(autoCorrect: Bool, styling: Bool, unlanded: Bool, copying: Bool) {
        style.tint = styling ? Ink.green : autoCorrect ? BlobButton.lit : BlobButton.dim
        copy.tint = copying ? Ink.green : unlanded ? BlobButton.lit : BlobButton.dim
    }

    // v22 (Marko, 31.10.2026: "Only function of the clicking is to push this line at the bottom of blob or at the top"):
    // the line above the pill or below it, the panel the same size
    func placeLine(below: Bool) {
        if below {
            line.frame = NSRect(x: 0, y: 0, width: PANEL_W, height: LINE_H - 2)
            pill.frame.origin.y = LINE_H
        } else {
            pill.frame.origin.y = 0
            line.frame = NSRect(x: 0, y: PILL_H + 2, width: PANEL_W, height: LINE_H - 2)
        }
        needsDisplay = true
    }

    // --pill-shot <png>: the face drawn off screen, so it is checked without taking his screen
    func png() -> Data? {
        let back = NSView(frame: bounds.insetBy(dx: 0, dy: -8))
        back.wantsLayer = true; back.layer?.backgroundColor = NSColor(white: 0.55, alpha: 1).cgColor
        frame.origin = NSPoint(x: 0, y: 8); back.addSubview(self)
        guard let rep = back.bitmapImageRepForCachingDisplay(in: back.bounds) else { return nil }
        back.cacheDisplay(in: back.bounds, to: rep)
        removeFromSuperview(); frame.origin = .zero
        return rep.representation(using: .png, properties: [:])
    }
}
