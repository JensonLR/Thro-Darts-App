import SwiftUI
import ThroWatchKit

// The whole of the watch target. Everything real lives in packages/client-ios, under tests, for the
// same reason the phone's app target is nineteen lines: an app needs a target and SwiftPM cannot
// produce one, and that is the only job this file has.
@main
struct ThroWatchApp: App {
    /// Opened here rather than in the view, because the context the phone left is handed over when
    /// the session activates — a watch that waited for a screen to appear before listening would
    /// draw an empty board first and the leg a moment later.
    init() {
        #if DEBUG
        // `-ThroWristDemo` puts a leg on the wrist with no phone attached, so the layout can be
        // looked at on a simulator. The phone target's `-ThroScreen` is the same idea. **The link is
        // not started for it.** A simulator watch is paired with a simulator phone, whose last word —
        // usually that nothing is on — waits on the session and is read on activation, which cleared
        // the demo leg a moment after it was drawn. A demo is a watch with no phone, so it does not listen.
        if ProcessInfo.processInfo.arguments.contains("-ThroWristDemo") {
            ThroWrist.shared.seedFromLaunchArguments()
            return
        }
        #endif
        ThroWristLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ThroWatchRoot()
        }
    }
}
