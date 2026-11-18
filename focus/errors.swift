import AppKit
import Darwin

// MARK: - Error codes
//
// Every failure Focus can notice has a code. Fxxx, grouped by area:
//   F1xx sessions (parking and bringing apps back)   F5xx permissions
//   F2xx opening and quitting apps                    F6xx saved settings
//   F3xx keyboard shortcuts                           F7xx the network (updates, feedback, prices)
//   F4xx Super Smart Search                           F8xx sound
//                                                     F9xx Focus itself (crashes, restarts)
// The full table, with what each means and what to check, is docs/ERROR-CODES.md (a test keeps the two in step).
// Records go to ~/Library/Logs/Focus/errors.jsonl, one JSON object per line, each carrying the last lines of
// Focus.log that led up to it. `Focus --diagnose` summarises them. Nothing a user types is ever written.

enum FocusError: String, CaseIterable {
    // F1 sessions
    case quitTimedOut = "F101"            // an app was asked to quit and was still open when the queue moved on
    case quitRefused = "F102"             // macOS refused to send an app the quit request
    case restoreAppMissing = "F110"       // an app parked in a session is no longer where it was
    case restoreLaunchFailed = "F111"     // an app could not be reopened at the end of a session
    case modeAppNotFound = "F112"         // a mode's app is not installed (nothing to open)
    // F2 apps
    case appNotFound = "F201"             // an app asked for by bundle id is not installed
    case appOpenFailed = "F202"           // macOS returned an error opening an app
    case forceQuitRefused = "F203"        // a force quit was refused
    // F3 shortcuts
    case hotkeyTaken = "F301"             // macOS would not register a shortcut: another app holds it
    // F4 Super Smart Search
    case scriptNotAllowed = "F401"        // the Mac has not allowed Focus to control that app (Automation, -1743)
    case scriptAppNotRunning = "F402"     // the app quit between being seen and being asked (-600)
    case scriptTimedOut = "F403"          // the app did not answer in time
    case scriptFailed = "F404"            // any other script error (the app's own message is kept)
    case scriptCouldNotStart = "F405"     // osascript itself would not start
    case pageReadingOff = "F406"          // the browser's "Allow JavaScript from Apple Events" is off
    case tabNotFound = "F410"             // the chosen tab was not where it was, nor found by its address
    case notBroughtForward = "F411"       // the app was asked to come forward and did not
    // F5 permissions
    case accessibilityMissing = "F501"    // windows can't be read or raised: no Accessibility permission
    // F6 saved settings
    case settingsUnreadable = "F601"      // saved settings exist but could not be read (the defaults are used)
    // F7 network
    case updateCheckFailed = "F701"
    case feedbackFailed = "F702"          // the feedback post failed; the email fallback opened instead
    case pricingFetchFailed = "F703"
    // F8 sound
    case chimeFailed = "F801"
    // F9 Focus itself
    case uncaughtException = "F901"
    case crashed = "F902"                 // a fatal signal: the stack is kept
    case endedUnexpectedly = "F903"       // the last run never quit (crash, force quit, power loss)
    case staleCopyReplaced = "F904"       // a running Focus did not answer and was replaced

    var name: String { String(describing: self) }
    var area: String {
        switch rawValue.dropFirst().first {
        case "1": "session"; case "2": "apps"; case "3": "shortcuts"; case "4": "search"; case "5": "permissions"
        case "6": "settings"; case "7": "network"; case "8": "sound"; default: "focus"
        }
    }
}

// MARK: - The log

enum ErrorLog {
    /// Where records go. Tests point it somewhere temporary.
    static var dir: URL = CommandLine.arguments.contains { $0.hasPrefix("--selftest") || $0.hasPrefix("--render") || $0.hasPrefix("--sss-go") }
        ? FileManager.default.temporaryDirectory.appendingPathComponent("focus-test-logs-\(getpid())")   // tests never touch the real record
        : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Focus")
    static var file: URL { dir.appendingPathComponent("errors.jsonl") }
    static var crashFile: URL { dir.appendingPathComponent("crash.txt") }
    static var marker: URL { dir.appendingPathComponent("running.json") }
    static let run = String(UUID().uuidString.prefix(8))          // ties a run's records together
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    private static let lock = NSLock()
    private static var trail: [String] = []                          // the last lines of Focus.log, for context
    private static var lastSeen: [String: (at: Date, suppressed: Int)] = [:]

    /// flog calls this: every line is kept briefly so an error can show what led up to it.
    static func breadcrumb(_ line: String) {
        lock.lock(); trail.append(line); if trail.count > 20 { trail.removeFirst(trail.count - 20) }; lock.unlock()
    }

