// ONE ADAPTER PER ENGINE (ported from TTT's EngineAdapters.kt, 10.11.2026): a 16 kHz mono WAV in, the words out, through the
// key ring (Ring.run: numbered keys, a rotation that wraps to key 1 and never turns off). Every call goes through `call`,
// which gives the status, the body and the headers to the classifier; a key is never in a message, a log or an error.
import Foundation
import Security

struct Multipart {
    let boundary = "vtt-" + UUID().uuidString
    private var body = Data()
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    mutating func field(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }
    mutating func file(_ name: String, filename: String, mime: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data); body.append(Data("\r\n".utf8))
    }
    func finish() -> Data { var b = body; b.append(Data("--\(boundary)--\r\n".utf8)); return b }
}

enum Adapters {
    static func names() -> [String] {
        Prefs.names.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func nameList() -> String { String(names().joined(separator: ", ").prefix(600)) }

    static func request(_ url: String, method: String = "POST", headers: [String: String] = [:], body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = body
        return r
    }

    static func jsonBody(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data() }

    static func text(_ d: Data) -> String { String(data: d, encoding: .utf8) ?? "" }

    /// the words of a Google recognize answer: every result's first alternative
    static func googleWords(_ d: Data) -> String {
        let rs = (json(d)["results"] as? [[String: Any]]) ?? []
        return rs.compactMap { ($0["alternatives"] as? [[String: Any]])?.first?["transcript"] as? String }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Groq (OpenAI-compatible Whisper); the one key of this job, the ring moves to the next on a quota or refusal
    static func groq(model: String, _ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.groq) { key -> Ring.Outcome<String> in
            var m = Multipart()
            m.field("model", model); m.field("response_format", "json"); m.field("temperature", "0")
            if lang != "auto" { m.field("language", lang) }
            let n = nameList(); if !n.isEmpty { m.field("prompt", n) }
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let r = request("https://api.groq.com/openai/v1/audio/transcriptions", headers: ["Authorization": "Bearer " + key, "Content-Type": m.contentType, "User-Agent": "curl/8"], body: m.finish())
            return .from(call(r)) { json($0)["text"] as? String }
        }
    }

    // MARK: Cloudflare Workers AI (the key is "account id \n token")
    static func cloudflare(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.cloudflare) { key -> Ring.Outcome<String> in
            let parts = key.components(separatedBy: "\n")
            guard parts.count >= 2 else { return .fail(Failure(status: 401, body: "needs account id and token", headers: [:])) }
            var b: [String: Any] = ["audio": wav.base64EncodedString()]
            if lang != "auto" { b["language"] = lang }
            let r = request("https://api.cloudflare.com/client/v4/accounts/\(parts[0])/ai/run/@cf/openai/whisper-large-v3-turbo",
                            headers: ["Authorization": "Bearer " + parts[1], "Content-Type": "application/json"], body: jsonBody(b))
            return .from(call(r)) { (json($0)["result"] as? [String: Any])?["text"] as? String }
        }
    }

