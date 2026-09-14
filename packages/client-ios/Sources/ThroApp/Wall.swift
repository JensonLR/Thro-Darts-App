import Foundation
import SwiftUI
import ThroLiveKit
import ThroNet
import ThroVenueKit

// What a phone puts on a pub television (PD-089).
//
// **The Apple TV app, without the Apple TV.** `ThroTV` is a real product and it is the better answer for a
// room that keeps a screen on all season — it needs no phone in the building. But it is £150 of hardware
// that has to be registered to a developer team, and the room that wants a live board *this Tuesday* has a
// telly, an HDMI socket and a landlord with an iPhone. iOS already creates a
// `windowExternalDisplayNonInteractive` scene for a cable **or for AirPlay mirroring**, which is how the
// match board has reached a wall since PD-041. This puts the league on the same scene.
//
// **Two things can want the screen, and the match wins.** If a match is being scored on this phone, the
// room is watching that match and the board shows it — a league table would be the app deciding that the
// game ten feet away is less interesting than the standings. When nothing is being scored, the season the
// landlord chose takes the screen. Nothing chosen and nothing playing, and it says how to choose, because
// a black television with an app's name on it teaches somebody that the feature does not work.

/// The whole of what an external display shows.
public struct ThroWallScreen: View {
    @ObservedObject private var venue = ThroVenue.shared
    private let season: UUID?
    private let api: ThroAPI?

    /// - Parameters:
    ///   - season: the league season this phone was pointed at, or nil if nobody has chosen one.
    ///   - api: **a sessionless client**, built by the caller. See `ThroWall.api(for:)` for why.
    public init(season: UUID?, api: ThroAPI?) {
        self.season = season
        self.api = api
    }

    public var body: some View {
        Group {
            if venue.state != nil {
                // The match on this phone. Unchanged since PD-041, and it takes precedence.
                ThroVenueBoard(state: venue.state, format: venue.format, stale: venue.isStale())
            } else if let season, let api {
                ThroVenueChannel(wall: ThroVenueWall(api: api), season: season)
            } else {
                ThroWallNothing()
            }
        }
        // A wall has no clock and no home indicator on it. Guarded because the package builds for macOS
        // too, where neither modifier exists and neither is meaningful.
        #if os(iOS) || os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

/// The whole external display, assembled: the choice this phone holds, and a sessionless client.
///
/// **Public, and the app target's one name.** The scene delegate in `apps/ios/ThroDarts` mounts this and
/// nothing else — it imports `ThroApp` and needs to know about neither `ThroNet` nor `ThroVenueKit`. The
/// deciding is in this module where it can be reasoned about; the UIKit file stays fifty lines of
/// plumbing, which is what it is good at being.
public struct ThroWallScene: View {
    public init() {}

    public var body: some View {
        let configuration = ServerConfiguration.fromInfoPlist()
        ThroWallScreen(season: ThroVenueChoice().season,
                       api: configuration.map { ThroWall.api(for: $0) })
    }
}

/// How to put something on this screen, on the screen itself.
///
/// It is addressed to whoever is standing in the room with the phone, so it says where the setting is
/// rather than what it is called: somebody reading this is looking at a television and holding the thing
/// that has to change.
struct ThroWallNothing: View {
    var body: some View {
        ThroVenueEmptyWall(title: ThroWall.nothingTitle, hint: ThroWall.nothingHint)
    }
}

public enum ThroWall {
    public static let nothingTitle = "Nothing on this screen yet"
    public static let nothingHint =
        "On the phone: Live → Put a league on the telly. Score a match and this shows the match instead."

    /// The client the wall reads with: **the same configuration, and no session**.
    ///
    /// The phone has a signed-in `ThroAPI` a few lines away and passing it would work today, because every
    /// route the wall reads is public. It is not passed, and the reason is the property the Apple TV app
    /// has structurally and this one would otherwise only have by luck: *a screen in a room full of
    /// strangers sees what a stranger sees.* If a public route ever starts returning more to an
    /// authenticated caller — a name, a contact, a private team — the pub television must not be the
    /// surface that finds out. `check_the_wall_never_signs_in.py` holds it for `ThroVenueKit`; this holds
    /// the same line at the one place a credential could have got in.
    /// The device id is a **fresh one each launch**, and that is not laziness either. The phone's own
    /// device id identifies the phone across sessions, which is exactly right for a signed-in client and
    /// exactly wrong for a screen: nothing the wall asks for is about a device, so there is nothing for
    /// this one to be, and one that persisted would be a correlatable identifier attached to reads made
    /// on behalf of a room rather than a person.
    public static func api(for configuration: ServerConfiguration, deviceId: UUID = UUID()) -> ThroAPI {
        ThroAPI(configuration: configuration, deviceId: deviceId, store: MemorySessionStore(nil))
    }
}
