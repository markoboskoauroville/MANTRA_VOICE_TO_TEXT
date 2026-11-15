// TRANSCRIBE A FILE (v15, Marko, 13.11.2026, request from the MPA Lessons Analyzer: "I want to see this thing open up and
// it's working"): any audio or video file, any length. ffmpeg makes mono 16 kHz audio, the audio is cut into pieces that
// respect the engine's limit, the pieces go to the engine picked in order (the v14 rule holds: the same engine retries on a
// network error, the next key of the same provider on a quota, never another engine by itself), every piece's timestamps are
// moved by the piece's start, and the result is saved next to the source as <name>.transcript.json and <name>.transcript.md.
// The window shows it (FilePanel.swift); the local API on 127.0.0.1 (FileAPI) lets other programs ask for it.
import Foundation
import Network

struct Seg { var start: Double; var end: Double; var text: String }
typealias Piece = (text: String, segs: [Seg])

// MARK: one job

final class FileJob {
    let id: String
    let path: String
    let engine: HearEngine
    let created = Date()
    private let lock = NSLock()
    private var _state = "queued"             // queued | extracting | running | done | failed | cancelled
    private var _pieces = 0
    private var _piece = 0                    // the piece being heard (1-based); finished ones are _doneSeconds
    private var _duration = 0.0
    private var _doneSeconds = 0.0
    private var _segs: [Seg] = []
    private var _error = ""
    private var _note = ""
    private var _started: Date?
    private var _ended: Date?
    private var _jsonPath = "", _mdPath = ""
    private var _cancel = false