    // MARK: Gemini Flash-Lite audio (a prompt, the clip inline)
    static func gemini(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.gemini) { key -> Ring.Outcome<String> in
            let l = lang == "en" ? "English" : lang == "hr" ? "Croatian" : "Croatian or English (write each part in the language it is in)"
            let n = nameList()
            let prompt = "Transcribe this speech exactly and verbatim in \(l), with punctuation, no commentary." + (n.isEmpty ? "" : " Names that may occur: \(n).")
            let b: [String: Any] = ["contents": [["parts": [["text": prompt], ["inline_data": ["mime_type": "audio/wav", "data": wav.base64EncodedString()]]]]]]
            let r = request("https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent",
                            headers: ["x-goog-api-key": key, "Content-Type": "application/json"], body: jsonBody(b))
            return .from(call(r)) { d in
                let c = ((json(d)["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
                return (c?.first?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    // MARK: Deepgram Nova-3 (the audio itself as the body)
    static func deepgram(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.deepgram) { key -> Ring.Outcome<String> in
            var q = "model=nova-3&smart_format=true"
            q += lang == "auto" ? "&detect_language=en&detect_language=hr" : "&language=\(lang)"
            for n in names().prefix(50) { q += "&keyterm=" + (n.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
            let r = request("https://api.deepgram.com/v1/listen?" + q, headers: ["Authorization": "Token " + key, "Content-Type": "audio/wav"], body: wav)
            return .from(call(r)) { d in
                let ch = ((json(d)["results"] as? [String: Any])?["channels"] as? [[String: Any]])?.first
                return ((ch?["alternatives"] as? [[String: Any]])?.first?["transcript"] as? String)
            }
        }
    }

    // MARK: ElevenLabs Scribe (paid: only when picked)
    static func elevenlabs(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.elevenlabs) { key -> Ring.Outcome<String> in
            var m = Multipart()
            m.field("model_id", "scribe_v1")
            if lang != "auto" { m.field("language_code", lang) }
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let r = request("https://api.elevenlabs.io/v1/speech-to-text", headers: ["xi-api-key": key, "Content-Type": m.contentType], body: m.finish())
            return .from(call(r)) { json($0)["text"] as? String }
        }
    }

    // MARK: Google Speech v1 (clips under one minute only)
    static func googleV1(_ wav: Data, lang: String, seconds: Double) -> Result<String, EngineError> {
        if seconds > 58 { return .failure(EngineError("Google Speech v1 takes clips under 1 minute")) }
        return Ring.run(.google) { key -> Ring.Outcome<String> in
            var cfg: [String: Any] = ["encoding": "LINEAR16", "sampleRateHertz": 16000, "enableAutomaticPunctuation": true,
                                      "languageCode": lang == "en" ? "en-US" : "hr-HR"]
            if lang == "auto" { cfg["alternativeLanguageCodes"] = ["en-US"] }
            let n = names(); if !n.isEmpty { cfg["speechContexts"] = [["phrases": Array(n.prefix(100))]] }
            let b: [String: Any] = ["config": cfg, "audio": ["content": Data(wav.dropFirst(44)).base64EncodedString()]]
            let r = request("https://speech.googleapis.com/v1/speech:recognize", headers: ["x-goog-api-key": key, "Content-Type": "application/json"], body: jsonBody(b))
            return .from(call(r)) { googleWords($0) }
        }
    }

    // MARK: Google Chirp 3 on the v2 API (a service account: OAuth by a signed token)
    static func chirp(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.chirp) { key -> Ring.Outcome<String> in
            let project = ((try? JSONSerialization.jsonObject(with: Data(key.utf8))) as? [String: Any])?["project_id"] as? String ?? ""
            guard !project.isEmpty else { return .fail(Failure(status: 401, body: "no project id in the service account", headers: [:])) }
            switch Chirp.token(key) {
            case .failure(let e): return .fail(Failure(status: e.message.contains("network") ? 0 : 401, body: e.message, headers: [:]))
            case .success(let tok):
                let codes = lang == "en" ? ["en-US"] : lang == "hr" ? ["hr-HR"] : ["auto"]
                let b: [String: Any] = ["config": ["autoDecodingConfig": [String: Any](), "languageCodes": codes, "model": "chirp_3"], "content": wav.base64EncodedString()]
                let r = request("https://us-speech.googleapis.com/v2/projects/\(project)/locations/us/recognizers/_:recognize",
                                headers: ["Authorization": "Bearer " + tok, "Content-Type": "application/json"], body: jsonBody(b))
                return .from(call(r)) { googleWords($0) }
            }
        }
    }

    // MARK: Speechmatics (upload, poll, fetch: one key for the whole job)
    static func speechmatics(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.speechmatics) { key -> Ring.Outcome<String> in
            var tc: [String: Any] = ["language": lang == "auto" ? "auto" : lang]
            if lang == "auto" { tc["language_identification_config"] = ["expected_languages": ["en", "hr"]] }
            var m = Multipart()
            m.field("config", text(jsonBody(["type": "transcription", "transcription_config": tc])))
            m.file("data_file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let h = ["Authorization": "Bearer " + key]
            let sub = call(request("https://asr.api.speechmatics.com/v2/jobs", headers: h.merging(["Content-Type": m.contentType]) { a, _ in a }, body: m.finish()))
            guard sub.status == 201 || sub.status == 200, let id = json(sub.data)["id"] as? String else { return .from(sub) { _ in nil } }
            let until = Date().addingTimeInterval(120)
            while Date() < until {
                usleep(800_000)
                let st = call(request("https://asr.api.speechmatics.com/v2/jobs/\(id)", method: "GET", headers: h), timeout: 30)
                guard st.status == 200 else { return .from(st) { _ in nil } }
                let status = (json(st.data)["job"] as? [String: Any])?["status"] as? String
                if status == "done" {
                    let tr = call(request("https://asr.api.speechmatics.com/v2/jobs/\(id)/transcript?format=txt", method: "GET", headers: h), timeout: 30)
                    return .from(tr) { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                if status == "rejected" || status == "deleted" { return .fail(Failure(status: 400, body: "{\"error\": \"job \(status ?? "failed")\"}", headers: [:])) }
            }
            return .fail(Failure(status: 504, body: "Speechmatics did not finish within 2 minutes", headers: [:]))
        }
    }

    // MARK: Soniox (paid: only when picked): file, transcription, poll, text, the file deleted after
    static func soniox(_ wav: Data, lang: String) -> Result<String, EngineError> {
        Ring.run(.soniox) { key -> Ring.Outcome<String> in
            let auth = ["Authorization": "Bearer " + key]
            var m = Multipart()
            m.file("file", filename: "clip.wav", mime: "audio/wav", data: wav)
            let up = call(request("https://api.soniox.com/v1/files", headers: auth.merging(["Content-Type": m.contentType]) { a, _ in a }, body: m.finish()))
            guard up.status == 200 || up.status == 201, let fid = json(up.data)["id"] as? String else { return .from(up) { _ in nil } }
            defer { _ = call(request("https://api.soniox.com/v1/files/\(fid)", method: "DELETE", headers: auth), timeout: 20) }
            let hints: [String] = lang == "auto" ? ["en", "hr"] : [lang]
            let sub = call(request("https://api.soniox.com/v1/transcriptions", headers: auth.merging(["Content-Type": "application/json"]) { a, _ in a },
                                   body: jsonBody(["model": "stt-async-v6", "file_id": fid, "language_hints": hints])))
            guard sub.status == 200 || sub.status == 201, let id = json(sub.data)["id"] as? String else { return .from(sub) { _ in nil } }
            let until = Date().addingTimeInterval(120)
            while Date() < until {
                usleep(600_000)
                let st = call(request("https://api.soniox.com/v1/transcriptions/\(id)", method: "GET", headers: auth), timeout: 30)
                guard st.status == 200 else { return .from(st) { _ in nil } }
                let status = json(st.data)["status"] as? String
                if status == "completed" {
                    let tr = call(request("https://api.soniox.com/v1/transcriptions/\(id)/transcript", method: "GET", headers: auth), timeout: 30)
                    return .from(tr) { json($0)["text"] as? String }
                }
                if status == "error" { return .fail(Failure(status: 400, body: "{\"error\": \"engine error\"}", headers: [:])) }
            }
            return .fail(Failure(status: 504, body: "Soniox did not finish within 2 minutes", headers: [:]))
        }
    }
}

// MARK: the service account's access token: a JWT signed RS256 with the account's private key, exchanged at Google, cached 50 min

enum Chirp {
    static var cached: (token: String, until: Date)?

    static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    // PKCS#8 -> the PKCS#1 RSAPrivateKey inside it (Security's RSA import wants the inner one)
    static func pkcs1(fromPKCS8 d: [UInt8]) -> [UInt8]? {
        var i = 0
        func len() -> Int? {
            guard i < d.count else { return nil }
            let b = Int(d[i]); i += 1
            if b < 0x80 { return b }
            let n = b & 0x7f
            guard n > 0, n <= 4, i + n <= d.count else { return nil }
            var v = 0; for _ in 0..<n { v = (v << 8) | Int(d[i]); i += 1 }
            return v
        }
        guard i < d.count, d[i] == 0x30 else { return nil }; i += 1; guard len() != nil else { return nil }
        guard i < d.count, d[i] == 0x02 else { return nil }; i += 1; guard let vl = len() else { return nil }; i += vl          // version
        guard i < d.count, d[i] == 0x30 else { return nil }; i += 1; guard let al = len() else { return nil }; i += al          // algorithm
        guard i < d.count, d[i] == 0x04 else { return nil }; i += 1; guard let ol = len(), i + ol <= d.count else { return nil }
        return Array(d[i..<(i + ol)])
    }

    static func sign(_ message: Data, pem: String) -> Data? {
        let body = pem.replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "").replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let der = Data(base64Encoded: body), let inner = pkcs1(fromPKCS8: [UInt8](der)) else { return nil }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(inner) as CFData, attrs as CFDictionary, &err),
              let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &err) else { return nil }
        return sig as Data
    }

    static func token(_ account: String) -> Result<String, EngineError> {
        if let c = cached, c.until > Date() { return .success(c.token) }
        guard let sa = (try? JSONSerialization.jsonObject(with: Data(account.utf8))) as? [String: Any],
              let email = sa["client_email"] as? String, let pem = sa["private_key"] as? String else { return .failure(EngineError("not a service account")) }
        let uri = sa["token_uri"] as? String ?? "https://oauth2.googleapis.com/token"
        let now = Int(Date().timeIntervalSince1970)
        let head = b64url(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
        let claims = b64url(Adapters.jsonBody(["iss": email, "scope": "https://www.googleapis.com/auth/cloud-platform", "aud": uri, "iat": now, "exp": now + 3000]))
        guard let sig = sign(Data("\(head).\(claims)".utf8), pem: pem) else { return .failure(EngineError("the service account's private key could not sign")) }
        let form = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(head).\(claims).\(b64url(sig))"
        let r = call(Adapters.request(uri, headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data(form.utf8)), timeout: 20)
        if r.status == 0 { return .failure(EngineError("network: Google could not be reached")) }
        guard r.status == 200, let tok = json(r.data)["access_token"] as? String else { return .failure(EngineError("Google refused the service account (HTTP \(r.status))")) }
        cached = (tok, Date().addingTimeInterval(50 * 60))
        return .success(tok)
    }
}
