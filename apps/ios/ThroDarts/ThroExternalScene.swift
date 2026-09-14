import SwiftUI
import ThroApp
import UIKit

// Club TV mode: the match on the wall — and, since PD-089, the league when no match is on it.
//
// **`UIScreen.screens` is deprecated (iOS 16.0), and so is the `.windowExternalDisplay` role.** The
// current model is a scene the system creates for you — `windowExternalDisplayNonInteractive`,
// which is *exactly* iOS 16.0, so this needs no new floor. iOS creates it when a display is attached
// **or when the user turns on AirPlay screen mirroring**, so a venue's Apple TV is served by the
// same code as an HDMI cable with no extra work. Attaching a window replaces the mirrored image
// with this board; removing it puts mirroring back.
//
// SwiftUI has no native external-display API until iOS 27's `sceneAccessory`, which would serve none
// of this app's users today, so this is the UIKit path — about fifty lines — and the SwiftUI one is
// a later refinement rather than a rewrite.
//
// There is deliberately no button for it. **No API can initiate screen mirroring**; only the person
// can, from Control Center. A control labelled "TV mode" that could not turn anything on would be a
// promise the app cannot keep — and `AVRoutePickerView`, which looks like the answer, is a *media*
// route picker for AVPlayer and does not mirror a screen at all.

final class ThroAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "Venue", sessionRole: session.role)
            configuration.delegateClass = ThroVenueSceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
    }
}

/// The window on the wall.
final class ThroVenueSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ThroWallScene())
        window.isHidden = false
        self.window = window
    }
}
