import SwiftUI
import ThroTokens

// What a widget draws, and the words it uses.
//
// In `ThroLiveKit` beside the Live Activity's views and for the same reasons: the widget extension
// links this and nothing else, the copy is the part that can be wrong, and both of those mean the
// words live in a type rather than inside a `Text`.
//
// **The system's typeface again.** Archivo and IBM Plex Sans Condensed are registered by the app's
// `UIAppFonts`; an extension asking for them by name would look right in a preview and silently
// fall back on a phone. A brand is worth more than a font, and a wrong font is worse than none.

/// The words on a widget.
public enum ThroWidgetCopy {
    /// The line under a live scoreboard, which either states the position or says it may not be
    /// current any more.
    ///
    /// The rule is the Lock Screen's, applied to a surface the app cannot renew. WidgetKit refreshes
    /// when it chooses; a score on the Home Screen can be hours behind the phone it is on and looks
    /// exactly as current as one written a second ago. A **decided match outranks staleness**,
    /// because *"Ann wins"* does not go out of date.
    public static func caption(_ projection: ThroProjection, now: Date = Date()) -> String {
        guard let live = projection.live else { return "" }
        if let winner = live.winner { return "\(live.name(winner)) wins" }
        guard !projection.isStale(now: now) else { return "May be out of date — open THRØ" }
        guard let thrower = live.thrower else { return projection.liveFormat }
        return "\(live.name(thrower)) to throw"
    }

    /// What a phone with nothing being scored shows. **Counts, never averages**: a count carries its
    /// own sample, and a widget has no room for the basis an average needs.
    public static func idle(_ projection: ThroProjection) -> String {
        switch (projection.matches, projection.legsThisWeek) {
        case (0, _):
            return "No matches on this phone yet"
        case (let matches, 0):
            return "\(matches) match\(matches == 1 ? "" : "es") · none this week"
        case (let matches, let legs):
            return "\(matches) match\(matches == 1 ? "" : "es") · \(legs) leg\(legs == 1 ? "" : "s") this week"
        }
    }

    /// The next fixture, or nil when there is none ahead.
    public static func fixture(_ projection: ThroProjection, now: Date = Date()) -> (String, String)? {
        guard let next = projection.nextFixture, next.at > now else { return nil }
        let when = Self.when.string(from: next.at)
        let venue = next.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (next.title, venue.isEmpty ? when : "\(when) · \(venue)")
    }

    /// **Where the widget goes when it is tapped: whatever it is currently showing.**
    ///
    /// It went to *continue the match* in every state, including the two that are not a match. A
    /// widget reading *Tuesday · Feathers v Bell · 8pm* opened the Play tab with nothing on it —
    /// which is not a crash, not an error, and not what anybody tapping that widget meant. A
    /// destination that ignores what is drawn above it is a link to somewhere else's content.
    ///
    /// Three states, three places, and each one is the screen that holds what the widget is showing:
    /// the match being scored, the list of every fixture this phone's clubs have not finished with,
    /// or — on a phone with neither — the one action that is real.
    public static func destination(_ projection: ThroProjection?, now: Date = Date()) -> URL {
        guard let projection else { return ThroLink.url(path: "new") }
        if projection.live != nil { return ThroLink.url(path: "continue") }
        if fixture(projection, now: now) != nil { return ThroLink.url(path: "tab/live") }
        return ThroLink.url(path: "new")
    }

    static let when: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()
}

/// The board a widget draws: a live leg when there is one, and what this phone holds when there is
/// not.
///
/// One view for both sizes, laid out from the space it is given rather than from a size enum, so a
/// small widget and a medium one cannot drift apart in what they claim.
public struct ThroWidgetBoard: View {
    private let projection: ThroProjection?
    private let now: Date
    private let wide: Bool

    public init(projection: ThroProjection?, now: Date = Date(), wide: Bool = false) {
        self.projection = projection
        self.now = now
        self.wide = wide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let projection, let live = projection.live {
                scoreboard(live, projection)
            } else {
                waiting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scoreboard(_ live: ThroLiveState, _ projection: ThroProjection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                side(live.homeName, live.homeRemaining, live.homeLegs,
                     throwing: ThroLiveCopy.isThrowing(live, .home))
                side(live.awayName, live.awayRemaining, live.awayLegs,
                     throwing: ThroLiveCopy.isThrowing(live, .away))
            }
            let caption = ThroWidgetCopy.caption(projection, now: now)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: wide ? 13 : 11,
                                  weight: projection.isStale(now: now) ? .semibold : .regular))
                    .foregroundStyle(projection.isStale(now: now)
                                     ? ThroLivePalette.onField : ThroColor.throChalk.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func side(_ name: String, _ remaining: Int, _ legs: Int, throwing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                // Marked, not merely coloured: a dot survives Increase Contrast, Differentiate
                // Without Color, and a glance from across a room.
                Circle()
                    .fill(throwing ? ThroLivePalette.onField : Color.clear)
                    .frame(width: 5, height: 5)
                Text(name)
                    .font(.system(size: wide ? 13 : 11, weight: throwing ? .semibold : .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 1 : 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(remaining)")
                    .font(.system(size: wide ? 40 : 32, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(ThroColor.throChalk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(legs)")
                    .font(.system(size: wide ? 15 : 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(throwing ? "\(name), to throw" : name)
        .accessibilityValue("\(remaining), \(legs) leg\(legs == 1 ? "" : "s")")
    }

    /// Nothing is being scored. What this phone holds, in counts — and the next fixture, which is
    /// the one thing somebody looking at a darts widget on a Tuesday actually wants.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THRØ")
                .font(.system(size: wide ? 17 : 15, weight: .black))
                .tracking(2)
                .foregroundStyle(ThroColor.throChalk)
            if let projection, let (title, detail) = ThroWidgetCopy.fixture(projection, now: now) {
                Text(title)
                    .font(.system(size: wide ? 15 : 13, weight: .semibold))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.9))
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: wide ? 12 : 10, weight: .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(projection.map(ThroWidgetCopy.idle) ?? "Open THRØ")
                .font(.system(size: wide ? 12 : 10, weight: .regular))
                .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}
