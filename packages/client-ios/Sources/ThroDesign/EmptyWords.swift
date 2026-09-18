import Foundation

// What THRØ says when there is nothing to show — in one place, so it can be tested rather than
// looked at.
//
// **The rule, written down here because prose does not compile.**
//
//   *The board when the emptiness is the whole page; the card when it is a section.*
//
// `ThroNothingYet` is the board: the green field with the lamp and the chalk. It fills any screen by
// construction, which is why it is the answer when the empty state **is** the page. `EmptyState` is
// the card, and a card is right for a section that is empty among sections that are not — a
// tournaments list with nothing in it, sitting under leagues that do exist, reads correctly as one
// part of a page. Reach for the card on a page with nothing else on it and you get a notice pinned
// to the top of a sheet of cream, which is the failure `NothingYet.swift` was written about.
//
// **Two deliberate exceptions, recorded so nobody has to rediscover them.**
//
//   - *The inbox* carries no action. It is the one empty state in the app that is a good outcome:
//     nobody needs anything from you. Inventing a button for it would mirror a noun that is not
//     missing.
//   - *The blocked list* stays a card although it is the whole page. The field with a lamp is the
//     app's welcome, and a cheerful green invitation on the safety screen would be the wrong
//     register. The rule holds; this is the exception worth writing down rather than silently
//     breaking.
//
// **The ceiling is fourteen words.** A body is the sentence a reader takes in while looking at a
// screen with nothing on it, which is the moment they have least patience for a paragraph. Nine of
// the nineteen bodies in this app were over it, and the longest was thirty-eight words, because a
// body is the easiest place in a codebase to answer a question nobody asked. Held by
// `EmptyWordsTests`, not by good intentions.
//
// One body is not held here and says so: the *not enough teams* sentence on the add-a-fixture
// screen is composed at runtime from how many are entered and whether the reader may keep the list,
// so it lives beside the screen that builds it (`NewTeamFixtureScreen.notEnoughNote`) and is tested
// there.

/// One empty state's words: what it calls itself, what it says, and what it offers.
///
/// `place` is for a failing test to name, never for a reader. `title` is optional because a few of
/// these sit under a section header that already names them, and repeating it would say it twice.
/// `actionLabel` is `nil` both where there is deliberately no action and where the label is built
/// from a noun the screen knows and this file does not.
public struct EmptyWords: Sendable, Equatable {
    public let place: String
    public let title: String?
    public let body: String
    public let actionLabel: String?

    public init(place: String, title: String?, body: String, actionLabel: String? = nil) {
        self.place = place
        self.title = title
        self.body = body
        self.actionLabel = actionLabel
    }

    /// How many words the body is. Whitespace-separated, which is what a reader counts.
    public var bodyWordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// The ceiling a body is held to.
    public static let ceiling = 14
}

extension EmptyWords {

    // MARK: - the board: the emptiness is the page

    /// Home, before this phone has scored anything.
    ///
    /// The second sentence — *nothing is sent anywhere unless you send it* — was cut. The promise is
    /// already made in six other places, and this is the screen a player reaches before they have
    /// anything to be reassured about, which is where it read as least necessary and most defensive.
    public static let home = EmptyWords(
        place: "Home",
        title: "No matches yet",
        body: "Score a match on this device and it will appear here.",
        actionLabel: "Start match")

    /// The shelf, with nothing on it.
    public static let archive = EmptyWords(
        place: "Archived",
        title: "Nothing archived",
        body: "Matches you put away from Home appear here.")

    /// The signed-in player's inbox. No action, by the exception recorded above.
    public static let inbox = EmptyWords(
        place: "Your inbox",
        title: "Nothing waiting on you",
        body: "Nobody needs anything from you just now.")

    /// Darts you can play, when no organiser has opened one.
    public static let discovery = EmptyWords(
        place: "Darts you can play",
        title: "Nothing open just now",
        body: "No organiser has opened an event you can enter.",
        actionLabel: "See the leagues")

    /// A team that was on this device and is not.
    public static let teamGone = EmptyWords(
        place: "A team that is gone",
        title: "That team is gone",
        body: "It is no longer on this device.",
        actionLabel: "Back to teams")

    // MARK: - the card: the emptiness is a section