    init(path: String, engine: HearEngine) {
        self.path = path; self.engine = engine
        self.id = String(UUID().uuidString.prefix(8)).lowercased()
    }

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    func set(_ f: () -> Void) { lock.lock(); f(); lock.unlock() }
    var state: String { lock.lock(); defer { lock.unlock() }; return _state }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancel }
    func cancel() { set { _cancel = true } }
    func setNote(_ s: String) { set { _note = s } }
    var finished: Bool { ["done", "failed", "cancelled"].contains(state) }

    struct Snapshot {
        var state: String, pieces: Int, piece: Int, duration: Double, doneSeconds: Double, segs: [Seg]
        var error: String, note: String, elapsed: Double, eta: Double?, percent: Double, json: String, md: String
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let el = _started.map { (_ended ?? Date()).timeIntervalSince($0) } ?? 0
        var eta: Double?
        if _state == "running", _doneSeconds > 0, _duration > _doneSeconds { eta = el / _doneSeconds * (_duration - _doneSeconds) }
        if _state == "done" { eta = 0 }
        let pct = _duration > 0 ? min(100, _doneSeconds / _duration * 100) : (_state == "done" ? 100 : 0)
        return Snapshot(state: _state, pieces: _pieces, piece: _piece, duration: _duration, doneSeconds: _doneSeconds, segs: _segs,
                        error: _error, note: _note, elapsed: el, eta: eta, percent: pct, json: _jsonPath, md: _mdPath)
    }

    func api() -> [String: Any] {
        let s = snapshot()
        var o: [String: Any] = [
            "id": id, "status": s.state, "file": path, "engine": engine.id, "language": engine.lang,
            "piece": s.piece, "pieces": s.pieces, "duration": r2(s.duration), "elapsed": r2(s.elapsed),
            "percent": r2(s.percent), "text": s.segs.map(\.text).joined(separator: " "),
            "segments": s.segs.map { ["start": r2($0.start), "end": r2($0.end), "text": $0.text] as [String: Any] },
        ]
        if let e = s.eta { o["eta"] = r2(e) }
        if !s.error.isEmpty { o["error"] = s.error }
        if !s.note.isEmpty { o["note"] = s.note }
        if !s.json.isEmpty { o["output"] = ["json": s.json, "md": s.md] }
        return o
    }
    func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // MARK: the work (one job at a time, on its own queue)

    func run() {
        set { _started = Date(); _state = "extracting" }
        Ring.lastMove = nil
        let spec = engine.spec
        guard Catalog.available(spec) else { return fail("\(spec.short) is not available (no key, or not on this Mac)") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vtt-file-\(id)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let raw = tmp.appendingPathComponent("audio.s16")
        if let why = FileJobs.extract(path, to: raw) { return fail(why) }
        let size = (try? FileManager.default.attributesOfItem(atPath: raw.path)[.size] as? Int) ?? 0
        let total = Double(size) / 32000
        guard total > 0.5 else { return fail("no audio found in this file") }
        let len = FileJobs.pieceSeconds(spec)
        let n = Int((total / len).rounded(.up))
        set { _duration = total; _pieces = n; _state = "running" }
        appendLog("file job \(id): \(name), \(Int(total)) s, \(n) pieces of \(Int(len)) s, \(spec.id) \(engine.lang)")
        guard let fh = try? FileHandle(forReadingFrom: raw) else { return fail("the extracted audio cannot be read") }
        defer { try? fh.close() }
        for i in 0..<n {
            if cancelled { return finish("cancelled", "stopped; what was heard is kept") }
            set { _piece = i + 1 }
            let startSec = Double(i) * len
            try? fh.seek(toOffset: UInt64(startSec * 32000))
            let bytes = fh.readData(ofLength: Int(len * 32000))
            let seconds = Double(bytes.count) / 32000
            if seconds < 0.3 { set { _doneSeconds = min(total, startSec + seconds) }; continue }
            let wav = FileJobs.wav(bytes)
            var url: URL?
            if spec.local { let u = tmp.appendingPathComponent("piece\(i).wav"); try? wav.write(to: u); url = u }
            switch FileJobs.piece(spec, wav: wav, url: url, lang: engine.lang, seconds: seconds, job: self) {
            case .failure(let e):
                if cancelled { return finish("cancelled", "stopped; what was heard is kept") }
                return fail("piece \(i + 1) of \(n): \(e.message)")
            case .success(let p):
                var segs = p.segs
                if segs.isEmpty {
                    let t = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { segs = [Seg(start: 0, end: seconds, text: t)] }
                }
                segs = segs.filter { !inventions.contains($0.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) }
                let moved = segs.map { Seg(start: startSec + max(0, $0.start), end: startSec + min(seconds, max($0.end, $0.start)), text: $0.text) }
                set { _segs += moved; _doneSeconds = min(total, startSec + seconds); _note = Ring.lastMove ?? "" }
            }
        }
        finish("done", "")
    }

    func fail(_ why: String) {
        appendLog("file job \(id) failed: \(why)")
        finish("failed", why)
    }

    func finish(_ state: String, _ why: String) {
        set { _error = why; _ended = Date() }
        let s = snapshot()
        if !s.segs.isEmpty {
            let (j, m) = FileJobs.save(self, segs: s.segs, duration: s.duration, complete: state == "done")
            set { _jsonPath = j; _mdPath = m }
            FileJobs.addToHistory(self, segs: s.segs, md: m, complete: state == "done")
        }
        set { _state = state }
    }
}

// MARK: the machinery

enum FileJobs {
    static var jobs: [String: FileJob] = [:]
    static var order: [String] = []
    static let lock = NSLock()
    static let queue = DispatchQueue(label: "vtt.filejobs")

    static func job(_ id: String) -> FileJob? { lock.lock(); defer { lock.unlock() }; return jobs[id] }
    static var busy: Bool { lock.lock(); defer { lock.unlock() }; return jobs.values.contains { !$0.finished } }

    /// make a job and queue it (one at a time)
    @discardableResult
    static func start(path: String, engine: HearEngine) -> FileJob {
        let j = FileJob(path: path, engine: engine)
        lock.lock(); jobs[j.id] = j; order.append(j.id); lock.unlock()
        queue.async { j.run() }
        return j
    }

