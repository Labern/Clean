// Registers the app's own Capacitor plugin (Gt7Direct). Main.storyboard's view
// controller is set to this class by native/install-plugin.sh.
import UIKit
import Capacitor

class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(Gt7DirectPlugin())
    }
}
