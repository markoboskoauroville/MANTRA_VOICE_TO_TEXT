// THE ENGINES THAT GIVE TIMESTAMPS (v15, transcribe a file): the same calls as Adapters.swift, through the same key ring, but
// asking for (and reading) the engine's own segments, sentences or words. Times are seconds from the start of the piece;
// FileJob moves them by the piece's start. An engine that answers without times gives an empty list and the job writes one
// segment for the piece. The words are what Adapters.swift would have given.
import Foundation

enum Stamped {
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    /// [{start, end, text}] with the keys named; seconds
    static func segs(_ any: Any?, text: String = "text", start: String = "start", end: String = "end", scale: Double = 1) -> [Seg] {
        guard let list = any as? [[String: Any]] else { return [] }
        var out: [Seg] = []
        for x in list {
            guard let t = x[text] as? String, let s = num(x[start]) else { continue }
            let e = num(x[end]) ?? s
            let tt = trim(t)
            if !tt.isEmpty { out.append(Seg(start: s * scale, end: e * scale, text: tt)) }
        }
        return out
    }

    struct Tok { var s: Double; var e: Double; var t: String; var glue: Bool }

    /// words (or sub-words) into sentences: a sentence ends at . ? ! or after 40 words
    static func sentences(_ toks: [Tok]) -> [Seg] {
        var out: [Seg] = []
        var cur = "", start = 0.0, end = 0.0, count = 0
        func flush() {
            let t = trim(cur)
            if !t.isEmpty { out.append(Seg(start: start, end: end, text: t)) }
            cur = ""; count = 0
        }
        for k in toks {
            if trim(cur).isEmpty { start = k.s }
            if k.glue { cur += k.t } else { cur += (cur.isEmpty ? "" : " ") + trim(k.t); count += 1 }
            end = k.e
            if let last = trim(k.t).last, ".?!".contains(last) { flush() } else if count >= 40 { flush() }
        }
        flush()
        return out
    }

