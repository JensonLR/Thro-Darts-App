import Foundation
import XCTest
@testable import ThroApp

/// Clubs, leagues and profiles on the phone (PD-009, PD-010).
///
/// These are the same three rules `packages/organisation` states in Kotlin. They are restated in
/// Swift because a screen has to know what to draw before anything has been asked of a server, and
/// they are asserted here in the same shape so the two cannot drift silently: **the Kotlin is the
/// reference, and when a server exists the server is authoritative.** This copy decides what a
/// screen shows, never what a person may do.
final class ClubStateTests: XCTestCase {

    private func member(_ id: String, _ role: OrgRole = .member, _ band: AgeBand = .adult) -> ClubMember {
        ClubMember(id: id, name: "\(id.uppercased()) Player", role: role, ageBand: band, joined: "2024")
    }

    private func club(role: OrgRole?, members: [ClubMember] = []) -> Club {
        Club(id: "c", name: "The Feathers A", kind: .club, meta: "Crediton · 24 members",
             yourRole: role, members: members,
             fixtures: [Fixture(id: "f1", title: "Feathers A v Ship Inn", when: "Tue 15 Sep", venue: "The Feathers"),
                        Fixture(id: "f2", title: "Ship Inn v Feathers A", when: "Tue 8 Sep", venue: "The Ship Inn", state: .played)])
    }

    /// A public front and a private inside. A stranger may open the page and nothing else.
    func testAStrangerSeesTheFrontAndNothingElse() {
        let outside = club(role: nil, members: [member("a"), member("b")])
        XCTAssertFalse(outside.isMember)
        XCTAssertEqual(outside.visibleMembers, [], "the membership list is not public")
        XCTAssertFalse(outside.mayAnnounce)
        XCTAssertFalse(outside.mayManageFixtures)
        XCTAssertFalse(outside.mayManageMembers)
        // But the fixtures the front shows are there to be shown.
        XCTAssertEqual(outside.fixtures.filter { !$0.state.isTerminal }.count, 1)
    }

    /// A member recorded as a minor — or whose age is not established, treated the same way — is
    /// listed only to an admin. Not to an official either: running a club is not a reason to see a
    /// child. And the count of who is hidden is a property, so a screen can say it rather than
    /// quietly showing a shorter list.
    func testAMinorIsListedOnlyToAnAdminAndTheHiddenCountIsSayable() {
        let people = [member("adult", .member, .adult),
                      member("junior", .member, .minor),
                      member("unstated", .official, .unknown),
                      member("pat", .admin, .adult)]

        for role in [OrgRole.member, .official] {
            let c = club(role: role, members: people)
            XCTAssertEqual(c.visibleMembers.map(\.id), ["adult", "pat"], "\(role) sees the adults only")
            XCTAssertEqual(c.hiddenMembers, 2, "and is told there are two they cannot see")
        }
        let asAdmin = club(role: .admin, members: people)
        XCTAssertEqual(asAdmin.visibleMembers.count, 4, "an admin sees everybody, because somebody has to")
        XCTAssertEqual(asAdmin.hiddenMembers, 0)
        // The list and the count always add up, whoever is looking.
        for role in [OrgRole.member, .official, .admin] {
            let c = club(role: role, members: people)
            XCTAssertEqual(c.visibleMembers.count + c.hiddenMembers, people.count)
        }
    }

