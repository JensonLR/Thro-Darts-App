import Combine
import Foundation
import SwiftUI
import ThroLiveKit
import ThroTokens

// What this watch is showing, and the screen that shows it.
//
// **The same shape as the wall.** `ThroVenue` in ThroLiveKit is the app's one holder of the leg in
// play for an external display: a state, a format, and *when it last heard anything*. A wrist wants
// exactly that and for the same reason, so this is that shape again rather than a new idea — and it
// takes its freshness from there rather than choosing a second number.
//
// It is a separate object rather than `ThroVenue.shared` reused because these are two processes.
// The venue's holder lives in the phone and is written by the scoring session directly; this one
// lives in the watch and is written by whatever arrives over the link. Sharing a name across a
// process boundary would suggest they are the same holder, and the day they disagreed nobody would
// know which one was wrong.

/// The leg this watch has been handed, and when it heard it.
///
/// Not `@MainActor`, matching `ThroVenue`: the rule here is that whoever writes hops to the main
/// thread first, which `ThroWristLink` does at the one place a message arrives.
public final class ThroWrist: ObservableObject {
    public static let shared = ThroWrist()

    @Published public private(set) var state: ThroLiveState?
    @Published public private(set) var format: String = ""
    /// When this watch last heard from the phone. Staleness is judged against the **watch's own**
    /// clock at the moment of arrival, never against a timestamp inside the message: two devices
    /// are two clocks, and a wrist that trusted the sender's would be wrong by the skew.
    @Published public private(set) var heardAt: Date?

    public init() {}

    public func show(_ state: ThroLiveState, format: String) {
        self.state = state
        self.format = format
        self.heardAt = Date()
    }

    public func clear() {
        state = nil
        heardAt = nil
    }

    /// Whether what is on the wrist should still be presented as current.
    ///
    /// A decided leg is never stale — *"Ann wins"* does not go out of date — which is the rule the
    /// Lock Screen and the widgets already state, applied here rather than restated. It arrives for
    /// free through `ThroLiveCopy.caption`, and is repeated here because the numerals dim too.
    public func isStale(now: Date = Date(), after: TimeInterval = ThroWrist.freshness) -> Bool {
        guard let heardAt, state?.winner == nil else { return false }
        return now.timeIntervalSince(heardAt) > after
    }

    /// The wall screen's number, deliberately. A visit is twenty or thirty seconds, so two and a
    /// half minutes of silence during a live leg means the link has gone, not that nobody threw.
    public static let freshness: TimeInterval = ThroVenue.freshness
}

#if DEBUG
extension ThroWrist {
    /// Seeds a leg from a launch argument, so the glance can be looked at on a watch simulator with no
    /// phone attached to it.
    ///
    /// The phone app has had `-ThroScreen` for the same reason since the beginning: a screen nobody
    /// can reach without setting up a whole situation is a screen nobody looks at, and this project's
    /// rule is to look before calling something done. DEBUG only — it writes a fictional leg, and a
    /// fictional leg on a release build is a score somebody could believe.
    /// Takes an optional value the way the phone's `-ThroScreen` does — `-ThroWristDemo won` for a
    /// decided leg, `-ThroWristDemo between` for the gap between two, and nothing for a live one.
    public func seedFromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let flag = arguments.firstIndex(of: "-ThroWristDemo") else { return }
        let which = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
        show(ThroLiveState(homeName: "Jenson R.", awayName: "Ethan T.",
                           homeRemaining: which == "won" ? 0 : 81, awayRemaining: 230,
                           homeLegs: which == "won" ? 3 : 2, awayLegs: 1,
                           thrower: which == "between" ? nil : .home,
                           checkout: ["T19", "D12"],
                           winner: which == "won" ? .home : nil),
             format: "501, best of 5")
    }
}
#endif

/// The whole of the watch app's screen.
///
/// A timer ticks for the same reason the wall screen's does: nothing else will happen when the link
/// goes quiet, and a wrist showing 141 after the player has checked out is the failure this surface
/// has to avoid. On watchOS the publisher stops when the app is no longer frontmost, so this costs
/// nothing while nobody is looking at it.
public struct ThroWatchRoot: View {
    @ObservedObject private var wrist: ThroWrist
    @State private var now = Date()

    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    public init(wrist: ThroWrist = .shared) {
        _wrist = ObservedObject(wrappedValue: wrist)
    }

    public var body: some View {
        ZStack {
            ThroColor.colorBackgroundBrand.ignoresSafeArea()
            if let state = wrist.state {
                ThroWatchGlance(state: state, stale: wrist.isStale(now: now))
            } else {
                waiting
            }
        }
        .onReceive(tick) { now = $0 }
    }

    /// Nothing is being scored. It says so, rather than holding the last leg up as though it were
    /// still going — the wall screen's rule, and the honest thing on a surface glanced at for two
    /// seconds by somebody who will believe it.
    private var waiting: some View {
        VStack(spacing: 4) {
            Text("THRØ")
                .font(.system(size: 26, weight: .black))
                .tracking(3)
                .foregroundStyle(ThroColor.throChalk)
            Text(ThroWatchWords.nothingOn)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ThroColor.throChalk.opacity(0.8))
            Text(ThroWatchWords.nothingOnHint)
                .font(.system(size: 11))
                .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }
}
