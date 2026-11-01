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

    // the download in ⚙: progress 0…1, then the result (nil = done)
    private static var task: URLSessionDownloadTask?
    private static var watch: NSKeyValueObservation?
    static var downloading: Bool { task != nil }

    static func download(progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
        guard task == nil else { return }
        let t = URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            var problem: String?
            if let err { problem = err.localizedDescription }
            else if let tmp {
                let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
                if size < bytes { problem = "the download was cut short (\(size / 1_000_000) MB)" }
                else {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: file)
                    do { try FileManager.default.moveItem(at: tmp, to: file) } catch { problem = error.localizedDescription }
                }
            }
            DispatchQueue.main.async { task = nil; watch = nil; done(problem) }
        }
        watch = t.progress.observe(\.fractionCompleted) { p, _ in DispatchQueue.main.async { progress(p.fractionCompleted) } }
        task = t
        t.resume()
    }

    static func cancel() { task?.cancel() }
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
        var cp = whisper_context_default_params()
        cp.use_gpu = true
        cp.flash_attn = true
        ctx = whisper_init_from_file_with_params(Model.file.path, cp)
        appendLog(ctx == nil ? "whisper: the model did not load" : "whisper: model loaded")
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
