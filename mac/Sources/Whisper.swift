// Mantra Voice to Text: Whisper inside the app (whisper.cpp with Metal), no server, no Python, no ffmpeg.
//
// The public sibling of Mantra Voice to Text (1.11.2026): the model is one file, Whisper large-v3-turbo quantised
// q5_0 (547 MB), downloaded once from ⚙ into the app's own folder; after that the Mac can be offline for good.
import Foundation
import AVFoundation

enum Model {
    static let name = "ggml-large-v3-turbo-q5_0.bin"
    static let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    static let bytes: Int64 = 574_041_195                  // the published size; a smaller file is a broken download
    static let folder = appSupport.appendingPathComponent("models")
    static var file: URL { folder.appendingPathComponent(name) }

    static var ready: Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        return size >= bytes
    }

    // THE DOWNLOAD ALWAYS RESUMES (Marko, 1.11.2026: "always resume downloads. Even if the user closes the application
    // and you open, it will continue where it left off"). The bytes go into <name>.part; every start asks only for what
    // is missing (HTTP Range), a dropped connection retries by itself from the bytes already there, and the app continues
    // a .part on its own at the next launch. A server answering 200 instead of 206 starts the file over.
    static var part: URL { folder.appendingPathComponent(name + ".part") }
    static var partSize: Int64 { (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0 }
    static var started: Bool { FileManager.default.fileExists(atPath: part.path) }
    private static var loader: Loader?
    static var downloading: Bool { loader != nil }
    static var onProgress: ((Double) -> Void)?
    static var onDone: ((String?) -> Void)?
    static var onWait: ((String) -> Void)?

    static func download(progress: ((Double) -> Void)? = nil, done: ((String?) -> Void)? = nil) {
        if let progress { onProgress = progress }
        if let done { onDone = done }
        guard loader == nil, !ready else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !started { FileManager.default.createFile(atPath: part.path, contents: nil) }
        let l = Loader()
        loader = l
        l.start()
    }

    /// pressed Cancel: stops now, keeps the .part (the next press or start goes on from it)
    static func cancel() { loader?.stop(); loader = nil; onDone?("paused: press Download to go on") }

    fileprivate static func finished(_ problem: String?) {
        loader = nil
        if problem == nil {
            try? FileManager.default.removeItem(at: file)
            do { try FileManager.default.moveItem(at: part, to: file) } catch { onDone?(error.localizedDescription); return }
            appendLog("model: downloaded")
        }
        onDone?(problem)
    }

    final class Loader: NSObject, URLSessionDataDelegate {
        private var session: URLSession?
        private var out: FileHandle?
        private var have: Int64 = 0
        private var tries = 0
        private var stopped = false

        func start() {
            guard !stopped else { return }
            have = Model.partSize
            appendLog("model: download from byte \(have) of \(Model.bytes)")
            var req = URLRequest(url: Model.url)
            if have > 0 { req.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            req.timeoutInterval = 60
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session?.dataTask(with: req).resume()
        }

        func stop() { stopped = true; session?.invalidateAndCancel(); try? out?.close(); out = nil }

        func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive resp: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 || code == 206 else { completionHandler(.cancel); return }
            if code == 200 && have > 0 {                       // the server ignored the range: from the start
                try? FileManager.default.removeItem(at: Model.part)
                FileManager.default.createFile(atPath: Model.part.path, contents: nil)
                have = 0
            }
            out = try? FileHandle(forWritingTo: Model.part)
            _ = try? out?.seekToEnd()
            completionHandler(out == nil ? .cancel : .allow)
        }

        func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            out?.write(data)
            have += Int64(data.count)
            tries = 0                                           // bytes arrived: the next drop starts a fresh count
            let f = Double(have) / Double(Model.bytes)
            DispatchQueue.main.async { Model.onProgress?(f) }
        }

        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            try? out?.close(); out = nil
            s.finishTasksAndInvalidate()
            if stopped { return }
            if Model.partSize >= Model.bytes { DispatchQueue.main.async { Model.finished(nil) }; return }
            // cut short or an error: wait a little and go on from the bytes already there, as long as it takes
            tries += 1
            let wait = min(60.0, pow(2.0, Double(min(tries, 6))))
            appendLog("model: stopped at \(Model.partSize) (\(error?.localizedDescription ?? "cut short")), again in \(Int(wait)) s")
            DispatchQueue.main.async { Model.onWait?("connection lost, going on in \(Int(wait)) s…") }
            DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [weak self] in self?.start() }
        }
    }
}

