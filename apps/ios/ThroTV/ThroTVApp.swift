import SwiftUI
import ThroNet
import ThroVenueKit

// The whole of the Apple TV target. Everything real lives in packages/client-ios, under tests, for the
// same reason the phone's target is nineteen lines and the watch's is thirteen.
//
// **It never signs in**, so it is handed a session store that cannot outlive the process: a screen on a
// pub wall has no credential to leak and nothing for whoever picks up the remote to reach. Every route it
// reads is public by decision (PD-054, PD-056) — a league's published competition is published.
@main
struct ThroTVApp: App {
    private let configuration = ServerConfiguration.fromInfoPlist()

    var body: some Scene {
        WindowGroup {
            if let configuration {
                ThroVenueScreen(api: ThroAPI(configuration: configuration,
                                             deviceId: ThroVenueDevice.id,
                                             store: MemorySessionStore()))
            } else {
                // A build with no `THROAPIBaseURL` cannot read anything and should say so on the wall
                // rather than showing an empty league forever. The phone target takes the same line.
                ThroVenueUnconfigured()
            }
        }
    }
}
