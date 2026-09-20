import UIKit

/// A thin UIKit shim purely so `VehicleDataStore` (and therefore the CoreBluetooth central
/// manager, with its restoration identifier) is created inside
/// `application(_:didFinishLaunchingWithOptions:)` — the point Apple's CoreBluetooth
/// background-restoration guidance calls out as the reliable place to do it, including on a
/// silent background relaunch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let layoutStore = GaugeLayoutStore()
    lazy var store = VehicleDataStore(layoutStore: layoutStore)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        store.startForLaunch()
        return true
    }
}
