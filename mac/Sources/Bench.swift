// v17 (Marko, 14.11.2026: "test the engine as we already do on my phone for accuracy. Invent 12 sentences ... next to each
// engine in parentheses put the percentage of correctness"). TTT's method (docs/benchmark-2026-11-09.md): accuracy = 100 x
// (1 - WER), lower-cased, no punctuation, per clip, averaged; free engines only (Soniox and ElevenLabs are paid and sit
// out). The clips are twelve invented sentences spoken by the voice API (POST :8837/render, never a second TTS), kept in
// <app support>/bench/NN.mp3 so a rerun costs no speech; the engines get the files straight through their own adapters,
// nothing is played on the speakers or heard by the microphone. Results go to <app support>/benchmark.json, which Scores.get
// reads before anything else, so the next run replaces the figures.
import Foundation

enum Bench {
    static let sentences = [
        "Marko is flying from Chennai to Zagreb on the twenty third of December at six forty five in the morning.",
        "We are meeting at Auroville's Matrimandir at half past four to record the drums for the new album.",
        "Please export the timeline from DaVinci Resolve in H.265 at ten megabits per second and upload it to the Drive folder.",
        "Speechify reads the lesson aloud while the student follows the highlighted words on the screen.",
        "The invoice number is four hundred and seventy two, and the total comes to one thousand two hundred and fifty euros.",
        "Natasha practises the seven eight rhythm every morning, starting slowly and then raising the tempo by ten beats per minute.",
        "Can you send Damjan the final version before noon, and tell him the captions are on the upper chest?",
        "Whisper large version three runs on Groq in under a second, which makes it ideal for dictation.",
        "The phone battery dropped to eighteen percent, so I plugged it into the charger on the desk.",
        "Yesterday it rained heavily in Pondicherry, but the concert on the beach still started exactly at seven.",
        "Mantreshwar teaches percussion at the academy on Tuesdays and Thursdays, and the free lesson is open to everyone.",
        "After we finished mixing the concert on the Allen and Heath console, we copied the recordings from the SD card to the laptop, checked every channel for clipping, wrote down the notes for the next soundcheck, and then went to sleep because it was already past three in the morning.",
    ]
    static var dir: URL { appSupport.appendingPathComponent("bench") }
    static var file: URL { appSupport.appendingPathComponent("benchmark.json") }
    static var running = false

    /// the stored result: {"date","lang","clips","results":{id:{"pct","seconds"}},"failed":{id:msg},"skipped":{id:why}}
    static func stored() -> [String: Any]? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    /// the measured percentage of one engine in English, nil when no run measured it
    static func pct(_ id: String) -> Int? {
        ((stored()?["results"] as? [String: Any])?[id] as? [String: Any])?["pct"] as? Int
    }

    static func clip(_ i: Int) -> URL { dir.appendingPathComponent(String(format: "%02d.mp3", i + 1)) }

    /// make the missing clips with the voice API; false with a reason when it cannot
    static func render(_ say: (String) -> Void) -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: sentences, options: [.prettyPrinted]) { try? d.write(to: dir.appendingPathComponent("sentences.json")) }
        for (i, t) in sentences.enumerated() where !FileManager.default.fileExists(atPath: clip(i).path) {
            say("making sentence \(i + 1) of 12 with the voice")
            var done = false
            for _ in 0..<6 where !done {
                var req = URLRequest(url: URL(string: "http://127.0.0.1:8837/render")!, timeoutInterval: 120)
                req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": t])
                let sem = DispatchSemaphore(value: 0); var out: Data?
                URLSession.shared.dataTask(with: req) { d, _, _ in out = d; sem.signal() }.resume(); sem.wait()
                if let out, let j = try? JSONSerialization.jsonObject(with: out) as? [String: Any], j["ok"] as? Bool == true,
                   let b = j["audio"] as? String, let a = Data(base64Encoded: b) { try? a.write(to: clip(i)); done = true }
                else { Thread.sleep(forTimeInterval: 4) }
            }
            if !done { return "the voice (127.0.0.1:8837) did not make sentence \(i + 1)" }
        }
        return nil
    }

    /// the whole run; blocking, call off the main thread. `say` gets the progress words.
    static func run(say: @escaping (String) -> Void) -> String {
        if running { return "a benchmark is already running" }
        running = true; defer { running = false }
        if let why = render(say) { return "FAILED: " + why }
        var results: [String: Any] = [:], failed: [String: String] = [:], skipped: [String: String] = [:]
        for s in Catalog.all {
            if s.paid { skipped[s.id] = "paid, only when picked"; continue }
            if !Catalog.available(s) { skipped[s.id] = s.ring == nil ? "not on this Mac" : "no working key"; continue }
            var scores: [Int] = [], secs = 0.0, lastErr = ""
            clips: for i in 0..<sentences.count {
                say("\(s.short): sentence \(i + 1) of 12")
                guard let pcm = Audio.pcm16k(clip(i)) else { lastErr = "clip unreadable"; break }
                let t0 = Date()
                switch Chain.once(s, source: clip(i), wav: Ears.wav16(pcm), lang: "en", seconds: Double(pcm.count) / 16000) {
                case .success(let t): scores.append(Scores.accuracy(reference: sentences[i], heard: t)); secs += Date().timeIntervalSince(t0)
                case .failure(let e):
                    lastErr = e.message; scores.append(-1)
                    if scores.filter({ $0 < 0 }).count >= 2 && scores.filter({ $0 >= 0 }).isEmpty { break clips }
                }
            }
            let ok = scores.filter { $0 >= 0 }
            if ok.count < sentences.count - 2 { failed[s.id] = lastErr.isEmpty ? "too few answers" : lastErr; continue }
            results[s.id] = ["pct": Int((Double(ok.reduce(0, +)) / Double(ok.count)).rounded()), "seconds": (secs / Double(ok.count) * 100).rounded() / 100, "clips": ok.count, "per": scores]
        }
        let f = DateFormatter(); f.dateFormat = "d.M.yyyy"
        let doc: [String: Any] = ["date": f.string(from: Date()), "lang": "en", "clips": sentences.count, "voice": "Beatrice (Speechify) via :8837/render",
                                  "results": results, "failed": failed, "skipped": skipped]
        if let d = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: file) }
        var lines = ["engine,pct,seconds"]
        for (id, v) in results.sorted(by: { (($0.value as! [String: Any])["pct"] as! Int) > (($1.value as! [String: Any])["pct"] as! Int) }) {
            let m = v as! [String: Any]; lines.append("\(id),\(m["pct"]!),\(m["seconds"]!)")
        }
        for (id, w) in failed.sorted(by: { $0.key < $1.key }) { lines.append("\(id),FAILED,\(w)") }
        for (id, w) in skipped.sorted(by: { $0.key < $1.key }) { lines.append("\(id),SKIPPED,\(w)") }
        return lines.joined(separator: "\n")
    }
}