    /// the window shows it (brought front, History tab)
    static func present(_ j: FileJob) {
        DispatchQueue.main.async {
            stripe.openSettings(tab: SettingsWindow.historyTab)
            stripe.settings?.history.files.watch(j)
        }
    }

    /// the size limit of each engine decides the piece (the free tiers and bodies as measured or documented):
    /// Groq 25 MB = 780 s of 16 kHz mono, used at 300 s; base64 bodies (Cloudflare) 60 s; Google's synchronous calls 55 s
    static func pieceSeconds(_ s: EngineSpec) -> Double {
        switch s.id {
        case "google_v1", "google_chirp": return 55
        case "cloudflare": return 60
        case "parakeet", "whisper": return 180
        default: return 300
        }
    }

    /// which engines give their own timestamps (the others give one segment per piece)
    static func timestamps(_ id: String) -> Bool {
        ["groq_turbo", "groq_v3", "deepgram", "assemblyai", "speechmatics", "elevenlabs", "soniox"].contains(id)
    }

    // MARK: audio

    static let ffmpeg = "/opt/homebrew/bin/ffmpeg"

    /// mono 16 kHz signed 16-bit little-endian PCM into a file; nil when it worked, else the reason
    static func extract(_ path: String, to out: URL) -> String? {
        if FileManager.default.isExecutableFile(atPath: ffmpeg) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpeg)
            p.arguments = ["-nostdin", "-v", "error", "-y", "-i", path, "-vn", "-ac", "1", "-ar", "16000", "-f", "s16le", out.path]
            let errFile = out.deletingLastPathComponent().appendingPathComponent("ffmpeg.err")
            FileManager.default.createFile(atPath: errFile.path, contents: nil)
            if let eh = try? FileHandle(forWritingTo: errFile) { p.standardError = eh }
            p.standardOutput = FileHandle.nullDevice
            do { try p.run() } catch { return "ffmpeg could not start" }
            p.waitUntilExit()
            if p.terminationStatus == 0 { return nil }
            let msg = ((try? String(contentsOf: errFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            appendLog("ffmpeg: \(msg.prefix(300))")
            if !msg.isEmpty && msg.lowercased().contains("does not contain any stream") { return "no audio in this file" }
        }
        // without ffmpeg (or when it refused): the app's own decoder, audio files only
        guard let pcm = Audio.pcm16k(URL(fileURLWithPath: path)), !pcm.isEmpty else {
            return FileManager.default.isExecutableFile(atPath: ffmpeg) ? "ffmpeg could not read this file" : "ffmpeg is missing at \(ffmpeg) and the app cannot read this file itself"
        }
        var d = Data(capacity: pcm.count * 2)
        for f in pcm { var s = Int16(max(-1, min(1, f)) * 32767).littleEndian; d.append(Data(bytes: &s, count: 2)) }
        do { try d.write(to: out) } catch { return "cannot write the temporary audio" }
        return nil
    }

    /// a 16 kHz mono 16-bit WAV around raw PCM
    static func wav(_ pcm: Data) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }

    // MARK: one piece through the engine picked: v14 rule (same engine, 3 s, up to 10 tries on a network error)

