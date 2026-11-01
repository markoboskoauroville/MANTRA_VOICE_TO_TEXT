// v21, VOICE ACTIVATION (Marko, 31.10.2026: "my blob for transcription can be activated with voice ... One check mark.
// Listen. That's the to start transcription. Send. To send transcription. Simple ... the way which doesn't spend too
// much CPU or GPU power"; "next to the voice activation checkbox ... in parenthesis put the starting word and ending word").
//
// The way: Apple's own on-device speech recognition (SFSpeechRecognizer, en-US, requiresOnDeviceRecognition), told the
// two words as contextual strings. No model of ours, no GPU, no sample of his voice; the audio never leaves the Mac.
// Its own capture session on the same microphone the takes use (⚙'s recording device; the Mac's default input is
// BlackHole), 16 kHz mono 16-bit, beside the take's own session (macOS lets both read one device).
//
// THE GATE (measured 31.10.2026: the recognizer running on room sound cost 13 % of a core in Apple's
// localspeechrecognition, the app 4 %): the recognizer runs only while there is sound. Each buffer's level is read
// (a few multiplications); after 2.5 s under the quiet line the task is ended, and the next sound starts a new one with
// the last 0.6 s fed first, so the word's beginning is not lost.
//
// A word counts only when it stands alone: a pause before it (when the recognizer gives times) and 0.7 s of nothing new
// after it, so "please send me the file" in the middle of a take does not send it.
import AVFoundation
import Speech

