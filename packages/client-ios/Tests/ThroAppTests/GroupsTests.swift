import Foundation
import XCTest
@testable import ThroApp

/// Groups, then a knockout (PD-021).
///
/// Two things here are worth checking hard. The **snake** — because dealing straight puts the
/// strongest entrants in the earliest groups, and dealing straight is what a first attempt does. And
/// the **seeding of the knockout from the group tables** — because the obvious ordering draws two
/// teams from one group against each other for some group counts and not others, which is exactly
/// the shape of a bug that survives the case somebody tried.
final class GroupsTests: XCTestCase {

    private func entrants(_ n: Int) -> [Team] {
        (1...n).map { Team(id: "t\($0)", name: "Seed \($0)") }
    }

    private func groups(_ field: [Team], count: Int, qualifiers: Int,
                        fixtures: [Fixture] = []) -> Groups {
        Groups.of(entrants: field, fixtures: fixtures, groups: count, qualifiers: qualifiers,
                  pointsForWin: 2, pointsForDraw: 1)
    }

    /// Plays every group match, letting the entrant with the **lower seed number** win — so the
    /// group tables come out in seeding order and the qualifiers are predictable.
    private func playTheGroups(_ field: [Team], count: Int, qualifiers: Int) -> [Fixture] {
        let stage = groups(field, count: count, qualifiers: qualifiers)
        var fixtures: [Fixture] = []
        for group in stage.groups {
            for match in group.matches {
                guard let sides = match.playable else { continue }
                let homeIsStronger = (field.firstIndex(of: sides.home) ?? 0)
                                   < (field.firstIndex(of: sides.away) ?? 0)
                fixtures.append(Fixture(
                    id: "g\(match.round)-\(match.slot)",
                    title: "\(sides.home.name) v \(sides.away.name)", when: "Tue", venue: "",
                    state: .played, homeTeamId: sides.home.id, awayTeamId: sides.away.id,
                    result: MatchResult(home: homeIsStronger ? 5 : 1,
                                        away: homeIsStronger ? 1 : 5,
                                        source: .recorded(by: "Pat")),
                    round: match.round, slot: match.slot, bracket: Bracket.group.rawValue))
            }
        }
        return fixtures
    }

    // MARK: - the snake

    /// **The snake, not straight dealing.** 1 to A, 2 to B, …, then back down — so group A does not
    /// collect the first and the third seed while the last group gets the two weakest.
    func testEntrantsAreDealtSnakeWiseSoOneGroupDoesNotGetAllTheStrength() {
        // Four groups: 1→A 2→B 3→C 4→D, then 5→D 6→C 7→B 8→A.
        let assigned = (1...8).map { Groups.group(ofSeed: $0, groups: 4) }
        XCTAssertEqual(assigned, [1, 2, 3, 4, 4, 3, 2, 1])

        // Straight dealing would have been [1,2,3,4,1,2,3,4] — the failure this is not.
        XCTAssertNotEqual(assigned, [1, 2, 3, 4, 1, 2, 3, 4])

        // Two groups over six: 1→A 2→B, 3→B 4→A, 5→A 6→B.
        XCTAssertEqual((1...6).map { Groups.group(ofSeed: $0, groups: 2) }, [1, 2, 2, 1, 1, 2])
    }

