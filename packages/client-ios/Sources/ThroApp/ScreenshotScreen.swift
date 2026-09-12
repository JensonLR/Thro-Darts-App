#if DEBUG
import Foundation

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
}
#endif