    /// Records an error. `detail` is plain words for a person; `context` is anything useful to debugging (no
    /// typed text, no page contents). The same code and detail inside 10 s is counted, not written again.
    @discardableResult
    static func record(_ code: FocusError, _ detail: String, _ context: [String: Any] = [:], at: Date = Date()) -> [String: Any] {
        lock.lock()
        let key = code.rawValue + detail
        if let seen = lastSeen[key], at.timeIntervalSince(seen.at) < 10 {
            lastSeen[key] = (seen.at, seen.suppressed + 1); lock.unlock(); return [:]
        }
        let repeats = lastSeen[key]?.suppressed ?? 0
        lastSeen[key] = (at, 0)
        let crumbs = trail
        lock.unlock()
        var rec: [String: Any] = ["t": ISO8601DateFormatter().string(from: at), "code": code.rawValue, "name": code.name,
                                  "area": code.area, "detail": String(detail.prefix(500)), "v": version, "run": run,
                                  "macOS": ProcessInfo.processInfo.operatingSystemVersionString, "trail": crumbs]
        if !context.isEmpty { rec["ctx"] = context.mapValues { "\($0)".prefix(300).description } }
        if repeats > 0 { rec["repeatsBefore"] = repeats }
        append(rec)
        flog("ERROR \(code.rawValue) \(code.name) — \(detail.prefix(200))")
        return rec
    }

