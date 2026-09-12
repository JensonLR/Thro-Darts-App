import SwiftUI
import ThroLiveKit
import WidgetKit

// The Home Screen and Lock Screen widgets.
//
// **They read a file, not the journal.** ADR-006 measured the journal in Application Support and it
// stays there; what this reads is the small regenerable projection the app writes into the App Group
// container — see `ThroLiveKit/Projection.swift`. A widget process that linked SQLite and a scoring
// engine to draw four numbers would be paying for the whole app to show a scoreboard.
//
// **The timeline is one entry and a short refresh.** There is nothing to extrapolate: a widget
// cannot know what the next visit will be, and a timeline of guesses is a scoreboard inventing
// darts. So it draws what the file said and asks to be woken again — and if the system does not
// come back, the entry's own age makes the caption say so rather than letting an old score stand.

struct ThroProjectionEntry: TimelineEntry {
    let date: Date
    let projection: ThroProjection?
}

struct ThroProjectionProvider: TimelineProvider {
    /// What the gallery shows while the widget is being chosen. Deliberately the empty state rather
    /// than an invented match: a preview showing "Ann 141 · Bea 220" would be a scoreline this
    /// phone has never seen, offered to somebody deciding whether to trust the app.
    func placeholder(in context: Context) -> ThroProjectionEntry {
        ThroProjectionEntry(date: Date(), projection: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ThroProjectionEntry) -> Void) {
        completion(ThroProjectionEntry(date: Date(), projection: ThroProjectionStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThroProjectionEntry>) -> Void) {
        let now = Date()
        let entry = ThroProjectionEntry(date: now, projection: ThroProjectionStore.read())
        // Ask again inside the freshness window, so a live match usually stays current — and past
        // it the caption says the score may be out of date rather than asserting it. WidgetKit
        // budgets refreshes and may ignore this; that is exactly why the honesty is in the entry.
        let again = now.addingTimeInterval(ThroProjection.freshness / 2)
        completion(Timeline(entries: [entry], policy: .after(again)))
    }
}

/// The scoreboard, on the Home Screen.
struct ThroBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.thro.darts.board", provider: ThroProjectionProvider()) { entry in
            ThroWidgetBoard(projection: entry.projection, now: entry.date, wide: false)
                .containerBackground(ThroLivePalette.field, for: .widget)
                // Wherever the widget is actually showing — see ThroWidgetCopy.destination.
                .widgetURL(ThroWidgetCopy.destination(entry.projection))
        }
        .configurationDisplayName("Match")
        .description("The leg being scored on this phone, or what is next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The same board, on the Lock Screen, where the system draws in one colour and nothing else fits.
struct ThroLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.thro.darts.lock", provider: ThroProjectionProvider()) { entry in
            ThroLockLine(entry: entry)
                .containerBackground(.clear, for: .widget)
                // Wherever the widget is actually showing — see ThroWidgetCopy.destination.
                .widgetURL(ThroWidgetCopy.destination(entry.projection))
        }
        .configurationDisplayName("THRØ")
        .description("The two remainders, on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

/// **Tinted, not coloured.** An accessory family is rendered in a single system colour whatever the
/// view asks for, so nothing here may lean on a colour to mean something — which is why the thrower
/// is marked with a symbol rather than a green name, and why staleness is a word.
private struct ThroLockLine: View {
    let entry: ThroProjectionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryInline {
            Text(inline)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(inline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let projection = entry.projection {
                    Text(ThroWidgetCopy.caption(projection, now: entry.date).isEmpty
                         ? ThroWidgetCopy.idle(projection)
                         : ThroWidgetCopy.caption(projection, now: entry.date))
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
        }
    }

    /// One line, which is all `accessoryInline` gets. The thrower is marked with a chevron because
    /// the family has no second colour to mark them with.
    private var inline: String {
        guard let live = entry.projection?.live else { return "THRØ" }
        let home = ThroLiveCopy.isThrowing(live, .home) ? "▸\(live.homeName)" : live.homeName
        let away = ThroLiveCopy.isThrowing(live, .away) ? "▸\(live.awayName)" : live.awayName
        return "\(home) \(live.homeRemaining) · \(away) \(live.awayRemaining)"
    }
}
