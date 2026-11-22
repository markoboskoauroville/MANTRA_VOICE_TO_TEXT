import AppKit
import AVFoundation
import Accelerate

// v62, Marko, 21.11.2026: "adding a simple ... small ellipse indicator while I'm recording to come at the bottom of the
// screen. That's all bottom of the screen, and it needs to have a spectral analyzer while I'm talking."
//
// A small dark ellipse at the bottom centre of the screen (above the Dock), with 20 spectrum bars from 80 Hz to 8 kHz that move
// with his voice. It shows while a take is recording (not paused), and goes when the take stops. The samples are the ones the
// take's own audio data output already delivers (MicBands.captureOutput calls RecordingIndicator.feed): no second input.
// Test hook `.indicator` (userInfo seconds): shows it for N seconds fed by a temporary microphone session, no take.
final class RecordingIndicator {
    static let shared = RecordingIndicator()
    static let bars = 20, N = 2048, LOG2N = vDSP_Length(11)
    static let W: CGFloat = 150, H: CGFloat = 40
    static let TILT = 4.5, TOP = -18.0, RANGE = 50.0

    private weak var stripe: Stripe?
    private var panel: NSPanel?
    private var view: BarsView?
    private var timer: Timer?
    private var shown = false
    private var testUntil: Date?
    private var testState = "recording"      // v64 hook: recording | paused | transcribing
    private var testScreen: Int?             // v64 hook: index in NSScreen.screens; nil = the screen with the mouse
    private var testSession: AVCaptureSession?
    private var testBands: MicBands?

    // the analysis (any thread)
    private static let setup = vDSP_create_fftsetup(LOG2N, FFTRadix(kFFTRadix2))!
    private static let window: [Float] = { var w = [Float](repeating: 0, count: N); vDSP_hann_window(&w, vDSP_Length(N), Int32(vDSP_HANN_DENORM)); return w }()
    private static let lock = NSLock()
    private static var latest = [Double](repeating: -140, count: bars)
    private static var live = false          // only analyse while the indicator is up

    func start(_ s: Stripe) {
        stripe = s
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// called from MicBands for each audio buffer: the last 2048 samples
    static func feed(_ ring: [Float], rate: Double) {
        guard live, ring.count >= N else { return }
        var x = [Float](repeating: 0, count: N)
        vDSP_vmul(ring, 1, window, 1, &x, 1, vDSP_Length(N))
        var re = [Float](repeating: 0, count: N / 2), im = [Float](repeating: 0, count: N / 2)
        var power = [Float](repeating: 0, count: N / 2)
        re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            x.withUnsafeBufferPointer { xp in
                xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(N / 2)) }
            }
            vDSP_fft_zrip(setup, &split, 1, LOG2N, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(N / 2))
        } }
        let full = Double(N / 2) * Double(N / 2) * 1.5, hz = rate / Double(N)
        var out = [Double](repeating: -140, count: bars)
        for b in 0..<bars {
            let e0 = 80 * pow(100.0, Double(b) / Double(bars)), e1 = 80 * pow(100.0, Double(b + 1) / Double(bars))   // 80 Hz ... 8 kHz
            let lo = max(1, Int(ceil(e0 / hz))), hi = min(N / 2 - 1, max(lo, Int(floor(e1 / hz))))
            var sum = 0.0
            for k in lo...hi { sum += Double(power[k]) }
            var db = sum > 0 ? 10 * log10(sum / full) : -140
            if db > -140 { db += TILT * log2(sqrt(e0 * e1) / 1000) }
            out[b] = db
        }
        lock.lock(); latest = out; lock.unlock()
    }

    private func tick() {
        let taking0 = stripe.map { $0.recorder.recording && !$0.recorder.paused } ?? false
        // v63: the centre oval is gone; its Paused and Transcribing states live here, in the same ellipse
        let paused0 = stripe.map { $0.recorder.recording && $0.recorder.paused } ?? false
        let working0 = stripe.map { !$0.recorder.recording && $0.busy } ?? false
        let testing = testUntil.map { Date() < $0 } ?? false
        if testUntil != nil && !testing { endTest() }
        let taking = taking0 || (testing && testState == "recording")
        let paused = paused0 || (testing && testState == "paused")
        let working = working0 || (testing && testState == "transcribing")
        if taking {
            if !shown { show(taking0 ? "take" : "hook") }
            RecordingIndicator.lock.lock(); let db = RecordingIndicator.latest; RecordingIndicator.lock.unlock()
            view?.mode = 0; RecordingIndicator.live = true
            view?.take(db)
        } else if paused || working {
            if !shown {
                show(paused ? "paused" : "transcribing")
                if paused && !paused0 { view?.demoShape() }      // hook only: a take that was talking before the pause
            }
            view?.mode = paused ? 1 : 2          // 1: bars frozen and dimmed; 2: a quiet wave runs through the bars
            RecordingIndicator.live = false
            view?.take([])
        } else if shown { hide() }
    }

    private func show(_ why: String) {
        var sc = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        if let i = testScreen, testUntil != nil, NSScreen.screens.indices.contains(i) { sc = NSScreen.screens[i] }
        let vf = sc.visibleFrame, w = RecordingIndicator.W, h = RecordingIndicator.H
        let r = NSRect(x: vf.midX - w / 2, y: vf.minY + 14, width: w, height: h)
        if panel == nil {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.ignoresMouseEvents = true; p.hidesOnDeactivate = false
            let v = BarsView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.88).cgColor
            v.layer?.cornerRadius = h / 2
            v.layer?.masksToBounds = true
            v.layer?.borderWidth = 0.5
            v.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
            p.contentView = v
            panel = p; view = v
        }
        panel?.setFrame(r, display: false)
        view?.reset()
        RecordingIndicator.live = true
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        shown = true
        appendLog("indicator: shown (\(why)) on \(NSStringFromRect(r))")
    }

    private func hide() {
        shown = false
        RecordingIndicator.live = false
        panel?.orderOut(nil)
        appendLog("indicator: hidden")
    }

    // MARK: test hook (no take): a temporary microphone session feeds the bars
    func test(seconds: Double, state: String = "recording", screen: Int? = nil) {
        if stripe?.recorder.recording == true { appendLog("indicator test: a take is recording, the indicator is already up"); return }
        endTest()
        if shown { hide() }
        testState = state; testScreen = screen
        if state != "recording" {          // paused / transcribing: no microphone needed
            testUntil = Date().addingTimeInterval(seconds)
            appendLog("indicator test: \(state) \(seconds) s screen \(screen.map(String.init) ?? "mouse")")
            return
        }
        guard let dev = InputDevice.current(), let input = try? AVCaptureDeviceInput(device: dev) else { appendLog("indicator test: no microphone"); return }
        let s = AVCaptureSession(), data = AVCaptureAudioDataOutput(), mb = MicBands()
        data.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
                              AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true]
        data.setSampleBufferDelegate(mb, queue: mb.queue)
        guard s.canAddInput(input), s.canAddOutput(data) else { return }
        s.addInput(input); s.addOutput(data)
        RecordingIndicator.live = true
        s.startRunning()
        testSession = s; testBands = mb
        testUntil = Date().addingTimeInterval(seconds)
        appendLog("indicator test: recording \(seconds) s screen \(screen.map(String.init) ?? "mouse")")
    }

    private func endTest() {
        testSession?.stopRunning(); testSession = nil; testBands = nil; testUntil = nil; testScreen = nil; testState = "recording"
    }
}