    /// An app with no answer to OD-010 cannot message a child — and the sender is told, before they
    /// send, exactly who it will not reach and why.
    func testAnAnnouncementCountsWhoItWillNotReachAndNamesTheReason() {
        let people = [member("a1", .member, .adult), member("a2", .member, .adult),
                      member("j1", .member, .minor), member("j2", .member, .minor),
                      member("u1", .member, .unknown)]
        let c = club(role: .official, members: people)

        let d = c.delivery
        XCTAssertEqual(d.reaches, 2)
        XCTAssertEqual(d.of, 5)
        XCTAssertEqual(d.withheld.minors, 2)
        XCTAssertEqual(d.withheld.ageNotGiven, 1)
        XCTAssertEqual(d.withheld.total, 3)
        XCTAssertEqual(d.reaches + d.withheld.total, d.of, "everybody is in exactly one of the two")

        // Two reasons, in the order the screen shows them, each naming its own count.
        let lines = d.withheld.lines
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].count, "2 members under 18")
        XCTAssertTrue(lines[0].why.contains("safeguarding advice"), lines[0].why)
        XCTAssertEqual(lines[1].count, "1 member whose age is not given")
        XCTAssertTrue(lines[1].why.contains("whether they are a child"), lines[1].why)

        // Singular and plural both read as English, because a count of one is the common case.
        let one = Withheld(minors: 1, ageNotGiven: 0)
        XCTAssertEqual(one.lines.first?.count, "1 member under 18")
        XCTAssertEqual(Withheld(minors: 0, ageNotGiven: 0).lines.count, 0, "nothing said when nobody is withheld")

        // A club of adults reaches all of them and says nothing about it.
        let allAdults = club(role: .official, members: [member("a1"), member("a2")])
        XCTAssertEqual(allAdults.delivery.reaches, 2)
        XCTAssertEqual(allAdults.delivery.withheld.total, 0)
    }

    /// Only an official or an admin may announce or move a fixture; only an admin may change who
    /// belongs. The same table `Permissions` states in Kotlin.
    func testTheAuthorityTableIsTheSameOneTheDomainStates() {
        let expected: [OrgRole?: (announce: Bool, fixtures: Bool, members: Bool)] = [
            nil: (false, false, false),
            .member: (false, false, false),
            .official: (true, true, false),
            .admin: (true, true, true),
        ]
        for (role, want) in expected {
            let c = club(role: role)
            XCTAssertEqual(c.mayAnnounce, want.announce, "announce as \(String(describing: role))")
            XCTAssertEqual(c.mayManageFixtures, want.fixtures, "fixtures as \(String(describing: role))")
            XCTAssertEqual(c.mayManageMembers, want.members, "members as \(String(describing: role))")
        }
        XCTAssertTrue(OrgRole.member < .official && OrgRole.official < .admin, "the roles are ordered")
    }

    /// Small things the screens depend on and would render wrongly if they changed.
    func testInitialsFixtureStatesAndTheThingsTheScreensRead() {
        // At most three letters, and the words every club's name shares carry none of them.
        XCTAssertEqual(club(role: nil).initials, "FA", "\"The Feathers A\" is FA, not TFA")
        XCTAssertEqual(Club(id: "x", name: "Mid-Devon League", kind: .league, meta: "").initials, "MDL",
                       "a hyphen is a word break")
        XCTAssertEqual(Club(id: "x", name: "Summer Cup 2026", kind: .tournament, meta: "").initials, "SC2")
        // "A" is not dropped: Feathers A and Feathers B are different clubs and must not share a badge.
        XCTAssertEqual(Club(id: "x", name: "The Feathers B", kind: .club, meta: "").initials, "FB")
        XCTAssertNotEqual(Club(id: "x", name: "The Feathers A", kind: .club, meta: "").initials,
                          Club(id: "y", name: "The Feathers B", kind: .club, meta: "").initials)
        XCTAssertEqual(member("jl").initials, "JP", "a person's initials come from their name")

        XCTAssertTrue(FixtureState.played.isTerminal)
        XCTAssertTrue(FixtureState.cancelled.isTerminal)
        XCTAssertFalse(FixtureState.scheduled.isTerminal)
        XCTAssertFalse(FixtureState.postponed.isTerminal, "a postponed fixture is still going to happen")
        XCTAssertEqual(FixtureState.postponed.label, "Postponed")
        XCTAssertEqual(OrgKind.tournament.label, "Tournament")
        // A club that has chosen no colour has none, rather than a colour engineering chose for it.
        XCTAssertNil(club(role: nil).accentHex)
    }
}