/// One Whisper, loaded once and kept (the load is seconds, a take is under one). Takes run one at a time.
enum Whisper {
    private static var ctx: OpaquePointer?
    private static let q = DispatchQueue(label: "whisper")
    static var lastLang: String?

    /// load the model if it is there (called when a take starts, so the first take does not wait for the load)
    static func warm() { q.async { _ = load() } }

    private static func load() -> OpaquePointer? {
        if let ctx { return ctx }
        guard Model.ready else { return nil }
        // a Mac whose Metal cannot build whisper.cpp's shaders aborts inside the load (seen on macOS 15.0 before the
        // shader patch): the mark stays set, and the next start loads on the processor instead
        let d = UserDefaults.standard
        if d.bool(forKey: "loadingModel") { d.set(true, forKey: "cpuOnly"); appendLog("whisper: the last load did not finish, using the processor") }
        var cp = whisper_context_default_params()
        cp.use_gpu = !d.bool(forKey: "cpuOnly")
        cp.flash_attn = cp.use_gpu
        d.set(true, forKey: "loadingModel"); d.synchronize()
        ctx = whisper_init_from_file_with_params(Model.file.path, cp)
        d.set(false, forKey: "loadingModel")
        appendLog(ctx == nil ? "whisper: the model did not load" : "whisper: model loaded (\(cp.use_gpu ? "GPU, Metal" : "processor"))")
        return ctx
    }

    /// The words of a recording. lang: "en", "hr" or "auto" (auto is held to Croatian or English).
    static func transcribe(_ source: URL, lang: String) -> Result<String, EngineError> {
        guard Model.ready else { return .failure(EngineError("no Whisper model yet: ⚙ → Settings → Download the model")) }
        guard let pcm = Audio.pcm16k(source), pcm.count > 8000 else { return .failure(EngineError("nothing recorded")) }
        return q.sync {
            guard let ctx = load() else { return .failure(EngineError("the Whisper model did not load")) }
            let threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
            var chosen = lang
            if lang == "auto" {
                // the language of this take, between Croatian and English only
                _ = pcm.withUnsafeBufferPointer { whisper_pcm_to_mel(ctx, $0.baseAddress, Int32($0.count), threads) }
                var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
                _ = whisper_lang_auto_detect(ctx, 0, threads, &probs)
                let en = probs[Int(whisper_lang_id("en"))], hr = probs[Int(whisper_lang_id("hr"))]
                chosen = hr > en ? "hr" : "en"
            }
            lastLang = chosen
            var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            p.n_threads = threads
            p.print_progress = false; p.print_realtime = false; p.print_timestamps = false; p.print_special = false
            p.no_context = true                    // a wrong word in one take never poisons the next
            p.single_segment = false
            p.suppress_blank = true
            let ok: Int32 = chosen.withCString { l in
                p.language = l
                return pcm.withUnsafeBufferPointer { whisper_full(ctx, p, $0.baseAddress, Int32($0.count)) }
            }
            guard ok == 0 else { return .failure(EngineError("Whisper failed (\(ok))")) }
            var text = ""
            for i in 0..<whisper_full_n_segments(ctx) {
                if let c = whisper_full_get_segment_text(ctx, i) { text += String(cString: c) }
            }
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

// MARK: the take's audio, by AVFoundation (no ffmpeg)
enum Audio {
    /// 16 kHz mono float samples, what Whisper hears
    static func pcm16k(_ url: URL) -> [Float]? {
        guard let f = try? AVAudioFile(forReading: url),
              let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: f.processingFormat, to: out),
              let inBuf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return nil }
        do { try f.read(into: inBuf) } catch { return nil }
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * 16000 / f.processingFormat.sampleRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return nil }
        var given = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, let ch = outBuf.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }

    /// the history's copy: Apple Lossless at the recorded rate, mono
    static func archive(_ src: URL, to dst: URL) -> Bool {
        guard let f = try? AVAudioFile(forReading: src),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return false }
        do { try f.read(into: buf) } catch { return false }
        try? FileManager.default.removeItem(at: dst)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: f.processingFormat.sampleRate,
                                       AVNumberOfChannelsKey: f.processingFormat.channelCount]
        guard let w = try? AVAudioFile(forWriting: dst, settings: settings, commonFormat: f.processingFormat.commonFormat,
                                       interleaved: f.processingFormat.isInterleaved) else { return false }
        do { try w.write(from: buf) } catch { return false }
        return true
    }
}
