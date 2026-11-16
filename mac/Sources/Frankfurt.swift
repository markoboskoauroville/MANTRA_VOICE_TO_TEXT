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
        let age = Date().timeIntervalSince(checked), was = alive
        lock.unlock()
        if !force && age < (was ? 20 : 5) { return was }
        // v34: the lock is not held while the network answers, so a take never waits behind the background check
        let r = call(Adapters.request(base + "/health", method: "GET"), timeout: 4)
        let ok = r.status == 200 && (json(r.data)["ok"] as? Bool) == true
        if !ok { appendLog("frankfurt: /health HTTP \(r.status) \(r.error ?? "")") }
        lock.lock()
        alive = ok; version = (json(r.data)["version"] as? Int) ?? version; checked = Date()
        if !ok { if skipLeft == 0 { skipLeft = skipCount } } else { skipLeft = 0 }
        lock.unlock()
        return ok
    }

    // v34 (Marko, 16.11.2026: "if Frankfurt is not answering, then you need to do next few transcriptions, let's say 5 of
    // them, without Frankfurt, without checking, going normal route, direct route, and then try again. not check every
    // time"): after a miss the next 5 takes go direct with no call to the relay at all, then one try again
    static let skipCount = 5
    private static var skipLeft = 0
    /// set while the current take is skipped: "direct (Frankfurt skipped, n of 5)"
    static var skipNote: String?
    /// the background 20 s check: not while takes are being skipped (nothing is asked of the relay then)
    static func backgroundCheck() {
        lock.lock(); let skipping = skipLeft > 0; lock.unlock()
        if !skipping { _ = reachable(force: true) }
    }
    private static func takeSkip() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard skipLeft > 0 else { return nil }
        skipLeft -= 1
        return skipCount - skipLeft
    }
    private static func startSkip() { lock.lock(); skipLeft = skipCount; lock.unlock() }

    static var skipping: Bool { lock.lock(); defer { lock.unlock() }; return skipLeft > 0 }
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
        guard on, !Frankfurt.skipping, reachable() else { return }
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
        skipNote = nil
        guard on, runsThere(spec.id) else { return nil }
        if let n = takeSkip() {
            skipNote = "direct (Frankfurt skipped, \(n) of \(skipCount))"
            appendLog("frankfurt: " + (skipNote ?? ""))
            return nil
        }
        guard reachable() else { return nil }
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
        startSkip()
        return .failure(EngineError("Frankfurt: no result in time"))
    }

    private static func forget() { lock.lock(); alive = false; checked = Date(); skipLeft = skipCount; lock.unlock() }
}

extension Adapters {
    static func jsonBody2(_ a: [String]) -> Data { (try? JSONSerialization.data(withJSONObject: a)) ?? Data("[]".utf8) }
}
