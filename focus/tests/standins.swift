// Stand-in apps for Focus's full test suite. One program, three behaviours, chosen by the bundle id it's built under:
//   …savepromptstandin — refuses to quit, like an app sitting on a "Save changes?" prompt
//   …slowquit          — takes 12 s to finish quitting, like a big app saving its state
//   …relauncher        — quits normally (the test runner relaunches it, like a login-item helper)
import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        let id = Bundle.main.bundleIdentifier ?? ""
        if id.hasSuffix("savepromptstandin") { return .terminateCancel }
        if id.hasSuffix("slowquit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { app.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        return .terminateNow
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
