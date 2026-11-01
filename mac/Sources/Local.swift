// v3: ONE APP (Marko, 1.11.2026: "Please unite these two apps. So public one is also my local one and everything is
// developed under one hood."). Transcribe Voice to Text RT (MARKO_TRANSCRIBE, his own) and Voice to Text (Mantra) (the
// public one) were the same code drifted apart. Everything that was only his lives here, and turns on only where it finds
// his setup, so the public download behaves as before:
//   · Ears: the MANTRA_VOICE ears on :8837 (MLX Whisper, warm) when ~/Developer/MANTRA_VOICE is on the Mac, else built in
//   · the move of his settings, keys and history from Transcribe Voice to Text RT, once
// and, for everybody, the duck (Marko, 1.11.2026: "reduce audio output while it's listening to the microphone to 6%.
// When listening is done, it brings it back to old value").
import AppKit
import CoreAudio
import AudioToolbox

// MARK: which Whisper hears

enum Ears: String {
    case builtIn, server
    static let voiceDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/MANTRA_VOICE")
    /// the MANTRA_VOICE ears are on this Mac (Marko's): the choice is offered, and it is the default
    static var serverHere: Bool { FileManager.default.fileExists(atPath: voiceDir.appendingPathComponent("voiced.py").path) }
    static var current: Ears {
        get {
            guard serverHere else { return .builtIn }
            return Ears(rawValue: UserDefaults.standard.string(forKey: "ears") ?? "") ?? .server
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ears") }
    }
    var title: String { self == .server ? "MANTRA_VOICE ears (:8837, MLX)" : "built in (whisper.cpp, this app)" }

    /// a take through the ears server: 16 kHz mono 16-bit WAV, never leaves the Mac
    static func server(_ source: URL, lang: String) -> Result<String, EngineError> {
        guard let pcm = Audio.pcm16k(source), pcm.count > 8000 else { return .failure(EngineError("nothing recorded")) }
        if !VoiceServer.up() { VoiceServer.ensure() }
        var req = URLRequest(url: URL(string: serverURL("voice", 8837) + "/hear?lang=\(lang)")!)
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.httpBody = wav16(pcm)
        let r = send(req)
        if r.status == 0 { return .failure(EngineError("the voice did not come up: ~/.voice/voiced.log")) }
        let j = json(r.data)
        Hear.lastLang = j["lang"] as? String
        if let t = j["text"] as? String { return .success(t) }
        return .failure(EngineError("Whisper: \(j["error"] as? String ?? "HTTP \(r.status)")"))
    }

    static func wav16(_ pcm: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(pcm.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        var s = pcm.map { Int16(max(-1, min(1, $0)) * 32767).littleEndian }
        d.append(Data(bytes: &s, count: s.count * 2))
        return d
    }

    /// when a take starts: the chosen Whisper gets ready
    static func warm() { current == .server ? Warm.ears() : Whisper.warm() }
}

// the local servers, found through the port registry (MANTRA_MANIFEST modules/ports.md)
func serverURL(_ name: String, _ fallback: Int) -> String {
    let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mantra-ports.json")
    if let d = try? Data(contentsOf: file), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
       let e = j[name] as? [String: Any], let url = e["url"] as? String { return url }
    return "http://127.0.0.1:\(fallback)"
}

// THE VOICE STARTS BY ITSELF (request 13 of Transcribe RT, Marko 18.10.2026: "When the application is running, it should
// enable my engines"): MANTRA_VOICE's voiced.py, detached, the way the star's Voices row does. Only with Ears = server.
enum VoiceServer {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let python = home + "/.pyenv/versions/3.10.14/bin/python3"
    static let dir = home + "/Developer/MANTRA_VOICE"

    static func up() -> Bool {
        send(URLRequest(url: URL(string: serverURL("voice", 8837) + "/health")!), timeout: 1.5).status == 200
    }

    static func running() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "MANTRA_VOICE/voiced.py"]
        p.standardOutput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// up already, or started and waited for (up to 60 s); a voiced still shutting down is waited out. Off the main thread.
    @discardableResult static func ensure() -> Bool {
        guard Ears.current == .server else { return false }
        var started = false
        for _ in 0..<120 {
            if up() { return true }
            if !started && !running() {
                guard FileManager.default.isExecutableFile(atPath: python), FileManager.default.fileExists(atPath: dir + "/voiced.py") else {
                    appendLog("voice: \(python) or \(dir)/voiced.py missing"); return false
                }
                try? FileManager.default.createDirectory(atPath: home + "/.voice", withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                // v7 (1.11.2026): through its launchd agent when there is one, never a second nohup copy beside it. Marko: "Two voice
                // engines are running at the same time, and they are killing each other." A nohup voiced held :8837 while launchd's
                // copy restarted and fought it for the port.
                let agent = home + "/Library/LaunchAgents/com.mantra.voiced.plist"
                if FileManager.default.fileExists(atPath: agent) {
                    let gui = "gui/\(getuid())"
                    p.arguments = ["-c", "launchctl kickstart \(gui)/com.mantra.voiced >/dev/null 2>&1 || launchctl bootstrap \(gui) '\(agent)' >/dev/null 2>&1"]
                } else {
                    p.arguments = ["-c", "exec </dev/null >/dev/null 2>&1; cd '\(dir)' && nohup '\(python)' '\(dir)/voiced.py' >> '\(home)/.voice/voiced.log' 2>&1 &"]
                }
                try? p.run(); p.waitUntilExit()
                appendLog("voice: started voiced.py" + (FileManager.default.fileExists(atPath: agent) ? " (launchd com.mantra.voiced)" : ""))
                started = true
            }
            usleep(500_000)
        }
        appendLog("voice: did not answer within 60 s")
        return false
    }
}

// warm (Transcribe RT v28): "warm" on the ears' own socket the moment a take starts. Fire and forget.
enum Warm {
    static func ears() {
        DispatchQueue.global(qos: .utility).async {
            let path = NSHomeDirectory() + "/.voice/ears.sock"
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            defer { close(fd) }
            var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
            let cap = MemoryLayout.size(ofValue: addr.sun_path)
            guard path.utf8.count < cap else { return }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                for (i, b) in path.utf8.enumerated() { raw[i] = b }
                raw[path.utf8.count] = 0
            }
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard ok == 0 else { return }
            _ = "warm\n".withCString { Darwin.send(fd, $0, 5, 0) }
            var buf = [UInt8](repeating: 0, count: 64)
            _ = recv(fd, &buf, buf.count, 0)
        }
    }
}

// MARK: the move from Transcribe Voice to Text RT, once

enum Merge {
    static let oldDomain = "com.mantra.markotranscribe"
    static let oldFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Marko Transcribe")

