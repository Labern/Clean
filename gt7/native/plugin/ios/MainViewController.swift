// Registers the app's own Capacitor plugin (Gt7Direct). Main.storyboard's view
// controller is set to this class by native/install-plugin.sh.
import UIKit
import Capacitor

class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(Gt7DirectPlugin())
        // CI only: `-route '#/telemetry'` opens a page at launch so the cloud build can screenshot it
        if let i = CommandLine.arguments.firstIndex(of: "-route"), i + 1 < CommandLine.arguments.count {
            let route = CommandLine.arguments[i + 1].replacingOccurrences(of: "'", with: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.webView?.evaluateJavaScript("location.hash = '\(route)'", completionHandler: nil)
            }
        }
    }
}
