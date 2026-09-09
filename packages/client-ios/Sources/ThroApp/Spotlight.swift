import CoreSpotlight
import Foundation
import ThroJournal
import UniformTypeIdentifiers

// Finding a match, a person or a club from the iPhone's own search field.
//
// **What this is, and what it is not.** Apple states it plainly: the Spotlight index is on-device,
// private to the device owner, never shared with Apple, and **never synced to the user's other
// devices**. So this is not a way to look somebody up — it is the same names this phone already
// shows on Home, reachable one swipe earlier. Nothing leaves the phone, which is the claim the app
// makes everywhere else and would be the first thing to check here.
//
// Two consequences of that follow into the design rather than sitting in a comment:
//
//  - **A new phone has an empty index** until the app rebuilds it, so indexing runs on every
//    refresh rather than once at install, and is cheap enough to.
//  - **The player can turn it off**, and turning it off *removes* what was indexed rather than
//    stopping future writes. A switch that left the old entries behind would be a switch that lies.
//
// The identifier of every item is the route's own URL. One identity scheme rather than two: a tap
// hands back the string, `ThroRoute(url:)` reads it, and the router goes there. There is no second
// mapping to drift.

public enum ThroSpotlight {
    /// The player's answer, stored. Default on.
    public static let enabledKey = "thro.spotlight"

    /// The domains, so a kind can be forgotten in one call.
    enum Domain: String, CaseIterable {
        case match = "app.thro.darts.match"
        case person = "app.thro.darts.person"
        // The string is what the iPhone's index already holds for every organisation on the phone,
        // so it is kept while the case says what the thing is (ADR-017).
        case organisation = "app.thro.darts.club"
    }

    /// What a searchable item for one route looks like.
    ///
    /// Split out from the indexing so it can be tested without CoreSpotlight's index, which needs a
    /// real system service and is not available in a unit test on a build server.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let domain: String
        public let title: String
        public let subtitle: String?
        public let keywords: [String]

        public init(id: String, domain: String, title: String, subtitle: String?, keywords: [String]) {
            self.id = id
            self.domain = domain
            self.title = title
            self.subtitle = subtitle
            self.keywords = keywords
        }
    }

    /// Everything this device can be searched for.
    ///
    /// A match is named by its two players because that is how somebody looks for it — *"the one
    /// against Dave"* — and never by a figure, because a figure without its sample is a claim (the
    /// same rule Home's week strip follows). A match still in progress says so in its subtitle, so
    /// a search result cannot imply a finished game.
    public static func entries(matches: [AppStore.HomeMatch],
                               people: [LocalPerson],
                               clubs: [Club]) -> [Entry] {
        var out: [Entry] = []
        for match in matches {
            let record = match.record
            let title = "\(record.homeName) v \(record.awayName)"
            let state = match.complete ? "\(match.legsHome)–\(match.legsAway)" : "In progress"
            out.append(Entry(id: ThroRoute.match(record.id).url.absoluteString,
                             domain: Domain.match.rawValue,
                             title: title,
                             subtitle: "\(state) · \(Self.day.string(from: record.startedAt))",
                             keywords: [record.homeName, record.awayName, "match", "darts"]))
        }
        for person in people {
            out.append(Entry(id: ThroRoute.person(person.id).url.absoluteString,
                             domain: Domain.person.rawValue,
                             title: person.name,
                             subtitle: "Plays on this phone",
                             keywords: [person.name, "player"]))
        }
        for club in clubs {
            out.append(Entry(id: ThroRoute.club(club.id).url.absoluteString,
                             domain: Domain.organisation.rawValue,
                             title: club.name,
                             subtitle: club.kind.label,
                             keywords: [club.name, club.kind.label]))
        }
        return out
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Puts everything this device holds into the index, replacing whatever was there.
    ///
    /// `deleteSearchableItems(withDomainIdentifiers:)` first, so a match that has been deleted or a
    /// person who has been removed does not linger as a result that opens nothing. The alternative
    /// — indexing additively and hoping — is how a search result outlives the thing it names.
    public static func index(matches: [AppStore.HomeMatch],
                             people: [LocalPerson],
                             clubs: [Club],
                             enabled: Bool) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let index = CSSearchableIndex(name: "app.thro.darts")
        guard enabled else { return forget(index) }
        index.deleteSearchableItems(withDomainIdentifiers: Domain.allCases.map(\.rawValue)) { _ in
            let items = entries(matches: matches, people: people, clubs: clubs).map { entry -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
                attributes.title = entry.title
                attributes.contentDescription = entry.subtitle
                attributes.keywords = entry.keywords
                return CSSearchableItem(uniqueIdentifier: entry.id,
                                        domainIdentifier: entry.domain,
                                        attributeSet: attributes)
            }
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// Removes everything. Called when the player turns the switch off, so that turning it off
    /// clears what was already there rather than only stopping new entries.
    public static func forget(_ index: CSSearchableIndex = CSSearchableIndex(name: "app.thro.darts")) {
        index.deleteSearchableItems(withDomainIdentifiers: Domain.allCases.map(\.rawValue)) { _ in }
    }

    /// The place a tapped result names.
    ///
    /// The system hands back exactly the `uniqueIdentifier` that was indexed, under
    /// `CSSearchableItemActivityIdentifier`. Because that identifier is the route's own URL, this is
    /// a parse rather than a lookup — there is no table that can fall out of step with the index.
    public static func route(for activity: NSUserActivity) -> ThroRoute? {
        guard activity.activityType == CSSearchableItemActionType,
              let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: raw) else { return nil }
        return ThroRoute(url: url)
    }
}