    /// Every entrant lands in exactly one group, and the groups differ in size by at most one — the
    /// property that makes a deal fair rather than merely varied.
    func testEveryEntrantIsInOneGroupAndTheGroupsAreEven() {
        for count in 1...6 {
            for n in max(count, 2)...16 {
                let stage = groups(entrants(n), count: count, qualifiers: 1)
                let all = stage.groups.flatMap(\.entrants)
                XCTAssertEqual(all.count, n, "\(n) entrants over \(count) groups")
                XCTAssertEqual(Set(all.map(\.id)).count, n, "nobody is in two groups")
                let sizes = stage.groups.map(\.entrants.count)
                XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1,
                                         "\(n) over \(count) gave groups of \(sizes)")
            }
        }
    }

    /// A group is a round robin: everybody meets everybody, exactly once.
    func testAGroupIsARoundRobinAndEverybodyMeetsEverybodyOnce() {
        let stage = groups(entrants(8), count: 2, qualifiers: 2)
        for group in stage.groups {
            let n = group.entrants.count
            XCTAssertEqual(group.matches.count, n * (n - 1) / 2)
            var met = Set<String>()
            for match in group.matches {
                guard let sides = match.playable else { return XCTFail("a group match with a bye") }
                let pair = [sides.home.id, sides.away.id].sorted().joined(separator: "|")
                XCTAssertFalse(met.contains(pair), "\(pair) meet twice")
                met.insert(pair)
                XCTAssertNotEqual(sides.home.id, sides.away.id)
            }
        }
    }

    // MARK: - the knockout after them

    /// **The knockout waits.** A bracket built from half-played tables shows people through who are
    /// not, which is a claim rather than a schedule.
    func testTheKnockoutIsNotDrawnUntilEveryGroupHasFinished() {
        let field = entrants(8)
        XCTAssertNil(groups(field, count: 2, qualifiers: 2).knockout, "nothing played")

        let played = playTheGroups(field, count: 2, qualifiers: 2)
        XCTAssertNil(groups(field, count: 2, qualifiers: 2,
                            fixtures: Array(played.dropLast())).knockout,
                     "one match short is still short")
        XCTAssertNotNil(groups(field, count: 2, qualifiers: 2, fixtures: played).knockout)
    }

    /// The qualifiers are the top of each table, **position-major**: every group winner, then every
    /// runner-up. With the bracket's own seeding that is what keeps a group's two qualifiers apart.
    func testTheQualifiersAreTheTopOfEachTableInPositionOrder() {
        let field = entrants(8)
        let played = playTheGroups(field, count: 2, qualifiers: 2)
        let stage = groups(field, count: 2, qualifiers: 2, fixtures: played)

        // Snake over two groups: A gets seeds 1, 4, 5, 8 and B gets 2, 3, 6, 7. The stronger seed
        // wins every match, so A's table is 1, 4, 5, 8 and B's is 2, 3, 6, 7.
        XCTAssertEqual(stage.groups[0].table.map(\.team.id), ["t1", "t4", "t5", "t8"])
        XCTAssertEqual(stage.groups[1].table.map(\.team.id), ["t2", "t3", "t6", "t7"])

        let knockout = stage.knockout
        XCTAssertEqual(knockout?.rounds.first?.count, 2, "four qualifiers is two semi-finals")
        XCTAssertEqual(knockout?.size, 4)
    }

    /// **Nobody meets their own group in the first round**, across every setup THRØ can produce:
    /// two to six groups, one to three through from each.
    ///
    /// This is the assertion the whole seeding exists for. It is checked exhaustively rather than on
    /// one example, because the failure is not uniform — it appears at some group counts and not
    /// others, which is how it survives the case somebody tried.
    func testNobodyIsDrawnAgainstTheirOwnGroupInTheFirstRound() {
        var checked = 0
        for count in 2...6 {
            for qualifiers in 1...3 {
                let field = entrants(count * 4)
                let played = playTheGroups(field, count: count, qualifiers: qualifiers)
                let stage = groups(field, count: count, qualifiers: qualifiers, fixtures: played)
                guard let knockout = stage.knockout else {
                    return XCTFail("\(count) groups, top \(qualifiers): no knockout was drawn")
                }
                var origin: [String: Int] = [:]
                for group in stage.groups {
                    for team in group.entrants { origin[team.id] = group.number }
                }
                for match in knockout.rounds[0] {
                    guard let sides = match.playable else { continue }
                    XCTAssertNotEqual(origin[sides.home.id], origin[sides.away.id],
                                      "\(count) groups, top \(qualifiers): \(sides.home.name) and "
                                      + "\(sides.away.name) are both out of one group")
                }
                XCTAssertTrue(stage.clashes.isEmpty,
                              "\(count) groups, top \(qualifiers): \(stage.clashes)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 15, "every combination was actually reached")
    }

    /// **The repair earns its place**, and these are the two setups that prove it.
    ///
    /// Ordering the qualifiers position-major is not enough on its own: with three groups and two
    /// through, the bracket pairs the second group's winner with its own runner-up, and with five
    /// groups and three through it does the same to the third. Both are clean after the repair —
    /// and if the repair is ever removed, these are the cases that will say so.
    func testTheSetupsThatNeedTheRepairAreCleanAfterIt() {
        for (count, qualifiers) in [(3, 2), (5, 3)] {
            let field = entrants(count * 4)
            let played = playTheGroups(field, count: count, qualifiers: qualifiers)
            let stage = groups(field, count: count, qualifiers: qualifiers, fixtures: played)
            XCTAssertTrue(stage.clashes.isEmpty,
                          "\(count) groups, top \(qualifiers) is the case the repair is for")

            // And the repaired order is still the same set of qualifiers — a repair may move people,
            // never add or drop them.
            let seeded = Groups.seeded(stage.groups, qualifiers: qualifiers)
            XCTAssertEqual(seeded.count, count * qualifiers)
            XCTAssertEqual(Set(seeded.map(\.id)).count, seeded.count, "nobody is seeded twice")
            for group in stage.groups {
                let through = group.table.prefix(qualifiers).map(\.team.id)
                for id in through {
                    XCTAssertTrue(seeded.contains { $0.id == id },
                                  "\(id) qualified and is not in the draw")
                }
            }
        }
    }

    /// The ordinary case, said plainly: four groups with two through produce a clean eight-team
    /// bracket in which no group's pair meet before they have to.
    func testTheCommonSetupSeparatesEveryGroupsQualifiers() {
        let field = entrants(16)
        let played = playTheGroups(field, count: 4, qualifiers: 2)
        let stage = groups(field, count: 4, qualifiers: 2, fixtures: played)
        XCTAssertTrue(stage.clashes.isEmpty, "4 groups of 4, top 2 through, must draw clean")
        XCTAssertEqual(stage.knockout?.size, 8)
    }

    // MARK: - what it refuses to guess

    /// **Nothing is defaulted.** How many groups and how many qualify decide what every match is
    /// for, so a tournament that has not been told says so instead of picking.
    func testATournamentThatHasNotBeenToldItsShapeSaysSo() {
        func tournament(count: Int?, through: Int?) -> Club {
            Club(id: "t", name: "The Feathers Open", kind: .tournament, meta: "", yourRole: .admin,
                 teams: entrants(8), shape: .groups,
                 groupCount: count, qualifiersPerGroup: through)
        }
        XCTAssertNil(tournament(count: nil, through: nil).groups)
        XCTAssertTrue(tournament(count: nil, through: nil).groupsNeedSetup)
        XCTAssertNil(tournament(count: 4, through: nil).groups, "half an answer is not one")
        XCTAssertTrue(tournament(count: 4, through: nil).groupsNeedSetup)
        XCTAssertNotNil(tournament(count: 4, through: 2).groups)
        XCTAssertFalse(tournament(count: 4, through: 2).groupsNeedSetup)

        // And only a groups tournament has them at all.
        XCTAssertNil(Club(id: "t", name: "x", kind: .tournament, meta: "", teams: entrants(8),
                          shape: .knockout, groupCount: 4, qualifiersPerGroup: 2).groups)
    }

    /// The setup is settled by the first result, like the league's unit — changing how many qualify
    /// after people have played changes what those matches were for.
    func testTheSetupSettlesOnceAResultExists() {
        let field = entrants(8)
        let open = Club(id: "t", name: "x", kind: .tournament, meta: "", yourRole: .admin,
                        teams: field, shape: .groups, groupCount: 2, qualifiersPerGroup: 2)
        XCTAssertTrue(open.setupIsStillOpen)

        let played = Club(id: "t", name: "x", kind: .tournament, meta: "", yourRole: .admin,
                          fixtures: Array(playTheGroups(field, count: 2, qualifiers: 2).prefix(1)),
                          teams: field, shape: .groups, groupCount: 2, qualifiersPerGroup: 2)
        XCTAssertFalse(played.setupIsStillOpen)
    }

    /// **A note that names a place has to carry the way there, and know when there is no way.**
    ///
    /// The tournament page used to say *"Set them on Edit"* and stop, which is a page telling
    /// somebody to go and look for something — the founder's whole complaint about this build, in
    /// one sentence. It now offers the control to an admin. That makes the wording load-bearing in
    /// three directions, and the wrong one in each is worse than saying nothing: sending a
    /// non-admin to a screen that will refuse them, telling an admin that *an admin* does this, or
    /// offering either of them a change the store will not accept because a result already exists.
    ///
    /// Held here because no test in this repository constructs a screen, which is exactly how a
    /// sentence like this rots unnoticed.
    func testTheGroupsSetupNoteSaysSomethingDifferentToEachOfItsThreeReaders() {
        let admin = TournamentScreen.groupsSetupNote(mayEdit: true, setupIsStillOpen: true)
        let watcher = TournamentScreen.groupsSetupNote(mayEdit: false, setupIsStillOpen: true)
        let tooLate = TournamentScreen.groupsSetupNote(mayEdit: true, setupIsStillOpen: false)

        XCTAssertEqual(Set([admin, watcher, tooLate]).count, 3, "two readers are told the same thing")
        XCTAssertTrue(admin.contains("Set them below"), admin)
        XCTAssertTrue(watcher.contains("An admin"), watcher)
        XCTAssertFalse(watcher.contains("Set them below"),
                       "this sends somebody without the right to a screen that refuses them: \(watcher)")

        // Once a result exists the store refuses the change, so neither reader may be told to make
        // it — a button there would look like it worked and do nothing.
        XCTAssertTrue(tooLate.contains("too late"), tooLate)
        XCTAssertEqual(TournamentScreen.groupsSetupNote(mayEdit: false, setupIsStillOpen: false),
                       tooLate, "who is reading does not change whether it is too late")
        for note in [admin, watcher, tooLate] {
            XCTAssertTrue(note.contains("THRØ asks"), "every reader is told why it is being asked")
        }
    }
}