    static func piece(_ spec: EngineSpec, wav: Data, url: URL?, lang: String, seconds: Double, job: FileJob) -> Result<Piece, EngineError> {
        var tries = 0
        while true {
            tries += 1
            if job.cancelled { return .failure(EngineError("cancelled")) }
            let r = once(spec, wav: wav, url: url, lang: lang, seconds: seconds)
            switch r {
            case .success:
                Quota.add(spec, seconds: seconds)
                return r
            case .failure(let e):
                appendLog("file job \(job.id): \(spec.id) attempt \(tries) failed: \(e.message)")
                if !Chain.isNetwork(e.message) { return r }
                if tries >= Chain.maxTries { return .failure(EngineError("\(spec.short): no answer after \(Chain.maxTries) tries, 3 s apart")) }
                let said = "\(spec.short): no connection, trying again in 3 s (\(tries) of \(Chain.maxTries))"
                job.setNote(said)
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }

    static func once(_ s: EngineSpec, wav: Data, url: URL?, lang: String, seconds: Double) -> Result<Piece, EngineError> {
        switch s.id {
        case "groq_turbo": return Stamped.groq(model: "whisper-large-v3-turbo", wav, lang: lang)
        case "groq_v3": return Stamped.groq(model: "whisper-large-v3", wav, lang: lang)
        case "deepgram": return Stamped.deepgram(wav, lang: lang)
        case "assemblyai": return Stamped.assembly(wav, lang: lang)
        case "speechmatics": return Stamped.speechmatics(wav, lang: lang)
        case "elevenlabs": return Stamped.elevenlabs(wav, lang: lang)
        case "soniox": return Stamped.soniox(wav, lang: lang)
        case "cloudflare": return Stamped.cloudflare(wav, lang: lang)
        default:
            let r = Chain.once(s, source: url ?? URL(fileURLWithPath: "/dev/null"), wav: wav, lang: lang, seconds: seconds)
            switch r {
            case .success(let t): return .success((t, []))
            case .failure(let e): return .failure(e)
            }
        }
    }

    // MARK: saving

    static func mmss(_ t: Double) -> String {
        let s = Int(t.rounded(.down)); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// next to the source; when that folder cannot be written, in Application Support/transcripts
    static func save(_ job: FileJob, segs: [Seg], duration: Double, complete: Bool) -> (json: String, md: String) {
        let src = URL(fileURLWithPath: job.path)
        var dir = src.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: dir.path) {
            dir = appSupport.appendingPathComponent("transcripts")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let stem = src.deletingPathExtension().lastPathComponent
        let j = dir.appendingPathComponent(stem + ".transcript.json"), m = dir.appendingPathComponent(stem + ".transcript.md")
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let obj: [String: Any] = [
            "source": job.path, "engine": job.engine.id, "language": job.engine.lang, "duration": r2(duration),
            "segments": segs.map { ["start": r2($0.start), "end": r2($0.end), "text": $0.text] as [String: Any] }, "complete": complete,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: j, options: .atomic) }
        let md = segs.map { "\(mmss($0.start)) \($0.text)" }.joined(separator: "\n") + "\n"
        try? md.write(to: m, atomically: true, encoding: .utf8)
        return (j.path, m.path)
    }

    /// the job is listed in History (words only: no audio is kept for a file)
    static func addToHistory(_ job: FileJob, segs: [Seg], md: String, complete: Bool) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let at = Date()
        let id = f.string(from: at) + "-" + String(UUID().uuidString.prefix(4))
        try? FileManager.default.createDirectory(at: History.folder.appendingPathComponent(id), withIntermediateDirectories: true)
        let text = segs.map { "\(mmss($0.start)) \($0.text)" }.joined(separator: "\n")
        let v = Version(at: at, hear: job.engine.title, style: "file: \(job.name)" + (complete ? "" : " (partial)"), lang: job.engine.lang,
                        heard: segs.map(\.text).joined(separator: " "), text: text)
        History.save(Entry(id: id, versions: [v]))
    }

    // MARK: headless (--transcribe-file when the app is not running)

    static func runHeadless(path: String, engine: HearEngine) -> Int32 {
        let j = FileJob(path: path, engine: engine)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { j.run(); done.signal() }
        var shown = 0
        while done.wait(timeout: .now() + 2) == .timedOut {
            let s = j.snapshot()
            shown = printProgress(s, shown)
        }
        let s = j.snapshot()
        _ = printProgress(s, shown)
        if s.state == "done" { print("saved: \(s.json)"); print("saved: \(s.md)"); return 0 }
        print("\(s.state): \(s.error)")
        if !s.json.isEmpty { print("partial: \(s.json)") }
        return 1
    }

    static func printProgress(_ s: FileJob.Snapshot, _ shown: Int) -> Int {
        print(String(format: "%@ piece %d/%d  %.0f%%  elapsed %.0f s", s.state, s.piece, s.pieces, s.percent, s.elapsed))
        for g in s.segs.dropFirst(shown) { print("\(mmss(g.start)) \(g.text)") }
        return s.segs.count
    }

    /// --transcribe-file <path> [engine] [lang]: asked of the running app when there is one (it shows the window), else done here
    static func cli(_ args: [String]) -> Int32 {
        guard let i = args.firstIndex(of: "--transcribe-file"), i + 1 < args.count else { return 2 }
        let rest = Array(args[(i + 1)...]).filter { !$0.hasPrefix("--") }
        guard let p = rest.first else { print("usage: --transcribe-file <path> [engine] [lang]"); return 2 }
        let path = URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { print("no such file: \(path)"); return 2 }
        let engineId = rest.count > 1 ? rest[1] : HearEngine.current.id
        let lang = rest.count > 2 ? rest[2] : "auto"
        guard Catalog.byId(engineId) != nil else { print("unknown engine \(engineId): " + Catalog.all.map(\.id).joined(separator: ", ")); return 2 }
        guard HearEngine.langs.contains(lang) else { print("language is en, hr or auto"); return 2 }
        // the running app first
        let base = "http://127.0.0.1:\(FileAPI.port)"
        var st = URLRequest(url: URL(string: base + "/status")!); st.timeoutInterval = 2
        if send(st, timeout: 2).status == 200 {
            var req = URLRequest(url: URL(string: base + "/transcribe")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Adapters.jsonBody(["path": path, "engine": engineId, "language": lang])
            let r = send(req, timeout: 20)
            guard r.status == 200, let id = json(r.data)["id"] as? String else { print("the app refused: \(json(r.data)["error"] as? String ?? "HTTP \(r.status)")"); return 1 }
            print("job \(id) started in the window")
            var shown = 0
            while true {
                sleep(2)
                var g = URLRequest(url: URL(string: base + "/job/\(id)")!); g.timeoutInterval = 5
                let j = json(send(g, timeout: 5).data)
                guard let state = j["status"] as? String else { print("the app stopped answering"); return 1 }
                let segs = (j["segments"] as? [[String: Any]]) ?? []
                print(String(format: "%@ piece %d/%d  %.0f%%  elapsed %.0f s", state, j["piece"] as? Int ?? 0, j["pieces"] as? Int ?? 0, j["percent"] as? Double ?? 0, j["elapsed"] as? Double ?? 0))
                for s in segs.dropFirst(shown) { print("\(mmss(s["start"] as? Double ?? 0)) \(s["text"] as? String ?? "")") }
                shown = segs.count
                if ["done", "failed", "cancelled"].contains(state) {
                    if let o = j["output"] as? [String: Any] { print("saved: \(o["json"] as? String ?? "")"); print("saved: \(o["md"] as? String ?? "")") }
                    if let e = j["error"] as? String { print("\(state): \(e)") }
                    return state == "done" ? 0 : 1
                }
            }
        }
        return runHeadless(path: path, engine: HearEngine(id: engineId, lang: lang))
    }
}

// MARK: the local API: 127.0.0.1 only

enum FileAPI {
    static let port: UInt16 = 8865
    static var listener: NWListener?

    static func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        guard let l = try? NWListener(using: params) else { appendLog("file API: cannot listen on 127.0.0.1:\(port)"); return }
        l.newConnectionHandler = { c in serve(c) }
        l.stateUpdateHandler = { s in
            if case .failed(let e) = s { appendLog("file API failed: \(e)") }
            if case .ready = s { appendLog("file API on 127.0.0.1:\(port)") }
        }
        l.start(queue: .global())
        listener = l
    }

    static func serve(_ c: NWConnection) {
        c.start(queue: .global())
        pull(c, Data())
    }

    static func pull(_ c: NWConnection, _ have: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, err in
            var buf = have
            if let data { buf.append(data) }
            if err != nil { c.cancel(); return }
            if let (head, body) = split(buf) {
                let len = contentLength(head)
                if body.count >= len || done { respond(c, head: head, body: body.prefix(len)); return }
            }
            if buf.count > 16_000_000 || done { c.cancel(); return }      // v23: /hear takes a WAV body (16 MB = 8 min)
            pull(c, buf)
        }
    }

