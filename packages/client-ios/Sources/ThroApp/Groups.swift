import Foundation

// Groups, then a knockout (PD-021).
//
// Two numbers decide everything here — how many groups, and how many go through from each — and
// **neither is THRØ's to pick**. They are set before a tournament starts, they decide what every
// match in it is for, and a tournament that guessed them would be telling its entrants something
// nobody chose. So `Club.groups` is nil until an admin says, and the page asks rather than defaults.
//
// Everything after that is arithmetic, and one piece of it is the trap: **seeding the knockout from
// the group tables**. The obvious ordering — all the group winners, then all the runners-up — puts
// two teams from the same group against each other in the first round for some group counts and not
// others, which is exactly the kind of thing that looks right in the case somebody tried.

/// A groups tournament: the groups themselves, and the knockout the qualifiers feed.
public struct Groups: Equatable, Sendable {
    /// One group: who is in it, and where they stand.
    public struct Group: Identifiable, Equatable, Sendable {
        public let number: Int
        public let entrants: [Team]
        public let table: [TableRow]
        /// Every match this group plays — a round robin, so everybody meets everybody.
        public let matches: [DrawMatch]

        public var id: Int { number }
        /// A, B, C… which is what a group is called out loud.
        public var name: String {
            String(UnicodeScalar(UInt8(65 + (number - 1) % 26)))
        }
        public var isComplete: Bool { matches.allSatisfy { $0.fixture?.result != nil } }
    }

    public let groups: [Group]
    /// The knockout the qualifiers play, once every group is finished. Nil until then — a bracket
    /// built from half-finished tables would show people through who are not.
    public let knockout: Draw?
    public let qualifiersPerGroup: Int

    /// Which group an entrant is in, **snake-wise over the entry order**.
    ///
    /// Seed 1 to group A, 2 to B, … , k to the last, then back down: k+1 to the last, k+2 to the one
    /// before. Straight dealing (1→A, 2→B, 3→A, 4→B) stacks the strongest entrants into the earliest
    /// groups; the snake is the standard answer and it is why group A does not get both the first
    /// and the third seed.
    public static func group(ofSeed seed: Int, groups: Int) -> Int {
        guard groups >= 1 else { return 1 }
        let index = seed - 1
        let row = index / groups
        let within = index % groups
        return row % 2 == 0 ? within + 1 : groups - within
    }

    /// Every pairing in a round robin of `n`, in the order a group would play them.
    static func roundRobin(_ n: Int) -> [(Int, Int)] {
        guard n >= 2 else { return [] }
        var pairs: [(Int, Int)] = []
        for a in 0..<n {
            for b in (a + 1)..<n { pairs.append((a, b)) }
        }
        return pairs
    }

    public static func of(entrants: [Team], fixtures: [Fixture], groups count: Int,
                          qualifiers: Int, pointsForWin: Int, pointsForDraw: Int) -> Groups {
        guard count >= 1, qualifiers >= 1 else {
            return Groups(groups: [], knockout: nil, qualifiersPerGroup: max(qualifiers, 0))
        }
        let drawn = Dictionary(fixtures.compactMap { f -> (String, Fixture)? in
            guard let round = f.round, let slot = f.slot,
                  f.bracket == Bracket.group.rawValue else { return nil }
            return ("\(round)-\(slot)", f)
        }, uniquingKeysWith: { first, _ in first })

        var built: [Group] = []
        for number in 1...count {
            let members = entrants.enumerated()
                .filter { Groups.group(ofSeed: $0.offset + 1, groups: count) == number }
                .map(\.element)
            var matches: [DrawMatch] = []
            for (slot, pair) in Groups.roundRobin(members.count).enumerated() {
                matches.append(DrawMatch(round: number, slot: slot + 1,
                                         home: .entrant(members[pair.0]),
                                         away: .entrant(members[pair.1]),
                                         fixture: drawn["\(number)-\(slot + 1)"],
                                         bracket: .group))
            }
            let played = matches.compactMap(\.fixture)
            built.append(Group(number: number, entrants: members,
                               table: TableRow.table(teams: members, fixtures: played,
                                                     pointsForWin: pointsForWin,
                                                     pointsForDraw: pointsForDraw),
                               matches: matches))
        }

        // The knockout waits for every group to finish. A bracket built from a half-played table
        // would show people through who are not, which is a claim rather than a schedule.
        let ready = built.allSatisfy(\.isComplete) && built.allSatisfy { $0.table.count >= qualifiers }
        let knockout = ready
            ? Draw.of(entrants: Groups.seeded(built, qualifiers: qualifiers),
                      fixtures: fixtures.filter { $0.bracket == Bracket.winners.rawValue })
            : nil
        return Groups(groups: built, knockout: knockout, qualifiersPerGroup: qualifiers)
    }