    static func once() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "mergedFromRT") else { return }
        d.set(true, forKey: "mergedFromRT")
        guard FileManager.default.fileExists(atPath: oldFolder.path) else { return }
        // his settings (hotkey, style, sliders, the microphone, TOP …): every one he had
        if let old = UserDefaults(suiteName: oldDomain)?.persistentDomain(forName: oldDomain) {
            for (k, v) in old where k != "mergedFromRT" && !k.hasPrefix("NS") { d.set(v, forKey: k) }
        }
        // keys, key ring, history: what the new folder does not have yet
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        for name in ["keys.json", "ring.json"] {
            let src = oldFolder.appendingPathComponent(name), dst = appSupport.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
        }
        let oldHistory = oldFolder.appendingPathComponent("history"), newHistory = appSupport.appendingPathComponent("history")
        try? fm.createDirectory(at: newHistory, withIntermediateDirectories: true)
        for item in (try? fm.contentsOfDirectory(atPath: oldHistory.path)) ?? [] {
            let dst = newHistory.appendingPathComponent(item)
            if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: oldHistory.appendingPathComponent(item), to: dst) }
        }
        // the names and corrections his prompt and code had
        if d.string(forKey: "names") == nil {
            d.set("Marko (never Marco; \"a Marco\" or \"Amarco\" is \"and Marko\"), Claude, Speechify, Mantra, Auroville", forKey: "names")
        }
        let corr = appSupport.appendingPathComponent("corrections.txt")
        if !fm.fileExists(atPath: corr.path) {
            try? "# one a line: regular expression => text\n\\b[Aa]\\s?[Mm]arco\\b => and Marko\n\\bMarco\\b => Marko\n"
                .write(to: corr, atomically: true, encoding: .utf8)
        }
        appendLog("v3: settings, keys and history moved over from Transcribe Voice to Text RT")
    }
}

// MARK: the duck: the speakers at 6 % while a take listens, back to their own level after

enum Duck {
    static let level: Float32 = 0.06
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "duck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "duck") }
    }
    // the level to go back to, kept on disk too: a crash or a forced quit mid-take is put right at the next launch
    private static let savedKey = "duckSaved", deviceKey = "duckDevice"

    private static var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                                 mElement: kAudioObjectPropertyElementMain)

    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func volume(_ dev: AudioDeviceID) -> Float32? {
        var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(dev, &volumeAddress),
              AudioObjectGetPropertyData(dev, &volumeAddress, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    @discardableResult static func set(_ dev: AudioDeviceID, _ v: Float32) -> Bool {
        var settable: DarwinBoolean = false, x = v
        guard AudioObjectHasProperty(dev, &volumeAddress),
              AudioObjectIsPropertySettable(dev, &volumeAddress, &settable) == noErr, settable.boolValue else { return false }
        return AudioObjectSetPropertyData(dev, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) == noErr
    }

    static var ducked: Bool { UserDefaults.standard.object(forKey: savedKey) != nil }

    /// the take began listening: down to 6 % (never up: a quieter level stays as it is). A device without a volume
    /// (BlackHole, an aggregate) is left alone.
    static func down() {
        guard enabled, !ducked, let dev = defaultOutput(), let v = volume(dev) else { return }
        UserDefaults.standard.set(v, forKey: savedKey)
        UserDefaults.standard.set(Int(dev), forKey: deviceKey)
        UserDefaults.standard.synchronize()
        if v > level { set(dev, level) }
        appendLog(String(format: "duck: speakers %.0f %% → %.0f %%", v * 100, min(v, level) * 100))
    }

    /// listening is over (stop, pause, ✕, Esc, quit, or the launch after a crash): the level it had, on the device it had
    static func up() {
        let d = UserDefaults.standard
        guard let v = d.object(forKey: savedKey) as? Float32 ?? (d.object(forKey: savedKey) as? Double).map({ Float32($0) }) else { return }
        let dev = AudioDeviceID(d.integer(forKey: deviceKey))
        d.removeObject(forKey: savedKey); d.removeObject(forKey: deviceKey); d.synchronize()
        if set(dev, v) { appendLog(String(format: "duck: speakers back to %.0f %%", v * 100)) }
    }
}
