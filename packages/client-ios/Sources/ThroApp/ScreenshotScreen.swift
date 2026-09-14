#if DEBUG
import Foundation
#if os(iOS)
import UIKit
#endif

/// The screen to open on, for looking at one without a hand on the device.
///
/// **Why it exists.** Every screen in this app can be reached by tapping, and a simulator being driven
/// from a script cannot tap. That left most surfaces unlooked-at while they were being changed — which is
/// how thirty-three of them came to be written as though nobody would open them on a tablet (PD-052), and
/// how the bottom bar spread across one for a fortnight without anybody seeing it.
///
///     xcrun simctl launch <device> app.thro.darts -ThroScreenshotAccount adult -ThroScreen tab/discover
///
/// The value is a `thro://` address without its scheme — `tab/you`, `settings`, `e/<club id>` — read by
/// the very parser a real link goes through (ADR-011). So this can reach exactly the screens a link can
/// and no others, there is no second grammar to keep in step with the first, and an address that names
/// nothing leaves the app where it was. A Release build does not contain this file.
enum ScreenshotScreen {
    static let argument = "-ThroScreen"

    @MainActor static func goIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let i = arguments.firstIndex(of: argument), arguments.indices.contains(i + 1) else { return }
        guard let url = URL(string: "\(ThroRoute.scheme)://\(arguments[i + 1])"),
              let route = ThroRoute(url: url) else { return }
        ThroRouter.shared.go(route)
    }

    static let orientationArgument = "-ThroOrientation"

    /// Turns the app on its side, for looking at a landscape layout without a hand on the device (PD-092).
    ///
    ///     xcrun simctl launch <device> app.thro.darts -ThroScreen tab/you -ThroOrientation landscape
    ///
    /// **Why this and not the Simulator's Rotate command.** That turns whichever simulator window is in front,
    /// and with two booted — two sessions on one machine — the one in front is not necessarily the one being
    /// checked. This asks *this app's* scene to rotate, so it can only ever turn the device it runs on.
    ///
    /// `simctl io … screenshot` keeps the device's portrait frame, so the image comes back sideways; turn it
    /// with `sips -r 270` before looking.
    @MainActor static func orientIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if os(iOS)
        guard let i = arguments.firstIndex(of: orientationArgument), arguments.indices.contains(i + 1),
              arguments[i + 1] == "landscape" else { return }
        // On the first pass through the root view the scene may not have connected yet. One more turn of the
        // main actor is enough; with no scene to receive it, the request is simply not made.
        if !turnSideways() { Task { @MainActor in _ = turnSideways() } }
        #endif
    }

    #if os(iOS)
    @MainActor private static func turnSideways() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.session.role == .windowApplication }) else { return false }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        return true
    }
    #endif
}
#endif
