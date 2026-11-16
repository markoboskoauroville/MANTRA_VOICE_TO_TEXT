// v20 FRANKFURT (Marko, 15.11.2026: "update my voice to text application so it also goes to Frankfurt and it needs to have all
// the engines it has"). The same route TTT has (TTT's FrankfurtRelay.kt): the 16 kHz WAV goes as one small upload to the
// ttt-relay on chromium-vm (Tailscale 100.102.86.30:8897, repo vm-chromium/ttt-relay), which calls the engine from Frankfurt with
// the key ring, the 3 s x 10 retries and the forward-only rotation; the Mac long-polls the job and shows the relay's own status.
// The cloud engines all run there; Parakeet and Whisper on this Mac are local and never go. The direct path of each engine stays:
// it runs only when the relay does not answer at all (health, or the network to it), said on the status line and in the take's
// route. A relay answer "failed" (every key out, ...) is the engine's answer and is not retried direct. Keys go to the relay
// write-only (POST /keys, merged, never read back), from the Mac's own key store, never printed.
import Foundation

enum Frankfurt {
    static let defaultURL = "http://100.102.86.30:8897"
    static var base: String { UserDefaults.standard.string(forKey: "frankfurtURL") ?? defaultURL }

    /// the switch: on by default, the relay is only used when it answers
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "frankfurt") == nil ? true : UserDefaults.standard.bool(forKey: "frankfurt") }
        set { UserDefaults.standard.set(newValue, forKey: "frankfurt") }
    }

    /// the relay's ring ids for the engines it runs (the ids of Catalog are TTT's)
    static let rings: [String: Provider] = ["groq": .groq, "gemini": .gemini, "deepgram": .deepgram, "assemblyai": .assemblyai,
        "speechmatics": .speechmatics, "soniox": .soniox, "google_v1": .google, "elevenlabs": .elevenlabs,
        "cloudflare": .cloudflare, "google_chirp": .chirp]
    static let whole: Set<String> = ["cloudflare", "google_chirp"]
    static func runsThere(_ id: String) -> Bool { id != "parakeet" && id != "whisper" && Catalog.byId(id) != nil }

    private static var checked = Date.distantPast
    private static var alive = false
    private static var version = 0
    private static let lock = NSLock()

    /// does the relay answer (cached 20 s; a failed check is cached 5 s)
    static func reachable(force: Bool = false) -> Bool {
        lock.lock()
        let age = Date().timeIntervalSince(checked), was = alive, busy = fixing
        lock.unlock()
        // v35: while the Tailscale macro works, or a miss is fresh (the 20 s background check looks again), a take never
        // waits for a health call: it goes direct at once
        if !force && (busy || age < (was ? 20 : 60)) { return was }
        // the lock is not held while the network answers, so a take never waits behind the background check
        let r = call(Adapters.request(base + "/health", method: "GET"), timeout: 4)
        let ok = r.status == 200 && (json(r.data)["ok"] as? Bool) == true
        if !ok { appendLog("frankfurt: /health HTTP \(r.status) \(r.error ?? "")") }
        lock.lock()
        alive = ok; version = (json(r.data)["version"] as? Int) ?? version; checked = Date()
        lock.unlock()
        if !ok && on { fixTailscale() }
        return ok
    }

    /// the 20 s background check
    static func backgroundCheck() { _ = reachable(force: true) }

    // v35 (Marko, 16.11.2026: "if there is no connection to the server, it just triggers the macro to find ... this tailscale on
    // the menu bar and just activate it and click the switch tailscale connect ... forget this 5 times pause"): a miss sends
    // the take direct at once and starts the Macro Recorder skill that brings Tailscale up, in the background, at most once a
    // minute; when it ends /health is asked again and the next take uses Frankfurt if it answers.
    private static var fixing = false
    private static var lastFix = Date.distantPast
    private static let macroskill = NSHomeDirectory() + "/.local/bin/macroskill"

    private static func shell(_ args: [String], timeout: TimeInterval) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: macroskill)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let end = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate(); return (-2, "timed out") }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }

    /// the skill that brings Tailscale up: `tailscale-ensure-up`, else a macro skill whose id says tailscale and up/ensure/connect
    private static func findSkill() -> String? {
        let r = shell(["has", "tailscale ensure up", "--json"], timeout: 20)
        guard let o = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
              let ms = o["matches"] as? [[String: Any]] else { return nil }
        let ids = ms.compactMap { $0["id"] as? String }
        if ids.contains("tailscale-ensure-up") { return "tailscale-ensure-up" }
        return ids.first { $0.contains("tailscale") && ["ensure", "up", "connect", "on"].contains { k in $0.contains(k) } && !$0.contains("exit") }
    }

    static func fixTailscale() {
        lock.lock()
        if fixing || Date().timeIntervalSince(lastFix) < 60 { lock.unlock(); return }
        fixing = true; lastFix = Date()
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            func done(_ t: String, good: Bool) {
                lock.lock(); fixing = false; lock.unlock()
                appendLog("frankfurt: tailscale fix: " + t)
                DispatchQueue.main.async { Toast.show(t, good: good) }
            }
            appendLog("frankfurt: the relay does not answer: looking for the Tailscale macro")
            guard let id = findSkill() else { done("no Tailscale macro", good: false); return }
            appendLog("frankfurt: running macro skill \(id)")
            let r = shell(["run", id], timeout: 120)
            appendLog("frankfurt: macroskill run \(id) exit \(r.code): " + String(r.out.suffix(200)).replacingOccurrences(of: "\n", with: " "))
            Thread.sleep(forTimeInterval: 2)
            lock.lock(); fixing = false; lock.unlock()
            if reachableNoFix() { done("Tailscale was off: switched on", good: true) }
            else { done("Tailscale fix failed: direct", good: false) }
        }
    }

    /// /health once, without starting another fix
    private static func reachableNoFix() -> Bool {
        let r = call(Adapters.request(base + "/health", method: "GET"), timeout: 6)
        let ok = r.status == 200 && (json(r.data)["ok"] as? Bool) == true
        lock.lock(); alive = ok; checked = Date(); version = (json(r.data)["version"] as? Int) ?? version; lock.unlock()
        return ok
    }

    static var relayVersion: Int { version }
    /// the menu bar's badge: FRA while the switch is on and the relay answered last time, else DIR
    static var badge: String { on && alive ? "FRA" : "DIR" }
    /// the line at the top of ⚙ (asks the relay: call off the main thread)
    static func headline() -> (text: String, good: Bool) {
        if !on { return ("Route: DIRECT (the FRANKFURT switch is off)", false) }
        if reachable(force: true) { return ("Route: FRANKFURT ✓ (relay v\(version) answers)", true) }
        return ("Route: DIRECT (the Frankfurt relay does not answer)", false)
    }

    /// one line for ⚙: what the relay is and how many keys it holds
    static func summary() -> String {
        guard reachable(force: true) else { return "relay does not answer: every engine runs direct" }
        let r = call(Adapters.request(base + "/status", method: "GET"), timeout: 6)
        let rs = (json(r.data)["rings"] as? [String: Any]) ?? [:]
        let ready = rs.values.filter { (($0 as? [String: Any])?["keys"] as? Int ?? 0) > 0 }.count
        return "relay answers (version \(version)), keys for \(ready) of \(rings.count) providers"
    }

    // MARK: keys, write only

    /// sends the Mac's keys that the relay may lack: every provider merged (a key it holds is not doubled); Cloudflare and the
    /// service account are one credential each and go only where the relay has none. Only when the keys changed since last time.
    static func syncKeys(force: Bool = false) {
        guard on, reachable() else { return }
        var payload: [String: [String]] = [:]
        let st = call(Adapters.request(base + "/status", method: "GET"), timeout: 8)
        let held = (json(st.data)["rings"] as? [String: Any]) ?? [:]
        for (ring, p) in rings {
            let keys = Keys.get(p)
            if keys.isEmpty { continue }
            if whole.contains(ring) {
                let n = ((held[ring] as? [String: Any])?["keys"] as? Int) ?? 0
                if n == 0, let k = keys.first { payload[ring] = ring == "cloudflare" ? k.components(separatedBy: "\n") : [k] }
            } else { payload[ring] = keys }
        }
        guard !payload.isEmpty else { return }
        let sig = Ring.fingerprint(payload.keys.sorted().map { $0 + ":" + (payload[$0] ?? []).joined(separator: "|") }.joined(separator: ";"))
        if !force && UserDefaults.standard.string(forKey: "frankfurtKeysSig") == sig { return }
        let body = Adapters.jsonBody(["rings": payload, "replace": false])
        let r = call(Adapters.request(base + "/keys", headers: ["Content-Type": "application/json"], body: body), timeout: 20)
        if r.status == 200 { UserDefaults.standard.set(sig, forKey: "frankfurtKeysSig"); appendLog("frankfurt: keys sent to the relay (\(payload.count) providers)") }
        else { appendLog("frankfurt: keys not sent (HTTP \(r.status))") }
    }

    // MARK: one job

    /// nil = the relay did not answer, run the engine direct; otherwise the engine's own answer through Frankfurt
    static func run(_ spec: EngineSpec, wav: Data, lang: String) -> Result<String, EngineError>? {
        guard on, runsThere(spec.id), reachable() else { return nil }
        if lang == "auto" && version < 2 { return nil }                  // the relay learned AUTO in version 2
        var h = ["Content-Type": "audio/wav"]
        let n = Adapters.names()
        if !n.isEmpty { h["X-TTT-Names"] = Adapters.jsonBody2(n).base64EncodedString() }
        let post = call(Adapters.request(base + "/jobs?engine=\(spec.id)&lang=\(lang)", headers: h, body: wav), timeout: 60)
        guard post.status == 200, let id = json(post.data)["id"] as? String else {
            appendLog("frankfurt: job post HTTP \(post.status) \(post.error ?? "")")
            if post.status == 0 || post.status >= 500 { forget(); return nil }
            return .failure(EngineError("Frankfurt: " + ((json(post.data)["error"] as? String) ?? "refused (HTTP \(post.status))")))
        }
        var since = 0
        let deadline = Date().addingTimeInterval(60 + Double(wav.count) / 32000 * 3 + 40 * 11)
        var lastStatus = ""
        while Date() < deadline {
            let r = call(Adapters.request(base + "/jobs/\(id)?since=\(since)&wait=20", method: "GET"), timeout: 40)
            if r.status != 200 {
                if r.status == 0 { forget(); _ = call(Adapters.request(base + "/jobs/\(id)/cancel"), timeout: 4); return nil }
                return .failure(EngineError("Frankfurt: job lost (HTTP \(r.status))"))
            }
            let j = json(r.data)
            since = (j["version"] as? Int) ?? since
            if let s = j["status"] as? String, s != lastStatus { lastStatus = s; Chain.onStatus?(s) }
            switch j["state"] as? String ?? "" {
            case "done":
                let label = (j["key_label"] as? String) ?? (j["key"] as? String) ?? ""
                Hear.route = "Frankfurt" + (label.isEmpty ? "" : " · " + label) + ((j["ms"] as? Int).map { String(format: " · %.1f s there", Double($0) / 1000) } ?? "")
                return .success((j["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            case "failed": return .failure(EngineError("Frankfurt: " + ((j["error"] as? String) ?? "failed")))
            case "cancelled": return .failure(EngineError("Frankfurt: cancelled"))
            default: break
            }
        }
        _ = call(Adapters.request(base + "/jobs/\(id)/cancel"), timeout: 4)
        forget()
        return .failure(EngineError("Frankfurt: no result in time"))
    }

    private static func forget() { lock.lock(); alive = false; checked = Date(); lock.unlock(); fixTailscale() }
}

extension Adapters {
    static func jsonBody2(_ a: [String]) -> Data { (try? JSONSerialization.data(withJSONObject: a)) ?? Data("[]".utf8) }
}