    static func split(_ d: Data) -> (String, Data)? {
        guard let r = d.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        return (String(data: d[..<r.lowerBound], encoding: .utf8) ?? "", Data(d[r.upperBound...]))
    }

    static func contentLength(_ head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    static func respond(_ c: NWConnection, head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ").map(String.init)
        let method = parts.first ?? "", target = parts.count > 1 ? parts[1] : "/"
        // DNS-rebinding guard: only a request meant for this loopback address is answered
        let host = lines.first { $0.lowercased().hasPrefix("host:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let hostOK = host.hasPrefix("127.0.0.1") || host.hasPrefix("localhost")
        let query = target.components(separatedBy: "?").dropFirst().first ?? ""
        let (code, obj) = hostOK ? route(method, target.components(separatedBy: "?")[0], body, query: query) : (403, ["error": "forbidden host"] as [String: Any])
        let out = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        let status = code == 200 ? "200 OK" : code == 404 ? "404 Not Found" : code == 400 ? "400 Bad Request" : code == 403 ? "403 Forbidden" : "\(code) Error"
        var resp = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(out.count)\r\nConnection: close\r\n\r\n".utf8)
        resp.append(out)
        c.send(content: resp, completion: .contentProcessed { _ in c.cancel() })
    }

    static func route(_ method: String, _ path: String, _ body: Data, query: String = "") -> (Int, [String: Any]) {
        if method == "POST", path == "/hear" { return hearNow(body, query: query) }
        if method == "POST", path == "/engines/select" { return select(body) }
        if method == "GET", path == "/status" {
            return (200, ["app": "Voice to Text (Mantra)", "version": appVersion, "api": 1, "port": Int(port), "busy": FileJobs.busy,
                          "jobs": FileJobs.order.count, "engine": HearEngine.current.id,
                          // v28: the two selectors and the text box Vox would write into
                          "language": HearEngine.current.lang, "text_mode": TextMode.current.rawValue,
                          "modes": ["language": HearEngine.langs, "text": TextMode.allCases.map(\.rawValue)],
                          "target": TextTarget.shared.last?.json ?? [:]])
        }
        if method == "GET", path == "/target" {          // v28: the last text box clicked or focused (never Vox's own)
            return (200, ["target": TextTarget.shared.last?.json ?? [:]])
        }
        if method == "POST", path == "/mode" {           // v28: {"language"?: en|hr|auto, "text"?: style|style_correct|correct}
            let b = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:]
            if let l = b["language"] as? String {
                guard HearEngine.langs.contains(l) else { return (400, ["error": "language is en, hr or auto"]) }
                HearEngine.setLang(l)
            }
            if let m = b["text"] as? String {
                guard let tm = TextMode(rawValue: m) else { return (400, ["error": "text is style, style_correct or correct"]) }
                TextMode.current = tm
            }
            DispatchQueue.main.async { stripe.refresh(); stripe.ready(); stripe.settings?.paintChoices() }
            return (200, ["language": HearEngine.current.lang, "text_mode": TextMode.current.rawValue])
        }
        if method == "POST", path == "/test" {          // v24: TEST mode {"on": bool, "reference"?: "sentence"}
            guard let b = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return (400, ["error": "send {\"on\": true, \"reference\"?: \"the sentence\"}"]) }
            if let on = b["on"] as? Bool { Stats.testOn = on }
            if let r = b["reference"] as? String, !r.trimmingCharacters(in: .whitespaces).isEmpty { Stats.reference = r }
            DispatchQueue.main.async { stripe.settings?.paintTest() }
            return (200, ["test": ["on": Stats.testOn, "reference": Stats.reference]])
        }
        if method == "GET", path == "/engines" {
            let cur = HearEngine.current.id
            let list: [[String: Any]] = Catalog.all.map { s in
                ["id": s.id, "name": Stats.name(s, "en", long: true), "label": Stats.name(s, "en"), "label_hr": Stats.name(s, "hr"),
                 "stats_en": Stats.json(s.id, "en"), "stats_hr": Stats.json(s.id, "hr"), "available": Catalog.available(s), "local": s.local, "paid": s.paid,
                 "selected": s.id == cur, "timestamps": FileJobs.timestamps(s.id) ? "segments" : "piece",
                 "piece_seconds": Int(FileJobs.pieceSeconds(s)),
                 // v26 (for Talk Mode's engine panel): which language uses it, and what is known about its credit,
                 // all from this Mac's own records (no provider is asked)
                 "selected_en": (UserDefaults.standard.string(forKey: "engine_en") ?? "assemblyai") == s.id,
                 "selected_hr": (UserDefaults.standard.string(forKey: "engine_hr") ?? "assemblyai") == s.id,
                 "credit": credit(s)]
            }
            return (200, ["engines": list, "languages": HearEngine.langs, "test": ["on": Stats.testOn, "reference": Stats.reference]])
        }
        if method == "GET", path.hasPrefix("/job/") {
            guard let j = FileJobs.job(String(path.dropFirst(5))) else { return (404, ["error": "no such job"]) }
            return (200, j.api())
        }
        if method == "POST", path == "/transcribe" {
            guard let b = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let p = b["path"] as? String, !p.isEmpty else {
                return (400, ["error": "send {\"path\": \"/full/path\", \"engine\"?: id, \"language\"?: en|hr|auto}"])
            }
            let path = URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return (400, ["error": "no such file: \(path)"]) }
            let eid = (b["engine"] as? String) ?? HearEngine.current.id
            let lang = (b["language"] as? String) ?? "auto"
            guard Catalog.byId(eid) != nil else { return (400, ["error": "unknown engine \(eid): GET /engines"]) }
            guard HearEngine.langs.contains(lang) else { return (400, ["error": "language is en, hr or auto"]) }
            let j = FileJobs.start(path: path, engine: HearEngine(id: eid, lang: lang))
            FileJobs.present(j)
            return (200, ["id": j.id, "status": "started"])
        }
        return (404, ["error": "GET /status, GET /engines, POST /transcribe, GET /job/<id>, POST /hear?lang=en|hr|auto, POST /test, POST /mode, GET /target"])
    }

