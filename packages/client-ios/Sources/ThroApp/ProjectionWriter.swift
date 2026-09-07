import Foundation
import ThroJournal
import ThroLiveKit
import ThroPlay
import WidgetKit

// The app's side of the App Group.
//
// **The app writes; the widget reads.** One writer, here, assembling from the three things the
// widgets are allowed to show: the leg being scored, the next fixture, and two counts. The
// extension never writes — it would be a second writer to a file this process assumes it owns, and
// it has nothing to say.
//
// The live half comes from `ThroVenue.shared`, which already is this app's one holder of the leg in
// play: the scoring session pushes to it for the wall screen, so reading it here means there is one
// live state rather than two that can disagree. The rest comes from what Home already computed.

enum ThroProjectionWriter {

    /// What the widgets would show, given what the device holds.
    ///
    /// Pure, and separated from the writing, so the rules can be tested without an App Group — which
    /// a package test does not have and never will.
    static func assemble(matches: [AppStore.HomeMatch],
                         week: DeviceSummary.Week?,
                         clubs: [Club],
                         live: ThroLiveState?,
                         liveFormat: String,
                         now: Date = Date()) -> ThroProjection {
        ThroProjection(writtenAt: now,
                       live: live,
                       liveFormat: liveFormat,
                       nextFixture: nextFixture(in: clubs, now: now),
                       matches: matches.count,
                       legsThisWeek: week?.legs ?? 0)
    }

    /// The soonest fixture still ahead, across everything this phone keeps.
    ///
    /// **Only a scheduled one.** A cancelled fixture is not happening and a postponed one has no
    /// time anybody trusts, so putting either on a Home Screen would be telling somebody to turn up.
    /// A played one is behind us whatever its clock says.
    static func nextFixture(in clubs: [Club], now: Date = Date()) -> ThroProjectedFixture? {
        clubs
            .flatMap(\.fixtures)
            .filter { $0.state == .scheduled }
            .compactMap { fixture -> ThroProjectedFixture? in
                guard let at = fixture.at, at > now else { return nil }
                return ThroProjectedFixture(title: fixture.title, at: at, venue: fixture.venue)
            }
            .min { $0.at < $1.at }
    }

    /// Writes it and asks the system to redraw. Silent when there is no App Group, which is the
    /// normal state of a build without the capability.
    static func write(matches: [AppStore.HomeMatch],
                      week: DeviceSummary.Week?,
                      clubs: [Club],
                      live: ThroLiveState?,
                      liveFormat: String) {
        let projection = assemble(matches: matches, week: week, clubs: clubs,
                                  live: live, liveFormat: liveFormat)
        guard ThroProjectionStore.write(projection) else { return }
        // Only after a write that landed. Reloading timelines against a file that did not change is
        // spending the widget's refresh budget to draw the same thing.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