final class BarsView: NSView {
    private var spec = [Double](repeating: -140, count: RecordingIndicator.bars)
    private var last = CFAbsoluteTimeGetCurrent()
    var mode = 0           // v63: 0 recording, 1 paused (frozen, dim), 2 transcribing (quiet moving wave)
    func demoShape() { for c in 0..<spec.count { spec[c] = RecordingIndicator.TOP - RecordingIndicator.RANGE * (0.75 - 0.6 * abs(sin(Double(c) * 0.55))) } }
    func reset() { spec = [Double](repeating: -140, count: spec.count); last = CFAbsoluteTimeGetCurrent(); needsDisplay = true }
    func take(_ db: [Double]) {
        if mode == 1 { needsDisplay = true; return }
        if mode == 2 {
            let ph = CFAbsoluteTimeGetCurrent() * 3
            for c in 0..<spec.count { spec[c] = RecordingIndicator.TOP - RecordingIndicator.RANGE * (0.62 - 0.22 * sin(ph - Double(c) * 0.5)) }
            needsDisplay = true; return
        }
        let t = CFAbsoluteTimeGetCurrent(), dt = min(0.2, t - last); last = t
        for c in 0..<spec.count {
            let m = c < db.count ? db[c] : -140
            spec[c] = m > spec[c] ? m : max(m, spec[c] - 90 * dt)         // attack at once, smooth release
        }
        needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        let n = spec.count, gap: CGFloat = 2.5, w: CGFloat = 3.2
        let x0 = (bounds.width - CGFloat(n) * w - CGFloat(n - 1) * gap) / 2
        let maxH = bounds.height - 14
        NSColor(white: 1, alpha: mode == 1 ? 0.4 : (mode == 2 ? 0.6 : 0.92)).setFill()
        for i in 0..<n {
            let f = min(1, max(0, (spec[i] - (RecordingIndicator.TOP - RecordingIndicator.RANGE)) / RecordingIndicator.RANGE))
            let h = max(w, CGFloat(f) * maxH)
            let rect = NSRect(x: x0 + CGFloat(i) * (w + gap), y: (bounds.height - h) / 2, width: w, height: h)
            NSBezierPath(roundedRect: rect, xRadius: w / 2, yRadius: w / 2).fill()
        }
    }
}
