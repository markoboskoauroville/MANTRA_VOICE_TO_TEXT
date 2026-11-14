// Exclusive.swift (v16, 14.11.2026). Marko: "The idea is that one replaces the other. If I open my own engine, voice to
// text, then it closes Speechify automatically. If I open Speechify manually, my own engine disappears. So they are
// mutually exclusive." F1 belongs to whichever of the two is running.
//
// No loop: this app only ever quits Speechify at its own start (pids already running then are remembered and ignored by
// the launch watcher), and quits ITSELF when a Speechify launches later. Speechify is never started from here.
import AppKit

enum Exclusive {
    static let prefix = "com.cliffweitzman.speechify"      // Speechify Voice AI: com.cliffweitzman.speechifymacagent
    static var ignored = Set<pid_t>()                       // the ones this app is closing at its own start
    static var quitting = false

    static func speechifyApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { ($0.bundleIdentifier ?? "").hasPrefix(prefix) }
    }

    /// At launch: Speechify running means it is asked to quit; still alive after 4 s means force.
    static func start() {
        let running = speechifyApps()
        for a in running {
            ignored.insert(a.processIdentifier)
            appendLog("exclusive: Speechify (\(a.bundleIdentifier ?? "?"), pid \(a.processIdentifier)) is running: asking it to quit")
            a.terminate()
        }
        if !running.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                for a in running where !a.isTerminated {
                    appendLog("exclusive: Speechify pid \(a.processIdentifier) still alive after 4 s: force quit")
                    a.forceTerminate()
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
            guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  (a.bundleIdentifier ?? "").hasPrefix(prefix), !ignored.contains(a.processIdentifier) else { return }
            appendLog("exclusive: Speechify launched (pid \(a.processIdentifier)): F1 released, quitting")
            quitForSpeechify()
        }
    }

    /// F1 released first, then a clean quit, no dialog, no confirmation.
    static func quitForSpeechify() {
        if quitting { return }
        quitting = true
        stripe.releaseKeys()
        NSApp.terminate(nil)
    }
}