    /// v23 (Marko, 15.11.2026, for Talk Mode (Mantra): "It needs to use my engine basically, voice to text, the same one I'm
    /// using for transcription"): POST /hear?lang=en|hr|auto with a short WAV as the body. Written down by the engine picked
    /// for that language on the stripe, through the same route as F1 (Frankfurt first, the key ring, the retries), and the
    /// same corrections; no styling, nothing typed, nothing in History. One at a time.
    /// v26: what this Mac knows of an engine's credit: keys in its ring, the free audio of its window (Catalog), what this
    /// Mac used of it (Quota), the price per hour after that, and whether it goes through Frankfurt. Nothing is asked online.
    static func credit(_ s: EngineSpec) -> [String: Any] {
        var c: [String: Any] = ["price_per_hour": s.pricePerHour, "reset": s.reset.rawValue, "frankfurt": Frankfurt.runsThere(s.id)]
        if let p = s.ring { c["keys"] = Keys.entries(p).count }
        if s.freeSeconds.isFinite && s.freeSeconds > 0 {
            let used = Quota.used(s)
            c["free_seconds"] = Int(s.freeSeconds); c["used_seconds"] = Int(used); c["left_seconds"] = Int(max(0, s.freeSeconds - used))
        }
        c["kind"] = s.local ? "this Mac, free" : s.paid ? "paid per use" : s.reset == .oneOff ? "free trial credit" : "free tier (\(s.reset.rawValue))"
        return c
    }

