import SwiftUI
import ThroApp

// The whole of the app target. Everything real lives in packages/client-ios, under tests; this file
// exists because an iOS app needs an app target and SwiftPM cannot produce one.
@main
struct ThroDartsApp: App {
    /// The delegate exists for one reason: an external display arrives as a **scene**, and only an
    /// application delegate is asked which configuration to give it. `ThroExternalScene.swift` says
    /// the rest.
    @UIApplicationDelegateAdaptor(ThroAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ThroRootView()
        }
    }
}
