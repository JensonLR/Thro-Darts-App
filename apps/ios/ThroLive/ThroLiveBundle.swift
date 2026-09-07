import ActivityKit
import SwiftUI
import ThroLiveKit
import WidgetKit

// The Lock Screen and Dynamic Island scoreboard.
//
// The extension is deliberately thin: one bundle, one configuration, and the drawing comes from
// `ThroLiveKit`, which depends on the design tokens and nothing else. No journal, no engine, no
// SQLite — a process whose whole job is to show two numbers should not be linking a scoring engine.

@main
struct ThroLiveBundle: WidgetBundle {
    var body: some Widget {
        ThroMatchLiveActivity()
        // The Home Screen and Lock Screen widgets, in the same extension. A widget bundle may hold
        // both a Live Activity and static widgets, so decision 6B needed no second target — only
        // the App Group both processes read the projection through. See ThroWidgets.swift.
        ThroBoardWidget()
        ThroLockWidget()
    }
}

struct ThroMatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThroMatchActivityAttributes.self) { context in
            // The Lock Screen, and the Home Screen banner on a phone with no Dynamic Island.
            ThroLiveBoard(state: context.state,
                          format: context.attributes.format,
                          stale: context.isStale)
                .activityBackgroundTint(ThroLivePalette.field)
                .activitySystemActionForegroundColor(ThroLivePalette.onField)
                .widgetURL(URL(string: context.attributes.matchURL))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ThroLiveSide(name: context.state.homeName,
                                 remaining: context.state.homeRemaining,
                                 legs: context.state.homeLegs,
                                 throwing: ThroLiveCopy.isThrowing(context.state, .home),
                                 compact: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ThroLiveSide(name: context.state.awayName,
                                 remaining: context.state.awayRemaining,
                                 legs: context.state.awayLegs,
                                 throwing: ThroLiveCopy.isThrowing(context.state, .away),
                                 compact: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ThroLiveCopy.caption(context.state, stale: context.isStale))
                        .font(.system(size: 12, weight: context.isStale ? .semibold : .regular))
                        .foregroundStyle(context.isStale ? ThroLivePalette.onField : .secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Text("\(context.state.homeRemaining)")
                    .font(.system(size: 13, weight: .heavy)).monospacedDigit()
            } compactTrailing: {
                Text("\(context.state.awayRemaining)")
                    .font(.system(size: 13, weight: .heavy)).monospacedDigit()
            } minimal: {
                // The minimal presentation is about 45×37 points. One number fits; two do not, and
                // an image larger than the presentation can stop the activity starting at all.
                Text("\(context.state.thrower.map(context.state.remaining) ?? context.state.homeRemaining)")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
            }
            .widgetURL(URL(string: context.attributes.matchURL))
            .keylineTint(ThroLivePalette.onField)
        }
    }
}