    /// v26 (Marko, 15.11.2026: Talk Mode is "basically ... remote control for our VOX application"): POST /engines/select
    /// {"id", "lang": en|hr} sets the engine of that language, exactly as a card clicked in Settings does (engine_<lang>).
    static func select(_ body: Data) -> (Int, [String: Any]) {
        guard let b = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let id = b["id"] as? String,
              let s = Catalog.byId(id) else { return (400, ["error": "send {\"id\": engine id, \"lang\": \"en\"|\"hr\"}: GET /engines"]) }
        var lang = (b["lang"] as? String) ?? "en"
        if lang == "auto" { lang = "hr" }
        guard lang == "en" || lang == "hr" else { return (400, ["error": "lang is en or hr"]) }
        guard Catalog.available(s) else { return (400, ["error": "\(s.short) has no key or is not installed on this Mac"]) }
        UserDefaults.standard.set(id, forKey: "engine_" + lang)
        appendLog("recognition engine for \(lang.uppercased()): \(s.short) (set from the local API)")
        if id == "parakeet" || id == "whisper" { DispatchQueue.main.async { Ears.warm() } }
        DistributedNotificationCenter.default().postNotificationName(.init("com.mantra.voicetotext.engineChanged"), object: lang, userInfo: nil, deliverImmediately: true)
        return (200, ["ok": true, "id": id, "lang": lang, "label": Stats.name(s, lang)])
    }