    /// The Live tab with nothing going on.
    public static let live = EmptyWords(
        place: "Live",
        title: "Nothing on right now",
        body: "A match you are scoring shows here while it is going, and so do fixtures your "
            + "teams have not finished with.",
        actionLabel: "Start match")

    /// The leagues board, if THRØ is ever holding no leagues at all.
    ///
    /// Not *for this area*: the read asks for every league THRØ holds and passes no locality, so
    /// that clause named a filter which was never applied.
    public static let leaguesOnTheMap = EmptyWords(
        place: "The leagues board",
        title: "No leagues yet",
        body: "THRØ has no leagues on the map yet.")

    /// The tournaments section of Discover. No title: the section header above it is the title.
    public static let tournaments = EmptyWords(
        place: "Discover · tournaments",
        title: nil,
        body: "No tournament is taking entries on THRØ just now.",
        actionLabel: "Open the organiser's desk")

    /// A team's roster, to somebody who may add to it.
    ///
    /// Why an age is asked belongs on the screen that asks for it, not on the screen before.
    public static let roster = EmptyWords(
        place: "A team's roster",
        title: "Nobody here yet",
        body: "Add the people who play for this team.",
        actionLabel: "Add a member")

    /// A team's roster, to somebody who may not.
    public static let rosterKept = EmptyWords(
        place: "A team's roster, to a non-admin",
        title: "Nobody here yet",
        body: "An admin keeps the roster.")

    /// A team's fixtures, to somebody who may add one.
    public static let fixtures = EmptyWords(
        place: "A team's fixtures",
        title: "No fixtures yet",
        body: "Add one and it appears on the team's public page.",
        actionLabel: "Add a fixture")

    /// A team's fixtures, to somebody who may not.
    public static let fixturesKept = EmptyWords(
        place: "A team's fixtures, to a non-official",
        title: "No fixtures yet",
        body: "An official adds them.")

    /// A tournament with nobody in it. The action's label is built from the competitor noun.
    public static let entrants = EmptyWords(
        place: "A tournament's entrants",
        title: "Nobody entered yet",
        body: "Add everybody who is playing. The order they go in is the order the byes are "
            + "given out.")

    /// A league with no teams. The action's label is built from the competitor noun.
    public static let teams = EmptyWords(
        place: "A league's teams",
        title: "No teams yet",
        body: "A league is its teams. Add them, then the fixtures between them.")

    /// Either of the two above, to somebody who may not keep the list.
    public static let listKept = EmptyWords(
        place: "A league's teams, to a non-admin",
        title: nil,
        body: "An admin keeps this list.")

    /// A league table before any fixture carries a result.
    ///
    /// That THRØ derives the table rather than storing one is a claim about THRØ, not about this
    /// league; it sits in the note that already names the ordering rules.
    public static let table = EmptyWords(
        place: "A league table",
        title: "No results yet",
        body: "The table fills in as fixtures start carrying results.")

    /// The blocked list. A card although it is the page — the second recorded exception.
    ///
    /// What blocking does, and where the control is, moved to a note under the card. They are an
    /// explanation and a route, and neither belongs inside the sentence a distressed reader parses
    /// first.
    public static let blocked = EmptyWords(
        place: "Blocked",
        title: "Nobody is blocked",
        body: "Nobody you have blocked can reach you on THRØ.")

    /// Every empty state whose words live here, so a test can walk them.
    public static let every: [EmptyWords] = [
        home, archive, inbox, discovery, teamGone,
        live, leaguesOnTheMap, tournaments, roster, rosterKept, fixtures, fixturesKept,
        entrants, teams, listKept, table, blocked,
    ]

    /// The bodies still over the ceiling, and why they are still here.
    ///
    /// **This is a debt list, not a licence.** Each of these was outside the survey that cut the
    /// others, so cutting it now would be writing copy nobody has decided on. The test holds the
    /// list closed from both ends: nothing may be added to it without a reason, and a body that is
    /// brought under the ceiling must be taken out of it, or the test fails for the opposite reason.
    public static let overTheCeiling: [String: String] = [
        live.place: "Twenty-one words. The Live tab's own rework is held by an unanswered question "
            + "about whether that page should be shortened or anchored, and this sentence belongs "
            + "to whichever answer wins.",
        entrants.place: "Eighteen words. The second sentence explains how byes are given out, which "
            + "is a rule of the draw rather than a description of an empty list; where it should go "
            + "has not been decided.",
    ]
}