    static func append(_ rec: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]) else { return }
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Kept small: past 1 MB the file becomes errors.1.jsonl (the one before is dropped).
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int, size > 1_000_000 {
            let old = dir.appendingPathComponent("errors.1.jsonl")
            try? FileManager.default.removeItem(at: old); try? FileManager.default.moveItem(at: file, to: old)
        }
        let line = data + Data("\n".utf8)
        if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: file) }
    }

    /// Every record, oldest first (both files).
    static func all() -> [[String: Any]] {
        [dir.appendingPathComponent("errors.1.jsonl"), file].flatMap { url -> [[String: Any]] in
            guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        }
    }

    // MARK: crashes and runs that never ended

    /// Called once when Focus starts for real: reports how the last run ended, then watches this one.
    static func start() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A crash written by the signal handler last time.
        if let c = try? String(contentsOf: crashFile, encoding: .utf8), !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record(.crashed, c.components(separatedBy: "\n").first ?? "fatal signal", ["stack": c.components(separatedBy: "\n").dropFirst().prefix(25).joined(separator: "\n")])
            try? FileManager.default.removeItem(at: crashFile)
        }
        // The last run's marker still here: it never quit.
        if let d = try? Data(contentsOf: marker), let last = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let pid = (last["pid"] as? Int).map { pid_t($0) } ?? 0
            let alive = pid != 0 && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Bundle.main.bundleIdentifier
            if !alive {
                var ctx: [String: Any] = ["lastRun": last["run"] ?? "?", "lastVersion": last["v"] ?? "?", "lastStarted": last["t"] ?? "?"]
                if let report = newestCrashReport(since: (last["t"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }) { ctx["crashReport"] = report }
                record(.endedUnexpectedly, "the last run of Focus ended without quitting (a crash, a force quit or the Mac losing power)", ctx)
            }
        }
        let me: [String: Any] = ["run": run, "v": version, "pid": Int(getpid()), "t": ISO8601DateFormatter().string(from: Date())]
        if let d = try? JSONSerialization.data(withJSONObject: me) { try? d.write(to: marker) }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            try? FileManager.default.removeItem(at: marker)
        }
        NSSetUncaughtExceptionHandler { e in
            ErrorLog.record(.uncaughtException, "\(e.name.rawValue): \(e.reason ?? "")", ["stack": e.callStackSymbols.prefix(25).joined(separator: "\n")])
        }
        crashFD = open(crashFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        for s in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP] { signal(s, focusCrashHandler) }
        // An update or a plain `kill` asks politely (SIGTERM): that is a normal end, not F903.
        markerCPath = strdup(marker.path)
        for s in [SIGTERM, SIGINT, SIGHUP] { signal(s, focusQuitHandler) }
    }

    /// The newest macOS crash report for Focus written since a date (its file name, for --diagnose and the record).
    static func newestCrashReport(since: Date?) -> String? {
        let dirs = ["Library/Logs/DiagnosticReports", "Library/Logs/DiagnosticReports/Retired"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
        let found = dirs.flatMap { d in ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Focus") } }
        let dated = found.compactMap { u in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) } }
            .filter { since == nil || $0.1 >= since! }.sorted { $0.1 > $1.1 }
        return dated.first?.0.path
    }

    // MARK: script errors → codes

    /// Reads an osascript error message and gives it its code.
    static func scriptCode(_ said: String) -> FocusError {
        if said == "could not start" { return .scriptCouldNotStart }
        if said.hasPrefix("stopped after") { return .scriptTimedOut }
        if said.contains("-1743") || said.localizedCaseInsensitiveContains("not allowed") || said.localizedCaseInsensitiveContains("not authori") { return .scriptNotAllowed }
        if said.contains("(-600)") || said.localizedCaseInsensitiveContains("isn’t running") || said.localizedCaseInsensitiveContains("isn't running") { return .scriptAppNotRunning }
        if said.localizedCaseInsensitiveContains("JavaScript") && said.localizedCaseInsensitiveContains("turned off") { return .pageReadingOff }
        if said.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events") { return .pageReadingOff }
        return .scriptFailed
    }

    // MARK: --diagnose

    static func diagnose(days: Double = 7) -> String {
        let now = Date(), iso = ISO8601DateFormatter()
        let recs = all().filter { ($0["t"] as? String).flatMap { iso.date(from: $0) }.map { now.timeIntervalSince($0) < days * 86400 } ?? false }
        var out = ["Focus diagnostics · \(version) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
                   "Running copies: \(NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.labern.focus" && $0.processIdentifier != getpid() }.map { "\($0.processIdentifier)" }.joined(separator: ", ").ifEmpty("none"))",
                   "Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed") (for this binary)",
                   "Records: \(file.path)", ""]
        if recs.isEmpty { out.append("No errors in the last \(Int(days)) days."); return out.joined(separator: "\n") }
        out.append("Errors in the last \(Int(days)) days, by code:")
        let byCode = Dictionary(grouping: recs) { $0["code"] as? String ?? "?" }
        for (code, rs) in byCode.sorted(by: { $0.value.count > $1.value.count }) {
            let name = rs.first?["name"] as? String ?? ""
            let last = rs.last?["t"] as? String ?? ""
            out.append("  \(code) \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) ×\(rs.count)  last \(last)")
        }
        out.append(""); out.append("The last 15:")
        for r in recs.suffix(15) {
            out.append("  \(r["t"] as? String ?? "") \(r["code"] as? String ?? "") v\(r["v"] as? String ?? "") — \(r["detail"] as? String ?? "")")
            if let c = r["ctx"] as? [String: Any], !c.isEmpty {
                out.append("      " + c.filter { $0.key != "stack" }.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · "))
            }
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Tests get their own settings

/// Self-tests and renders run on a copy of the user's settings, never the settings themselves. Without this, a test
/// run flipped the live Focus to Basic and "0 sessions left" while he was using it (seen 2026-11-18), and two
/// sessions' test runs collided. Every `UserDefaults.standard` (ours and AppKit's) answers from the copy.
func isolateTestSettings() {
    let args = CommandLine.arguments
    guard args.contains(where: { $0.hasPrefix("--selftest") || $0.hasPrefix("--render") || $0.hasPrefix("--sss-go") }) else { return }
    let real = Bundle.main.bundleIdentifier ?? "com.labern.focus"
    let name = real + ".selftest.\(getpid())"
    // Copies left by earlier runs (macOS writes the file back after it is deleted): removed once that run is gone.
    let prefs = NSHomeDirectory() + "/Library/Preferences"
    for f in (try? FileManager.default.contentsOfDirectory(atPath: prefs)) ?? [] where f.hasPrefix(real + ".selftest.") && f.hasSuffix(".plist") {
        let pid = Int32(f.dropFirst((real + ".selftest.").count).dropLast(".plist".count)) ?? 0
        if pid > 0 && kill(pid, 0) != 0 { try? FileManager.default.removeItem(atPath: prefs + "/" + f) }
    }
    guard let suite = UserDefaults(suiteName: name) else { return }
    suite.setPersistentDomain(UserDefaults.standard.persistentDomain(forName: real) ?? [:], forName: name)   // starts as his settings
    let block: @convention(block) (AnyObject) -> UserDefaults = { _ in suite }
    if let m = class_getClassMethod(UserDefaults.self, NSSelectorFromString("standardUserDefaults")) {
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
    testSettingsName = name
    atexit {                                                    // the copy goes when the test ends
        if let n = testSettingsName {
            UserDefaults(suiteName: n)?.removePersistentDomain(forName: n)
            try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Preferences/\(n).plist")
        }
    }
}
nonisolated(unsafe) var testSettingsName: String? = nil

/// Shorthand used at the call sites.
func ferr(_ code: FocusError, _ detail: String, _ context: [String: Any] = [:]) { ErrorLog.record(code, detail, context) }

private extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

// MARK: - The signal handler (async-signal-safe: write() only, to a file opened in advance)

nonisolated(unsafe) var crashFD: Int32 = -1
nonisolated(unsafe) var markerCPath: UnsafeMutablePointer<CChar>? = nil
private func focusQuitHandler(_ sig: Int32) {
    if let p = markerCPath { unlink(p) }
    signal(sig, SIG_DFL); raise(sig)
}
private func focusCrashHandler(_ sig: Int32) {
    if crashFD >= 0 {
        var head: [UInt8] = Array("Focus stopped on signal ".utf8)
        var n = sig, digits: [UInt8] = []
        repeat { digits.insert(UInt8(48 + n % 10), at: 0); n /= 10 } while n > 0
        head += digits; head.append(10)
        _ = head.withUnsafeBufferPointer { write(crashFD, $0.baseAddress, $0.count) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 40)
        let count = backtrace(&frames, 40)
        backtrace_symbols_fd(&frames, count, crashFD)
    }
    signal(sig, SIG_DFL); raise(sig)
}