enum VoiceWords {
    // THE WORDS, ONE PLACE: the recognizer, the matcher, the cut from the text and ⚙'s label all read these
    static let start = "listen"
    static let end = "send"
    static var label: String { "Voice activation (start: \"\(start.capitalized)\", end: \"\(end.capitalized)\")" }

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceActivation") }           // off by default
        set { UserDefaults.standard.set(newValue, forKey: "voiceActivation") }
    }

    static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// the command words cut from a take's text: "listen" at its start, "send" at its end (Whisper hears them too)
    static func strip(_ text: String) -> String {
        var s = text
        for (pattern, _) in [(#"^\s*\#(start)\b[\s.,!?…]*"#, 0), (#"[\s,.!?…]*\b\#(end)\b[\s.,!?…]*$"#, 1)] {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // the sentence lost its full stop with the word: put one back when it ends in a letter
        if let last = s.last, last.isLetter || last.isNumber { s += "." }
        return s
    }

    /// is segment i a command standing alone? (pause before; pause after when the next segment is known)
    static func alone(_ segs: [SFTranscriptionSegment], _ i: Int, after known: Bool) -> Bool {
        let s = segs[i]
        if i > 0 {
            let p = segs[i - 1]
            // the times are 0 in some partial results: then the word must be the first of the stretch
            if s.timestamp > 0 { if s.timestamp - (p.timestamp + p.duration) < 0.3 { return false } } else { return false }
        }
        if known, i + 1 < segs.count { return segs[i + 1].timestamp - (s.timestamp + s.duration) >= 0.6 }
        return true
    }

    static var authorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var micAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
}

final class VoiceCommands: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// which word may act now (the stripe says: "listen" while idle, "send" while a take records), nil: none
    var wanted: () -> String? = { nil }
    var heard: (String) -> Void = { _ in }
    /// v22: the same microphone in eleven bands for the blob's yellow meter (a second output of this session, float at
    /// 24 kHz so the top band up to 11 kHz is there; the recognizer keeps its 16 kHz)
    let bands = MicBands()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var session: AVCaptureSession?
    private var request: SFSpeechAudioBufferRecognitionRequest?      // touched on `queue` only
    private var task: SFSpeechRecognitionTask?
    private let queue = DispatchQueue(label: "voice-commands")
    private var generation = 0               // each task its number: an old task's late answer is ignored
    private var renew: Timer?
    private(set) var buffers = 0             // for the test: audio arrived
    private(set) var tasks = 0               // for the test: how often the recognizer was woken
    private(set) var levels: [Float] = []    // for the test: each buffer's level, dBFS
    // dBFS RMS: under it is the room, over it someone speaks (UserDefaults voiceQuietLine, -48 by default)
    static var quietLine: Float { UserDefaults.standard.object(forKey: "voiceQuietLine") != nil ? UserDefaults.standard.float(forKey: "voiceQuietLine") : -48 }
    private var preroll: [CMSampleBuffer] = []
    private var lastLoud = Date.distantPast
    private var waking = false
    private var commandPending = false        // on `queue`: the last word heard is the command
    var running: Bool { session != nil }

    func start() {
        guard session == nil, VoiceWords.authorized, VoiceWords.micAllowed, let r = recognizer, r.supportsOnDeviceRecognition,
              let dev = InputDevice.current(), let input = try? AVCaptureDeviceInput(device: dev) else {
            appendLog("voice activation: not started (speech \(SFSpeechRecognizer.authorizationStatus().rawValue), mic \(VoiceWords.micAllowed), on device \(recognizer?.supportsOnDeviceRecognition ?? false))")
            return
        }
        let s = AVCaptureSession(), out = AVCaptureAudioDataOutput()
        out.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
                             AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false]
        out.setSampleBufferDelegate(self, queue: queue)
        guard s.canAddInput(input), s.canAddOutput(out) else { return }
        s.addInput(input); s.addOutput(out)
        let meter = AVCaptureAudioDataOutput()
        meter.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true]
        meter.setSampleBufferDelegate(bands, queue: bands.queue)
        bands.reset()
        if s.canAddOutput(meter) { s.addOutput(meter) }
        session = s
        queue.async { s.startRunning() }
        // a fresh task every 50 s while it is awake: the text does not pile up and the time limit is never met
        renew = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.queue.sync(execute: { self.request != nil }) { self.newTask() }
        }
        appendLog("voice activation: listening for \"\(VoiceWords.start)\" and \"\(VoiceWords.end)\" on \(dev.localizedName)")
    }

    func stop() {
        renew?.invalidate(); renew = nil
        sleep()
        if let s = session { queue.async { s.stopRunning() } }
        session = nil
    }

    /// the device was changed in ⚙: listen on the new one
    func restart() { stop(); if VoiceWords.enabled { start() } }

    /// the recognizer ends until the next sound
    private func sleep() {
        generation += 1
        task?.cancel(); task = nil
        queue.sync { request?.endAudio(); request = nil; waking = false }
    }

    /// a new recognition task, fed first with the last 0.6 s (main thread)
    private func newTask() {
        guard session != nil || feeding, let r = recognizer else { return }
        generation += 1
        tasks += 1
        let mine = generation
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.contextualStrings = [VoiceWords.start.capitalized, VoiceWords.end.capitalized]
        req.taskHint = .confirmation                 // short commands
        queue.sync {
            request?.endAudio()
            for b in preroll { req.appendAudioSampleBuffer(b) }
            request = req
            waking = false
        }
        task = r.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, mine == self.generation else { return }
                if let result {
                    if self.feeding { print("    [\(mine)\(result.isFinal ? " final" : "")] " + result.bestTranscription.segments.map { String(format: "%@@%.2f", $0.substring, $0.timestamp) }.joined(separator: " ")) }
                    result.isFinal ? self.lookFinal(result) : self.look(result, mine)
                }
                if let error, self.feeding { print("    [\(mine)] error:", error.localizedDescription) }
                if error != nil || result?.isFinal == true { self.sleep() }       // the next sound wakes it
            }
        }
    }

    // the newest words: when the last is the wanted command, standing alone, and nothing new comes for 0.7 s, it acts
    private var seen = 0
    private func look(_ result: SFSpeechRecognitionResult, _ mine: Int) {
        seen += 1
        let now = seen
        let segs = result.bestTranscription.segments
        // the command heard last: the stretch is closed after 1 s of quiet (not 2.5), so its final words, with real
        // times (partial results carry made-up ones), come quickly
        let hasCommand = segs.last.map { VoiceWords.norm($0.substring) == wanted() } ?? false
        queue.async { self.commandPending = hasCommand }
        guard let last = segs.last, let want = wanted(), VoiceWords.norm(last.substring) == want,
              VoiceWords.alone(segs, segs.count - 1, after: false) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, mine == self.generation, now == self.seen, self.wanted() == want else { return }
            appendLog("voice activation: \"\(want)\"")
            self.sleep()                               // a fresh start: the word is not heard twice
            self.queue.sync { self.preroll.removeAll() }
            self.heard(want)
        }
    }

    // the final words of a task (their times are reliable): the last word, standing alone, acts at once
    private func lookFinal(_ result: SFSpeechRecognitionResult) {
        let segs = result.bestTranscription.segments
        guard let last = segs.last, let want = wanted(), VoiceWords.norm(last.substring) == want,
              VoiceWords.alone(segs, segs.count - 1, after: true) else { return }
        appendLog("voice activation: \"\(want)\" (final)")
        queue.sync { preroll.removeAll() }
        heard(want)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        take(sampleBuffer)
    }

    private var feeding = false              // the feed test: buffers from a file instead of the microphone

    private func take(_ sampleBuffer: CMSampleBuffer) {
        buffers += 1
        let db = Self.level(sampleBuffer)
        if levels.count < 20000 { levels.append(db) }
        preroll.append(sampleBuffer)
        var kept = 0.0
        preroll = preroll.reversed().filter { b in kept += CMSampleBufferGetDuration(b).seconds; return kept <= 0.6 }.reversed()
        let now = Date()
        if db > Self.quietLine { lastLoud = now }
        if let r = request {
            r.appendAudioSampleBuffer(sampleBuffer)
            // quiet: the audio ends, the task gives its final words (judged by lookFinal), then it sleeps
            if now.timeIntervalSince(lastLoud) > (commandPending ? 1.0 : 2.5) { request = nil; commandPending = false; r.endAudio() }
        } else if db > Self.quietLine && !waking {
            waking = true
            DispatchQueue.main.async { self.newTask() }
        }
    }

    /// RMS of a 16-bit buffer, dBFS
    static func level(_ b: CMSampleBuffer) -> Float {
        guard let block = CMSampleBufferGetDataBuffer(b) else { return -160 }
        var length = 0
        var ptr: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == noErr,
              let p = ptr, length >= 2 else { return -160 }
        let n = length / 2
        var sum: Float = 0
        p.withMemoryRebound(to: Int16.self, capacity: n) { s in for i in 0..<n { let v = Float(s[i]) / 32768; sum += v * v } }
        return 10 * log10(max(sum / Float(n), 1e-16))
    }

    // --test-voice-feed <audio>: the live road (the gate, the pre-roll, the recognizer, the 0.7 s rule) fed from a file at
    // its own pace instead of the microphone: no speaker, no microphone
    static func feed(_ url: URL) {
        let v = VoiceCommands()
        v.feeding = true
        var recording = false
        let t0 = Date()
        v.wanted = { recording ? VoiceWords.end : VoiceWords.start }
        v.heard = { w in
            print(String(format: "%5.1f s  heard \"%@\"", Date().timeIntervalSince(t0), w))
            recording = w == VoiceWords.start
        }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else { print("FAILED: no audio"); return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false])
        reader.add(out)
        reader.startReading()
        var done = false
        DispatchQueue.global().async {
            while let b = out.copyNextSampleBuffer() {
                v.queue.sync { v.take(b) }
                usleep(UInt32(max(0, CMSampleBufferGetDuration(b).seconds) * 1_000_000))
            }
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        print("recognizer woken \(v.tasks)× · \(v.buffers) buffers")
    }

    // --test-voice-commands <audio>: the same recognizer (on device, the same words) on a file, the same "alone" rule
    // with the pause after read from the times; prints every word with its time and the commands found
    static func testFile(_ url: URL) {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { print("FAILED: no recognizer"); return }
        print("speech authorized:", VoiceWords.authorized, "· on device:", r.supportsOnDeviceRecognition)
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        req.contextualStrings = [VoiceWords.start.capitalized, VoiceWords.end.capitalized]
        var done = false
        let t0 = Date()
        r.recognitionTask(with: req) { result, error in
            if let error { print("error:", error.localizedDescription); done = true; return }
            guard let result, result.isFinal else { return }
            let segs = result.bestTranscription.segments
            print(String(format: "recognized in %.1f s: %@", Date().timeIntervalSince(t0), result.bestTranscription.formattedString))
            for (i, s) in segs.enumerated() {
                let w = VoiceWords.norm(s.substring)
                let cmd = (w == VoiceWords.start || w == VoiceWords.end) ? (VoiceWords.alone(segs, i, after: true) ? "  <- COMMAND" : "  <- inside a sentence, ignored") : ""
                print(String(format: "  %5.2f %5.2f  %@%@", s.timestamp, s.duration, s.substring, cmd))
            }
            done = true
        }
        while !done && Date().timeIntervalSince(t0) < 60 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    }
}