    static let hearLock = NSLock()
    static func hearNow(_ body: Data, query: String) -> (Int, [String: Any]) {
        var lang = "en"
        for kv in query.split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2, p[0] == "lang" { lang = p[1] }
        }
        guard HearEngine.langs.contains(lang) else { return (400, ["error": "lang is en, hr or auto"]) }
        guard body.count > 44 else { return (400, ["error": "send the audio (WAV) as the body"]) }
        var id = UserDefaults.standard.string(forKey: "engine_" + (lang == "auto" ? "hr" : lang)) ?? HearEngine.current.id
        if Catalog.byId(id) == nil || (id == "parakeet" && !Ears.serverHere) { id = "assemblyai" }
        let e = HearEngine(id: id, lang: lang)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("api-hear-\(UUID().uuidString).wav")
        do { try body.write(to: url) } catch { return (500, ["error": "cannot write the audio: \(error.localizedDescription)"]) }
        defer { try? FileManager.default.removeItem(at: url) }
        hearLock.lock(); defer { hearLock.unlock() }
        let t0 = Date()
        let r = Hear.run(e, wav: url)
        let usedTitle = Hear.used ?? e.title
        var out: [String: Any] = ["engine": Stats.decorate(hear: usedTitle), "engine_id": id, "route": Hear.route ?? "",
                                  "lang": Hear.lastLang ?? lang, "secs": (Date().timeIntervalSince(t0) * 100).rounded() / 100,
                                  "text_mode": TextMode.current.rawValue]
        switch r {
        case .success(let t): out["ok"] = true; out["text"] = corrected(t)
        case .failure(let err): out["ok"] = false; out["text"] = ""; out["error"] = err.message
        }
        appendLog("api /hear \(e.title): \(out["ok"] as? Bool == true ? "ok" : "failed") via \(out["route"] ?? "")")
        return (200, out)
    }
}
