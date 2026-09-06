import SwiftUI
import ThroApp

// The whole of the app target. Everything real lives in packages/client-ios, under tests; this file
// exists because an iOS app needs an app target and SwiftPM cannot produce one.
@main
struct ThroDartsApp: App {
    var body: some Scene {
        WindowGroup {
            ThroRootView()
        }
    }
}
