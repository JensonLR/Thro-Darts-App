import SwiftUI
import ThroLiveKit
import UIKit

// Club TV mode: the match on the wall.
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
        window.rootViewController = UIHostingController(rootView: ThroVenueScreen())
        window.isHidden = false
        self.window = window
    }
}

/// The board, watching the one venue state the scoring screen writes to.
///
/// A timer ticks so staleness is noticed without anything else happening. On a phone the Lock Screen
/// is refreshed by the system when its `staleDate` passes; a `UIWindow` on a wall is refreshed by
/// nobody, and a room reading a score that quietly stopped being true is the failure this surface
/// exists to avoid.
private struct ThroVenueScreen: View {
    @ObservedObject private var venue = ThroVenue.shared
    @State private var now = Date()

    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ThroVenueBoard(state: venue.state,
                       format: venue.format,
                       stale: venue.isStale(now: now))
            .onReceive(tick) { now = $0 }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}
