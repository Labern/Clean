import Foundation

/// Executes a gesture's configured action. URL actions first try to focus an
/// existing browser tab (Safari, then Chrome) already showing that address —
/// a new tab is opened only when none exists. First use triggers macOS's
/// one-time Automation permission prompt for the browser.
enum ActionRunner {
    static func run(_ action: GestureAction) {
        switch action.kind {
        case .none:
            break
        case .app:
            shell("/usr/bin/open", ["-a", action.value])
        case .shell:
            shell("/bin/sh", ["-c", action.value])
        case .url:
            openURL(action.value)
        }
    }

    private static func shell(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
    }

    private static func openURL(_ url: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let target = url.hasSuffix("/") ? String(url.dropLast()) : url
            for script in [safariFocus, chromeFocus] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script, target]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                guard (try? p.run()) != nil else { continue }
                p.waitUntilExit()
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                                  encoding: .utf8) ?? ""
                if p.terminationStatus == 0 && text.contains("focused") { return }
            }
            shell("/usr/bin/open", [url])
        }
    }

    private static let safariFocus = """
    on run argv
        set target to item 1 of argv
        if application "Safari" is running then
            tell application "Safari"
                repeat with w in every window
                    try
                        repeat with t in every tab of w
                            if URL of t starts with target then
                                tell w to set current tab to t
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                        end repeat
                    end try
                end repeat
            end tell
        end if
        return "notfound"
    end run
    """

    private static let chromeFocus = """
    on run argv
        set target to item 1 of argv
        if application id "com.google.Chrome" is running then
            tell application id "com.google.Chrome"
                repeat with w in every window
                    try
                        set tIndex to 0
                        repeat with t in every tab of w
                            set tIndex to tIndex + 1
                            if URL of t starts with target then
                                set active tab index of w to tIndex
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                        end repeat
                    end try
                end repeat
            end tell
        end if
        return "notfound"
    end run
    """
}
