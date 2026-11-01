// THE CRASH LOG (Marko, 30.10.2026: "please check the crash log. If you don't see anything in a crash log, please improve
// crash log"). macOS kept no report of the crashes of that evening; only a test launch with stderr caught one. Now every
// death leaves its story in ~/Library/Logs/voice-to-text-mantra-crash.log:
//   · an Objective-C exception (the 22:33 one): its name, its reason, the whole stack, and the pill's last line;
//   · a signal (a Swift fatal error, an index out of range, a bad pointer): its number and the stack, written with
//     async-signal-safe calls only, from a file opened at launch;
// and the next launch writes "crashed last time" into the usual log, with the time.
import AppKit
import Darwin

let crashFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/voice-to-text-mantra-crash.log")
var crashCrumb = "launching"                    // the pill's last line: what the app was doing (say() keeps it)
private var crashFD: Int32 = -1
private var crashHeader = [CChar](repeating: 0, count: 256)

enum Crash {
    static func install() {
        lastTime()
        crashFD = open(crashFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        let head = "\n=== CRASH (signal) · Voice to Text (Mantra) v\(appVersion) · launched \(stamp()) · pid \(getpid()) · signal "
        _ = head.withCString { strlcpy(&crashHeader, $0, crashHeader.count) }
        for s in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(s) { n in
                if crashFD >= 0 {
                    _ = write(crashFD, crashHeader, strlen(crashHeader))
                    var d = [CChar](repeating: 0, count: 8); var v = n, i = 6
                    d[7] = 10; repeat { d[i] = CChar(48 + v % 10); v /= 10; i -= 1 } while v > 0 && i >= 0
                    _ = write(crashFD, &d[i + 1], 7 - i)
                    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                    backtrace_symbols_fd(&frames, backtrace(&frames, 64), crashFD)
                }
                signal(n, SIG_DFL); raise(n)                 // and die as before, so macOS may keep its own report too
            }
        }
    }

    // --crash-test exception | signal: die on purpose a second after launch, to see the crash log work
    static func testIfAsked() {
        guard let i = CommandLine.arguments.firstIndex(of: "--crash-test"), i + 1 < CommandLine.arguments.count else { return }
        let how = CommandLine.arguments[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            crashCrumb = "crash test (\(how))"
            if how == "signal" { let a: [Int] = []; _ = a[1] }               // a Swift fatal error: index out of range
            else { _ = NSDictionary(objects: [NSNull()], forKeys: [NSString("k"), NSString("x")]) }   // an NSException
        }
    }

    // after NSApplication.shared: AppKit sets its own uncaught-exception handler when it starts, which trapped before
    // the reason could be written (seen in the first test); ours goes on top of it
    static func afterApp() { NSSetUncaughtExceptionHandler(crashOnException) }

    static func stamp() -> String { let f = ISO8601DateFormatter(); f.timeZone = .current; return f.string(from: Date()) }

    // a crash since the last launch: one line in the usual log, so the history of takes shows where it happened
    private static func lastTime() {
        let seen = UserDefaults.standard.double(forKey: "crashLogSeen")
        guard let a = try? FileManager.default.attributesOfItem(atPath: crashFile.path),
              let m = (a[.modificationDate] as? Date)?.timeIntervalSince1970, m > seen + 1 else { return }
        UserDefaults.standard.set(m, forKey: "crashLogSeen")
        if seen > 0 || m > Date().timeIntervalSince1970 - 86400 {
            appendLog("crashed last time (\(Date(timeIntervalSince1970: m))); see ~/Library/Logs/voice-to-text-mantra-crash.log")
        }
    }
}

// the exception handler: a plain function, as NSSetUncaughtExceptionHandler takes a C function pointer
private func crashOnException(_ e: NSException) {
    let text = """

    === CRASH (exception) · Voice to Text (Mantra) v\(appVersion) · \(Crash.stamp())
    \(e.name.rawValue): \(e.reason ?? "no reason")
    the pill said: \(crashCrumb)
    \(e.callStackSymbols.joined(separator: "\n"))

    """
    if let h = try? FileHandle(forWritingTo: crashFile) { h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close() }
    appendLog("CRASH: \(e.name.rawValue): \(e.reason ?? "")  (the whole story in voice-to-text-mantra-crash.log)")
}