    // MARK: Groq: verbose_json gives segments
    static func groq(model: String, _ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.groq) { key -> Ring.Outcome<Piece> in
            var m = Multipart()
            m.field("model", model); m.field("response_format", "verbose_json"); m.field("temperature", "0")
            m.field("timestamp_granularities[]", "segment")
            if lang != "auto" { m.field("language", lang) }
            let n = Adapters.nameList(); if !n.isEmpty { m.field("prompt", n) }
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let r = Adapters.request("https://api.groq.com/openai/v1/audio/transcriptions", headers: ["Authorization": "Bearer " + key, "Content-Type": m.contentType, "User-Agent": "curl/8"], body: m.finish())
            return .from(call(r)) { (d: Data) -> Piece? in
                let j = json(d)
                guard let t = j["text"] as? String else { return nil }
                return (trim(t), segs(j["segments"]))
            }
        }
    }

    // MARK: Cloudflare: the segments when the model returns them
    static func cloudflare(_ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.cloudflare) { key -> Ring.Outcome<Piece> in
            let parts = key.components(separatedBy: "\n")
            guard parts.count >= 2 else { return .fail(Failure(status: 401, body: "needs account id and token", headers: [:])) }
            var b: [String: Any] = ["audio": wav.base64EncodedString()]
            if lang != "auto" { b["language"] = lang }
            let r = Adapters.request("https://api.cloudflare.com/client/v4/accounts/\(parts[0])/ai/run/@cf/openai/whisper-large-v3-turbo",
                                     headers: ["Authorization": "Bearer " + parts[1], "Content-Type": "application/json"], body: Adapters.jsonBody(b))
            return .from(call(r)) { (d: Data) -> Piece? in
                guard let res = json(d)["result"] as? [String: Any], let t = res["text"] as? String else { return nil }
                return (trim(t), segs(res["segments"]))
            }
        }
    }

    // MARK: Deepgram: utterances, else the sentences of the paragraphs
    static func deepgram(_ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.deepgram) { key -> Ring.Outcome<Piece> in
            var q = "model=nova-3&smart_format=true&utterances=true"
            q += lang == "auto" ? "&language=multi" : "&language=\(lang)"
            for n in Adapters.names().prefix(50) { q += "&keyterm=" + (n.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
            let r = Adapters.request("https://api.deepgram.com/v1/listen?" + q, headers: ["Authorization": "Token " + key, "Content-Type": "audio/wav"], body: wav)
            return .from(call(r)) { (d: Data) -> Piece? in
                let res = json(d)["results"] as? [String: Any]
                let ch = (res?["channels"] as? [[String: Any]])?.first
                let alt = (ch?["alternatives"] as? [[String: Any]])?.first
                guard let t = alt?["transcript"] as? String else { return nil }
                var out = segs(res?["utterances"], text: "transcript")
                if out.isEmpty, let paras = (alt?["paragraphs"] as? [String: Any])?["paragraphs"] as? [[String: Any]] {
                    for p in paras { out += segs(p["sentences"]) }
                }
                return (trim(t), out)
            }
        }
    }

    // MARK: AssemblyAI: its sentences endpoint (milliseconds), after the transcript completes
    static func assembly(_ audio: Data, lang: String) -> Result<Piece, EngineError> {
        let language: [String: Any] = lang == "auto"
            ? ["language_detection": true, "language_detection_options": ["expected_languages": ["en", "hr"]]]
            : ["language_code": lang]
        return Ring.run(.assemblyai) { key -> Ring.Outcome<Piece> in
            let base = Assembly.base
            let up = call(Assembly.request(base + "/upload", key: key, data: audio))
            guard up.status == 200, let url = json(up.data)["upload_url"] as? String else { return .from(up) { _ in nil } }
            let sub = call(Assembly.request(base + "/transcript", key: key, json: language.merging(["audio_url": url]) { a, _ in a }))
            guard sub.status == 200, let id = json(sub.data)["id"] as? String else { return .from(sub) { _ in nil } }
            let until = Date().addingTimeInterval(240)
            while Date() < until {
                usleep(500_000)
                let poll = call(Assembly.request(base + "/transcript/\(id)", key: key), timeout: 30)
                guard poll.status == 200 else { return .from(poll) { _ in nil } }
                let j = json(poll.data)
                switch j["status"] as? String {
                case "completed":
                    let text = trim(j["text"] as? String ?? "")
                    var out: [Seg] = []
                    let sr = call(Assembly.request(base + "/transcript/\(id)/sentences", key: key), timeout: 30)
                    if sr.status == 200 { out = segs(json(sr.data)["sentences"], scale: 0.001) }
                    return .ok((text, out))
                case "error": return .fail(Failure(status: 400, body: "{\"error\": \(String(reflecting: j["error"] as? String ?? "error"))}", headers: [:]))
                default: continue
                }
            }
            return .fail(Failure(status: 504, body: "AssemblyAI did not finish within 4 minutes", headers: [:]))
        }
    }

    // MARK: Speechmatics: json-v2 words with times
    static func speechmatics(_ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.speechmatics) { key -> Ring.Outcome<Piece> in
            let tc: [String: Any] = ["language": lang == "auto" ? "auto" : lang]
            var m = Multipart()
            m.field("config", Adapters.text(Adapters.jsonBody(["type": "transcription", "transcription_config": tc])))
            m.file("data_file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let h = ["Authorization": "Bearer " + key]
            let sub = call(Adapters.request("https://asr.api.speechmatics.com/v2/jobs", headers: h.merging(["Content-Type": m.contentType]) { a, _ in a }, body: m.finish()))
            guard sub.status == 201 || sub.status == 200, let id = json(sub.data)["id"] as? String else { return .from(sub) { _ in nil } }
            let until = Date().addingTimeInterval(240)
            while Date() < until {
                usleep(800_000)
                let st = call(Adapters.request("https://asr.api.speechmatics.com/v2/jobs/\(id)", method: "GET", headers: h), timeout: 30)
                guard st.status == 200 else { return .from(st) { _ in nil } }
                let status = (json(st.data)["job"] as? [String: Any])?["status"] as? String
                if status == "done" {
                    let tr = call(Adapters.request("https://asr.api.speechmatics.com/v2/jobs/\(id)/transcript?format=json-v2", method: "GET", headers: h), timeout: 60)
                    return .from(tr) { (d: Data) -> Piece? in
                        guard let results = json(d)["results"] as? [[String: Any]] else { return nil }
                        var toks: [Tok] = []
                        for r in results {
                            let c = ((r["alternatives"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
                            if c.isEmpty { continue }
                            let s = num(r["start_time"]) ?? (toks.last?.e ?? 0), e = num(r["end_time"]) ?? s
                            let punct = (r["type"] as? String) == "punctuation"
                            toks.append(Tok(s: s, e: e, t: c, glue: punct))
                        }
                        let out = sentences(toks)
                        return (trim(out.map(\.text).joined(separator: " ")), out)
                    }
                }
                if status == "rejected" || status == "deleted" { return .fail(Failure(status: 400, body: "{\"error\": \"job \(status ?? "failed")\"}", headers: [:])) }
            }
            return .fail(Failure(status: 504, body: "Speechmatics did not finish within 4 minutes", headers: [:]))
        }
    }

    // MARK: ElevenLabs Scribe (paid: only when picked): words with times
    static func elevenlabs(_ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.elevenlabs) { key -> Ring.Outcome<Piece> in
            var m = Multipart()
            m.field("model_id", "scribe_v1")
            if lang != "auto" { m.field("language_code", lang) }
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let r = Adapters.request("https://api.elevenlabs.io/v1/speech-to-text", headers: ["xi-api-key": key, "Content-Type": m.contentType], body: m.finish())
            return .from(call(r)) { (d: Data) -> Piece? in
                let j = json(d)
                guard let t = j["text"] as? String else { return nil }
                var toks: [Tok] = []
                for w in (j["words"] as? [[String: Any]]) ?? [] where (w["type"] as? String ?? "word") == "word" {
                    guard let x = w["text"] as? String, let s = num(w["start"]) else { continue }
                    toks.append(Tok(s: s, e: num(w["end"]) ?? s, t: x, glue: false))
                }
                return (trim(t), sentences(toks))
            }
        }
    }

    // MARK: Soniox (paid: only when picked): tokens with milliseconds
    static func soniox(_ wav: Data, lang: String) -> Result<Piece, EngineError> {
        Ring.run(.soniox) { key -> Ring.Outcome<Piece> in
            let auth = ["Authorization": "Bearer " + key]
            var m = Multipart()
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let up = call(Adapters.request("https://api.soniox.com/v1/files", headers: auth.merging(["Content-Type": m.contentType]) { a, _ in a }, body: m.finish()))
            guard up.status == 200 || up.status == 201, let fid = json(up.data)["id"] as? String else { return .from(up) { _ in nil } }
            defer { _ = call(Adapters.request("https://api.soniox.com/v1/files/\(fid)", method: "DELETE", headers: auth), timeout: 20) }
            let hints: [String] = lang == "auto" ? ["en", "hr"] : [lang]
            let sub = call(Adapters.request("https://api.soniox.com/v1/transcriptions", headers: auth.merging(["Content-Type": "application/json"]) { a, _ in a },
                                            body: Adapters.jsonBody(["model": "stt-async-v6", "file_id": fid, "language_hints": hints])))
            guard sub.status == 200 || sub.status == 201, let id = json(sub.data)["id"] as? String else { return .from(sub) { _ in nil } }
            let until = Date().addingTimeInterval(240)
            while Date() < until {
                usleep(600_000)
                let st = call(Adapters.request("https://api.soniox.com/v1/transcriptions/\(id)", method: "GET", headers: auth), timeout: 30)
                guard st.status == 200 else { return .from(st) { _ in nil } }
                let status = json(st.data)["status"] as? String
                if status == "completed" {
                    let tr = call(Adapters.request("https://api.soniox.com/v1/transcriptions/\(id)/transcript", method: "GET", headers: auth), timeout: 60)
                    return .from(tr) { (d: Data) -> Piece? in
                        let j = json(d)
                        guard let t = j["text"] as? String else { return nil }
                        var toks: [Tok] = []
                        for x in (j["tokens"] as? [[String: Any]]) ?? [] {
                            guard let s = x["text"] as? String, let a = num(x["start_ms"]) else { continue }
                            toks.append(Tok(s: a / 1000, e: (num(x["end_ms"]) ?? a) / 1000, t: s, glue: true))
                        }
                        return (trim(t), sentences(toks))
                    }
                }
                if status == "error" { return .fail(Failure(status: 400, body: "{\"error\": \"engine error\"}", headers: [:])) }
            }
            return .fail(Failure(status: 504, body: "Soniox did not finish within 4 minutes", headers: [:]))
        }
    }
}
