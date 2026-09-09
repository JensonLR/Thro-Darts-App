import Foundation
import SwiftUI
import ThroTokens

// The board on the wall.
//
// **What a venue actually has, and what this serves.** A pub with a spare HDMI port and a £50
// adapter. Not a Chromecast, which iOS cannot drive without a third-party SDK and a registered
// receiver; not a smart-TV browser, which needs a hosted page and therefore a server; and not an
// Apple TV as the plan, because pub guest Wi-Fi commonly isolates clients and AirPlay discovery dies
// with it. AirPlay still works when it works — the system creates the same scene for a mirrored
// display as for a wired one, so it comes free — but a cable is the thing that never fails.
//
// The state lives here, in the module the app shares with its extensions, for the same reason the
// link contract does: `ThroPlay` produces it and the app target's scene delegate consumes it, and
// neither can see the other.

/// What the venue screen is showing.
public final class ThroVenue: ObservableObject {
    public static let shared = ThroVenue()

    @Published public private(set) var state: ThroLiveState?
    @Published public private(set) var format: String = ""
    /// When the board last heard anything. The wall screen uses this exactly as the Lock Screen uses
    /// `staleDate`: a room full of people reading a score is the worst place to show one that has
    /// quietly stopped being true.
    @Published public private(set) var heardAt: Date?

    private init() {}

    public func show(_ state: ThroLiveState, format: String) {
        self.state = state
        self.format = format
        self.heardAt = Date()
    }

    public func clear() {
        state = nil
        heardAt = nil
    }

    /// Whether what is on the wall should still be presented as current.
    public func isStale(now: Date = Date(), after: TimeInterval = ThroVenue.freshness) -> Bool {
        guard let heardAt else { return false }
        return now.timeIntervalSince(heardAt) > after
    }

    public static let freshness: TimeInterval = 150
}

/// The scoreboard, at the size a room reads it from.
///
/// Deliberately not the phone's layout scaled up. A wall screen is read from six metres by people
/// who are not holding it: two names, two numbers, the legs, and one line saying whose throw it is.
/// Nothing that needs walking closer.
public struct ThroVenueBoard: View {
    private let state: ThroLiveState?
    private let format: String
    private let stale: Bool

    public init(state: ThroLiveState?, format: String, stale: Bool) {
        self.state = state
        self.format = format
        self.stale = stale
    }

    public var body: some View {
        ZStack {
            ThroColor.colorBackgroundBrand.ignoresSafeArea()
            if let state {
                board(state)
            } else {
                waiting
            }
        }
    }

    private func board(_ state: ThroLiveState) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                side(name: state.homeName, remaining: state.homeRemaining, legs: state.homeLegs,
                     throwing: ThroLiveCopy.isThrowing(state, .home))
                Rectangle()
                    .fill(ThroColor.throChalk.opacity(0.18))
                    .frame(width: 2)
                    .padding(.vertical, 40)
                side(name: state.awayName, remaining: state.awayRemaining, legs: state.awayLegs,
                     throwing: ThroLiveCopy.isThrowing(state, .away))
            }
            .frame(maxHeight: .infinity)

            Text(ThroLiveCopy.caption(state, stale: stale))
                .font(.system(size: 34, weight: stale ? .bold : .semibold))
                .foregroundStyle(stale ? ThroColor.throBronzeOnink : ThroColor.throChalk.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.bottom, 8)
            Text(format.uppercased())
                .font(.system(size: 20, weight: .medium))
                .tracking(3)
                .foregroundStyle(ThroColor.throChalk.opacity(0.45))
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 48)
    }

    private func side(name: String, remaining: Int, legs: Int, throwing: Bool) -> some View {
        VStack(spacing: 10) {
            Text(name.uppercased())
                .font(.system(size: 40, weight: throwing ? .heavy : .semibold))
                .tracking(2)
                .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 1 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("\(remaining)")
                .font(.system(size: 220, weight: .black))
                .monospacedDigit()
                .foregroundStyle(ThroColor.throChalk)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("\(legs)")
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(throwing ? ThroColor.throGreenOnink : ThroColor.throChalk.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Nothing is being scored. The board says exactly that rather than holding the last match up as
    /// though it were still going — a wall screen showing a finished leg to a room is worse than one
    /// showing nothing.
    private var waiting: some View {
        VStack(spacing: 18) {
            Text("THRØ")
                .font(.system(size: 96, weight: .black))
                .tracking(6)
                .foregroundStyle(ThroColor.throChalk)
            Text("No match on this phone")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(ThroColor.throChalk.opacity(0.55))
        }
    }
}