    /// The qualifiers, in the order the knockout seeds them.
    ///
    /// **Position-major**: every group winner, then every runner-up, and so on. That is the ordering
    /// real draws use, and combined with the bracket's own seeding — the top seed meets the bottom
    /// one — it usually keeps two teams from the same group apart in the first round.
    ///
    /// *Usually*, not always: with an odd number of groups the middle winner is paired with the
    /// runner-up of their own group. So the list is **repaired** afterwards rather than trusted, by
    /// swapping the offending entrant with one from another pairing. `Groups.clashes` reports
    /// anything the repair could not fix instead of letting it through quietly.
    public static func seeded(_ groups: [Group], qualifiers: Int) -> [Team] {
        var order: [Team] = []
        var origin: [String: Int] = [:]
        for position in 0..<qualifiers {
            for group in groups where position < group.table.count {
                order.append(group.table[position].team)
                origin[group.table[position].team.id] = group.number
            }
        }
        return repair(order, origin: origin)
    }

    /// Swaps entrants until no first-round pairing has two from one group, where that is possible.
    ///
    /// Greedy and bounded: for each clashing pairing, look for another pairing whose away side comes
    /// from a third group and swapping would clash with neither. It is not a general constrained
    /// draw and does not claim to be — what it is, is *checked*: `clashes` recomputes the answer
    /// from the repaired list, so a case this cannot fix is reported rather than shipped.
    static func repair(_ order: [Team], origin: [String: Int]) -> [Team] {
        var seeds = order
        let size = Draw.size(forEntrants: seeds.count)
        guard size >= 4 else { return seeds }
        let positions = Draw.seedOrder(size: size)

        func clashing() -> [Int] {
            var out: [Int] = []
            for slot in stride(from: 0, to: size, by: 2) {
                let a = positions[slot] - 1, b = positions[slot + 1] - 1
                guard a < seeds.count, b < seeds.count else { continue }
                if origin[seeds[a].id] != nil, origin[seeds[a].id] == origin[seeds[b].id] {
                    out.append(slot)
                }
            }
            return out
        }

        // At most one pass per pairing: each swap fixes one clash and is rejected if it makes
        // another, so this terminates and never trades one problem for two.
        for slot in clashing() {
            let a = positions[slot] - 1, b = positions[slot + 1] - 1
            guard a < seeds.count, b < seeds.count else { continue }
            for other in stride(from: 0, to: size, by: 2) where other != slot {
                let c = positions[other] - 1, d = positions[other + 1] - 1
                guard c < seeds.count, d < seeds.count else { continue }
                // Swap the two away sides and keep it only if both pairings come out clean.
                let group = { (team: Team) in origin[team.id] }
                if group(seeds[b]) != group(seeds[c]) && group(seeds[d]) != group(seeds[a]) {
                    seeds.swapAt(b, d)
                    break
                }
            }
        }
        return seeds
    }

    /// First-round pairings that still have two entrants from one group, in words. Empty when there
    /// are none, which is the ordinary case.
    public var clashes: [String] {
        guard let knockout, !knockout.rounds.isEmpty else { return [] }
        var group: [String: Int] = [:]
        for g in groups {
            for team in g.entrants { group[team.id] = g.number }
        }
        return knockout.rounds[0].compactMap { match in
            guard let sides = match.playable,
                  let a = group[sides.home.id], let b = group[sides.away.id], a == b else { return nil }
            let name = groups.first { $0.number == a }?.name ?? "\(a)"
            return "\(sides.home.name) and \(sides.away.name) both came out of group \(name) and "
                 + "have been drawn against each other in the first round. THRØ could not separate "
                 + "them with the entrants it had, and is saying so rather than pretending it did."
        }
    }

    /// Every group match that has not been created as a fixture yet.
    public func readyToDraw(group number: Int) -> [DrawMatch] {
        groups.first { $0.number == number }?.matches.filter { $0.fixture == nil } ?? []
    }

    /// How many matches the whole thing takes: every group's round robin, plus the knockout.
    public var matchCount: Int {
        groups.reduce(0) { $0 + $1.matches.count }
            + (groups.isEmpty ? 0 : max(groups.count * qualifiersPerGroup - 1, 0))
    }
}
