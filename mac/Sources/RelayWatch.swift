import Foundation

// v69, Marko, 22.11.2026: "Some blob is coming up fixing ... Every few minutes fixing connection or something. This blob is so
// annoying." The rule of a watcher: a notice once per CHANGE of state, retries quietly with a growing pause, and never repairs
// what it does not own (Tailscale is Marko's switch). This is the pure part (tested by --selftest): the state of the Frankfurt
// relay, when to notice, when to look again, what to log.
struct RelayWatch {
    enum Notice: Equatable { case none, down, back }
    private(set) var known: Bool?            // nil until the first check after launch
    private(set) var misses = 0              // checks in a row that found it down
    private var lastSummary = Date.distantPast
    private var downSince = Date.distantPast
    var checksWhileDown = 0

    /// the pause before the next check: 20 s while it is up; after a miss 20 s, 1 min, 2 min, 5 min, then every 15 min
    static func pause(up: Bool, misses: Int) -> TimeInterval {
        if up { return 20 }
        switch misses { case ..<2: return 20; case 2: return 60; case 3: return 120; case 4: return 300; default: return 900 }
    }

    /// what one check found. `notice`: the toast to show (only on a change after the first check; at launch none: the DIR badge
    /// and the take's own route line say it, a take never asks for a notice); `log`: one line per change, one summary per hour
    mutating func observe(ok: Bool, now: Date) -> (notice: Notice, log: String?) {
        defer { known = ok }
        if ok {
            misses = 0
            if known == nil { return (.none, "frankfurt: relay reachable") }
            if known == false { return (.back, "frankfurt: relay is back (was down \(Int(now.timeIntervalSince(downSince) / 60)) min, \(checksWhileDown) checks)") }
            return (.none, nil)
        }
        misses += 1
        if known == nil { downSince = now; lastSummary = now; checksWhileDown = 1; return (.none, "frankfurt: relay not reachable at launch: dictating direct") }
        if known == true { downSince = now; lastSummary = now; checksWhileDown = 1; return (.down, "frankfurt: relay not reachable: dictating direct") }
        checksWhileDown += 1
        if now.timeIntervalSince(lastSummary) >= 3600 {
            lastSummary = now
            return (.none, "frankfurt: still not reachable, \(checksWhileDown) checks since \(Int(now.timeIntervalSince(downSince) / 60)) min ago")
        }
        return (.none, nil)
    }

    /// is a check due (the background timer asks every 20 s; the pause says when the next one may run)
    func due(now: Date, last: Date) -> Bool { now.timeIntervalSince(last) >= RelayWatch.pause(up: known != false, misses: misses) - 0.5 }
}
