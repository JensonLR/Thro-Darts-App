import Foundation
import ThroDesign
import ThroEngine
import ThroJournal
import ThroStatistics

/// One match being scored on this device: the engine's state, the journal that makes it durable, and
/// the keypad's entry. This is the whole of the scoring logic; the screens only draw it.
///
/// The order inside `submit` is the durability rule from ADR-006 and is not to be rearranged:
/// the engine decides (pure, in memory) → the journal commits (fsync) → the state is applied and
/// the screen updates. If the journal throws, nothing is applied and the player is told the visit
/// was not saved — a score shown but not stored is the one thing this must never do.
public final class MatchSession: ObservableObject {
    public let journal: Journal
    public let record: MatchRecord

    @Published public private(set) var state: MatchState
    @Published public private(set) var visits: [ReplayedVisit]
    /// The leg as a scorer would have written it, struck rows included (PD-004).
    ///
    /// Separate from `visits` on purpose: `visits` is the evidence every figure stands on and every
    /// one of them counts, while this is what the board shows — and a retracted visit belongs on the
    /// board, struck, because that is what the journal did to it. Feeding this to a statistic would
    /// count a visit that was taken back.
    @Published public private(set) var ledger: [LedgerEntry]
    @Published public private(set) var entry: String = ""
    @Published public private(set) var prompt: Prompt?
    @Published public private(set) var notice: Notice?
    /// Set after a bust so the screen can show the restored score in the error colour until the
    /// next key is pressed.
    @Published public private(set) var bust: BustDisplay?
    /// A proposed undo of the last visit, awaiting the player's confirmation (PD-004).
    @Published public private(set) var retraction: RetractionProposal?
    /// A bust or a won leg, shown over the scoring screen until someone taps Continue (PD-005).
    @Published public private(set) var announcement: Announcement?

    public enum Announcement: Equatable, Sendable {
        /// `restored` is what the seat's remaining went back to; `reason` is the engine's, when it
        /// gave one beyond "below zero"; `next` is who throws now.
        case bust(seat: Seat, restored: Int, reason: String?, next: Seat?)
        /// The leg just decided, the legs as they now stand, and who throws first in the next.
        case legWon(leg: Int, winner: Seat, legsHome: Int, legsAway: Int, next: Seat?)
    }

    public struct RetractionProposal: Equatable, Sendable {
        public let seat: Seat
        public let visitTotal: Int
        /// What the seat's remaining returns to.
        public let restoresTo: Int
    }

    public struct Notice: Equatable, Sendable {
        public enum Tone: Sendable, Equatable { case neutral, success, error }
        public let text: String
        public let tone: Tone
    }

    public struct BustDisplay: Equatable, Sendable {
        public let seat: Seat
        public let restored: Int
    }

    /// PD-001's two questions, asked when they apply and never otherwise. Darts at a double is asked
    /// on every visit that BEGAN on a checkout number, finished or not; darts used only on the visit
    /// that wins the leg, the only one whose dart count is ambiguous.
    public enum Prompt: Equatable, Sendable {
        case dartsUsed(total: Int)
        case dartsAtDouble(total: Int, dartsUsed: Int?, finished: Bool)

        public var question: String {
            switch self {
            case .dartsUsed: return "Darts used to check out?"
            case .dartsAtDouble: return "Darts thrown at a double?"
            }
        }

        public var context: String {
            switch self {
            case .dartsUsed(let total): return "Finish on \(total)"
            case let .dartsAtDouble(total, _, finished): return finished ? "Finish on \(total)" : "\(total) scored from a finish"
            }
        }

        public var options: [Int] {
            switch self {
            case .dartsUsed: return [1, 2, 3]
            case let .dartsAtDouble(_, dartsUsed, finished):
                if !finished { return [0, 1, 2, 3] }
                return [1, 2, 3].filter { dartsUsed == nil || $0 <= dartsUsed! }
            }
        }

        public var preset: Int {
            switch self {
            case .dartsUsed: return 3
            case let .dartsAtDouble(_, _, finished): return finished ? 1 : 0
            }
        }
    }

    public init(journal: Journal, record: MatchRecord) throws {
        self.journal = journal
        self.record = record
        let replayed = try journal.replayVisits(record.id)
        self.state = replayed.state
        self.visits = replayed.visits
        self.ledger = (try? journal.ledger(record.id)) ?? []
        // Read on open, so reopening a finished match shows what was actually agreed (PD-011)
        // rather than starting again from nothing.
        self.standing = try journal.standing(for: record.id)
        self.ending = try journal.ending(for: record.id)
    }

    public static func start(_ new: NewMatch, in journal: Journal) throws -> MatchSession {
        try MatchSession(journal: journal, record: try journal.createMatch(new))
    }

    public static func open(_ id: MatchId, in journal: Journal) throws -> MatchSession {
        try MatchSession(journal: journal, record: try journal.match(id))
    }

    // MARK: - derived

    public var thrower: Seat? { state.thrower.flatMap(Seat.init(playerId:)) }

    /// Who won. The engine's answer when the match was played out; the **other** seat when somebody
    /// retired; and **nobody** when it was abandoned, which is why this is optional and why nothing
    /// downstream may fill it in (PD-016).
    public var winner: Seat? {
        if let ending { return ending.winner }
        return state.winner.flatMap(Seat.init(playerId:))
    }

    /// Whether the match is over — played out, or ended short (PD-016). Both close the keypad.
    public var isComplete: Bool { state.isComplete || ending != nil }

    /// Whether it was played to its format. A retired match has a winner and is still not this.
    public var wasPlayedOut: Bool { state.isComplete && ending == nil }
    public func name(_ seat: Seat) -> String { record.name(seat) }
    public func remaining(_ seat: Seat) -> Int { state.remaining[seat.playerId] ?? record.startingScore }
    public func legsWon(_ seat: Seat) -> Int { state.legsWonTotal[seat.playerId] ?? 0 }
    public var checkable: Set<Int> { RuleTables.checkouts(record.outRule) }
    public var throwerOnAFinish: Bool { thrower.map { checkable.contains(remaining($0)) } ?? false }

    // MARK: - ending a match short (PD-016)

    /// How this match ended short, if it did. Read from the journal, never assumed.
    @Published public private(set) var ending: Ending?

    /// Two steps, because an ending is final and so is never one tap away: choose which kind, then
    /// confirm that one with its consequence spelt out.
    public enum EndFlow: Equatable, Sendable {
        case choosing
        case confirming(Ending)
    }

    /// Where the player is in that flow, or nil when they are not in it.
    @Published public private(set) var endFlow: EndFlow?

    /// Whether ending short is offered at all. A match already over — played out or ended — is not
    /// ended again, and a match nobody has thrown a dart in is closed by leaving it, not by
    /// retiring: there is no result to protect and no darts to keep.
    public var mayEndShort: Bool { !isComplete && !visits.isEmpty }

    public func offerToEnd() {
        guard mayEndShort else { return }
        endFlow = .choosing
    }

    public func proposeEnding(_ ending: Ending) {
        guard mayEndShort else { return }
        endFlow = .confirming(ending)
    }

    /// Steps back one: from the confirmation to the choice, and from the choice out of the flow.
    /// One `Back` that means "out" would make the destructive button the only way forward.
    public func cancelEnding() {
        switch endFlow {
        case .confirming: endFlow = .choosing
        case .choosing, nil: endFlow = nil
        }
    }

    /// What the confirm sheet says, in the words the screen shows. Written here rather than in the
    /// view because these two sentences are the whole difference between the two endings, and a
    /// screen that got them the wrong way round would record the opposite of what happened.
    public func endingConsequence(_ ending: Ending) -> String {
        switch ending {
        case let .retired(by):
            return "\(name(by)) stops, so \(name(by == .home ? .away : .home)) wins. "
                 + "It is recorded as a retirement, not as a match played out."
        case .abandoned:
            return "Nobody wins, and nobody is given the win. "
                 + "The darts already thrown are kept; the match counts as no result."
        }
    }

    /// Writes the ending. Journal first, screen second, like every other change here — so a match
    /// never shows as ended until the row that ends it has committed.
    public func confirmEnding() {
        guard case let .confirming(proposed) = endFlow else { return }
        do {
            try journal.end(record.id, as: proposed)
            ending = try journal.ending(for: record.id)
            standing = try journal.standing(for: record.id)
            endFlow = nil
            notice = Notice(text: proposed.isResult ? "Recorded as a retirement." : "Recorded as abandoned — no result.",
                            tone: .neutral)
        } catch {
            // The confirmation stays up: nothing was written, so the offer is still live and the
            // player can try again rather than being returned to a match that looks unchanged
            // because it *is* unchanged.
            notice = Notice(text: "Not saved, so not recorded. \(error)", tone: .error)
        }
    }

    // MARK: - attestation (PD-011)

    /// Who stands behind this result, read from the journal on every change.
    @Published public private(set) var standing: Journal.Standing =
        Journal.Standing(confirmed: [], contested: [], stale: false)

    /// The label the Result screen shows, derived rather than stored.
    ///
    /// The derivation is deliberately conservative in both directions. A contest outranks a
    /// confirmation, because a result one competitor does not accept is disputed whatever the other
    /// said. And a confirmation that a later visit or retraction has overtaken counts for nothing:
    /// what was agreed is no longer what is recorded, so the label falls back to self-reported
    /// rather than claiming an agreement nobody gave to this version of the result.
    public var verification: VerificationLabel {
        if standing.anyContest { return .disputed }
        if standing.bothConfirmed { return .participantConfirmed }
        return .selfReported
    }

    /// Whether there is a result here for anybody to stand behind. An abandoned match has none, so
    /// there is nothing to confirm and nothing to dispute (PD-016).
    public var hasResult: Bool { isComplete && winner != nil }

    /// What the Result screen leads with. Here rather than in the view because "no result" and
    /// "in progress" are different states that a `winner ?? "In progress"` would collapse into one,
    /// and an abandoned match reading as still in progress is exactly the wrong answer.
    public var resultHeadline: String {
        if ending == .abandoned { return "No result" }
        if let winner { return "\(name(winner)) wins" }
        return "In progress"
    }

    /// The line under it, when the match did not simply get played out. Nil when it did — a normal
    /// win needs no explanation.
    public var resultDetail: String? {
        switch ending {
        case let .retired(by):
            return "\(name(by)) retired. The legs stand as they were; this is recorded as a retirement, not as a match played out."
        case .abandoned:
            return "This match was abandoned. The darts thrown are kept and count towards both players' figures; the match itself counts for nobody."
        case nil:
            return nil
        }
    }

    /// Seats still to answer. Empty when both have, which is what ends the confirm flow.
    public var awaitingAttestation: [Seat] {
        guard hasResult else { return [] }
        if standing.stale { return Seat.allCases }
        return Seat.allCases.filter { !standing.confirmed.contains($0) && !standing.contested.contains($0) }
    }

    /// Records one player's answer. Appends; nothing is replaced and nothing is removed.
    public func attest(_ seat: Seat, agrees: Bool) {
        do {
            try journal.attest(record.id, seat: seat, agrees: agrees)
            standing = try journal.standing(for: record.id)
            notice = nil
        } catch {
            notice = Notice(text: "Not saved, so not recorded. \(error)", tone: .error)
        }
    }

    /// The route THRØ shows for the thrower's remaining (PD-013), or empty when there is no finish.
    ///
    /// **A position, not a fact.** Most finishes have several legal routes and players disagree
    /// about which is best; the founder decided the app shows one rather than staying silent. Every
    /// route is derived by a stated rule in `packages/domain-spec` and checked arithmetically in
    /// both engines, so what is shown is always a legal finish of exactly this number under exactly
    /// this match's out-rule — which is the part that would be a defect to get wrong.
    ///
    /// The export's `CheckoutCard` already draws a route; it had simply never been given one.
    public var throwerRoute: [String] {
        guard let seat = thrower else { return [] }
        return RuleTables.route(remaining(seat), record.outRule) ?? []
    }

    /// Whether the thrower still has to open (PD-008). Nothing they score counts until they do, and
    /// the screen has to say so — a player watching their 60 not go on the board and not being told
    /// why is the worst thing a scoring app can do.
    public var throwerMustOpen: Bool {
        guard let seat = thrower else { return false }
        return record.inRule.requiresOpening && !(state.opened[seat.playerId] ?? true)
    }
    public var inRuleLabel: String? {
        switch record.inRule {
        case .straight: return nil
        case .double: return "Double in"
        case .master: return "Master in"
        }
    }

    public var formatLabel: String {
        record.legsMode == .bestOf ? "\(record.startingScore) · Bo\(record.legsTarget)"
                                   : "\(record.startingScore) · First to \(record.legsTarget)"
    }
    public var lengthLabel: String {
        record.legsMode == .bestOf ? "Best of \(record.legsTarget)" : "First to \(record.legsTarget)"
    }
    public var outRuleLabel: String {
        switch record.outRule {
        case .double: return "Double out"
        case .master: return "Master out"
        case .straight: return "Straight out"
        }
    }

    // MARK: - keypad

    public func digit(_ d: String) {
        guard prompt == nil, retraction == nil, announcement == nil, !isComplete else { return }
        bust = nil
        notice = nil
        entry = String((entry + d).prefix(3))
    }

    public func clearEntry() {
        bust = nil
        notice = nil
        entry = ""
    }

    public func quick(_ total: Int) {
        guard prompt == nil, retraction == nil, announcement == nil else { return }
        bust = nil
        notice = nil
        commit(total)
    }

    public func miss() {
        guard prompt == nil, retraction == nil, announcement == nil else { return }
        bust = nil
        notice = nil
        commit(0)
    }

    public func enter() {
        guard prompt == nil, retraction == nil, announcement == nil, let total = Int(entry) else { return }
        bust = nil
        notice = nil
        commit(total)
    }

    /// Dismisses the bust or leg announcement; scoring resumes.
    public func acknowledge() { announcement = nil }

    /// Answers the current prompt. `nil` is "not sure": recorded as unknown, never as zero.
    public func answer(_ value: Int?) {
        guard let current = prompt else { return }
        switch current {
        case .dartsUsed(let total):
            prompt = .dartsAtDouble(total: total, dartsUsed: value, finished: true)
        case let .dartsAtDouble(total, dartsUsed, _):
            prompt = nil
            submit(total, dartsUsed: dartsUsed, dartsAtDouble: value)
        }
    }

    /// Cancels the prompt. Nothing is submitted; the entry is kept so it can be corrected.
    public func cancelPrompt() { prompt = nil }

    // MARK: - undo (PD-004)

    /// The keypad's undo key. A typed entry is cleared first; with nothing typed it proposes striking
    /// the last visit, which the player must confirm.
    public func undoKey() {
        guard prompt == nil, retraction == nil, announcement == nil else { return }
        if !entry.isEmpty { clearEntry(); return }
        proposeRetraction()
    }

    public func proposeRetraction() {
        guard prompt == nil, retraction == nil, announcement == nil else { return }
        guard let last = visits.last else {
            notice = Notice(text: Copy.nothingToUndo, tone: .neutral)
            return
        }
        bust = nil
        retraction = RetractionProposal(seat: last.seat, visitTotal: last.visitTotal, restoresTo: last.remainingBefore)
    }

    public func cancelRetraction() { retraction = nil }

    /// Strikes the last visit. The journal commits the retraction first and the state is rebuilt by
    /// replay — the same order as a visit, for the same reason. A local match needs no one's
    /// approval; an online match will need the opponent's, and that is not built.
    public func confirmRetraction() {
        guard let proposal = retraction else { return }
        retraction = nil
        do {
            try journal.retractLastVisit(in: record.id)
            let replayed = try journal.replayVisits(record.id)
            state = replayed.state
            visits = replayed.visits
            // The struck row stays on the board. Before this the ledger was built from `visits`,
            // which excludes it, so a retraction was a disappearance — the one thing PD-004 says it
            // is not.
            ledger = (try? journal.ledger(record.id)) ?? ledger
            // Undoing a visit is exactly the case that makes an agreement stale: what somebody
            // confirmed is no longer what is recorded (PD-011).
            standing = (try? journal.standing(for: record.id)) ?? standing
            entry = ""
            bust = nil
            notice = Notice(text: Copy.undone(name(proposal.seat), proposal.visitTotal, next: thrower.map(name) ?? ""),
                            tone: .neutral)
        } catch {
            notice = Notice(text: Copy.notSaved(error), tone: .error)
        }
    }

    // MARK: - the visit

    func commit(_ total: Int) {
        guard let seat = thrower else { return }
        let rem = remaining(seat)
        let wasOnAFinish = checkable.contains(rem)
        let finished = rem - total == 0 && wasOnAFinish
        if finished {
            prompt = .dartsUsed(total: total)
        } else if wasOnAFinish {
            prompt = .dartsAtDouble(total: total, dartsUsed: nil, finished: false)
        } else {
            submit(total, dartsUsed: nil, dartsAtDouble: nil)
        }
    }

    func submit(_ total: Int, dartsUsed: Int?, dartsAtDouble: Int?) {
        guard let seat = thrower else { return }
        let before = remaining(seat)
        let leg = state.currentLeg
        let command = Command.visit(seat.playerId, total, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble)

        switch Engine.apply(state, command) {
        case .rejected(let reason):
            // The entry stays on screen so the player can see what was refused and fix it.
            notice = Notice(text: Copy.rejected(reason, total: total), tone: .error)

        case let .accepted(next, effect, bustReason):
            let written: JournalEntry
            do {
                written = try journal.append(command, to: record.id)   // flush …
            } catch {
                notice = Notice(text: Copy.notSaved(error), tone: .error)
                return                                                  // … or nothing happened
            }
            let ordinal = visits.filter { $0.seat == seat && $0.legOrdinal == leg }.count + 1
            let won = effect == .leg_won || effect == .set_won || effect == .match_won
            visits.append(ReplayedVisit(
                seat: seat, legOrdinal: leg, visitOrdinal: ordinal,
                visitTotal: total, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble,
                remainingBefore: before,
                remainingAfter: won ? 0 : (next.remaining[seat.playerId] ?? before),
                bust: effect == .bust, wonLeg: won
            ))
            // And on the board, in the same breath. Appended rather than re-read for the same
            // reason `visits` is: a full replay on every visit is work a player waits for, sixty
            // times a leg. `deviceSeq` comes from the row that was actually written, so the board's
            // identity for this line is the journal's own.
            ledger.append(LedgerEntry(
                seat: seat, legOrdinal: leg, visitOrdinal: ordinal, visitTotal: total,
                remainingAfter: won ? 0 : (next.remaining[seat.playerId] ?? before),
                struck: false, deviceSeq: written.deviceSeq))
            // A visit written after an agreement makes that agreement stale (PD-011). It is read
            // back rather than reasoned about, so the screen and the journal cannot disagree.
            standing = (try? journal.standing(for: record.id)) ?? standing
            state = next                                      // … then apply
            entry = ""

            notice = nil
            switch effect {
            case .bust:
                // The restored score stays red on the hero until the next key; the card over it is
                // for the opponent to see (PD-005).
                bust = BustDisplay(seat: seat, restored: before)
                announcement = .bust(seat: seat, restored: before, reason: Copy.bustReason(bustReason, total: total), next: thrower)
            case .leg_won, .set_won:
                announcement = .legWon(leg: leg, winner: seat, legsHome: legsWon(.home), legsAway: legsWon(.away), next: thrower)
            case .scored, .match_won:
                break
            }
        }
    }

    // MARK: - statistics

    /// The six figures the result screen shows, for one seat, each honest about its basis.
    public func statistics(for seat: Seat) -> [StatLine] {
        let records = visits.filter { $0.seat == seat }.map {
            VisitRecord(legOrdinal: $0.legOrdinal, visitOrdinal: $0.visitOrdinal, visitTotal: $0.visitTotal,
                        dartsUsed: $0.dartsUsed, bust: $0.bust, remainingBefore: $0.remainingBefore,
                        remainingAfter: $0.remainingAfter, wonLeg: $0.wonLeg, dartsAtDouble: $0.dartsAtDouble)
        }
        return [
            StatPresentation.line("3-dart average", Statistics.threeDartAverage(records), kind: .average),
            StatPresentation.line("First 9", Statistics.firstNineAverage(records), kind: .average),
            StatPresentation.line("Checkout %", Statistics.checkoutPercentage(records, checkable: checkable), kind: .percent),
            StatPresentation.line("180s", Statistics.maximums(records), kind: .count),
            StatPresentation.line("Highest checkout", Statistics.highestCheckout(records), kind: .count),
            StatPresentation.line("140+", Statistics.scoresAtLeast(records, threshold: 140), kind: .count),
        ]
    }
}

/// What this device can honestly say about one person's darts, across every match they played on it.
///
/// The same honesty layer as a single match's figures — the audited `Statistics` functions, not a
/// second arithmetic written for profiles — over the person's pooled visits, with legs renumbered by
/// the journal so per-leg figures do not merge one match's leg 1 with another's.
///
/// **Checkout percentage is refused when the person has played under more than one out-rule.**
/// Whether a visit was thrown from a finishable position depends on the rule, so pooling visits from
/// a double-out match and a straight-out one gives a number that is not a checkout percentage of
/// anything. Refusing it is a fact about the sample, and it says so rather than showing a figure.
public enum PersonSummary {
    public static func figures(for personId: String, in journal: Journal) throws -> [StatLine] {
        let history = try journal.history(of: personId)
        let records = history.visits.map {
            VisitRecord(legOrdinal: $0.legOrdinal, visitOrdinal: $0.visitOrdinal, visitTotal: $0.visitTotal,
                        dartsUsed: $0.dartsUsed, bust: $0.bust, remainingBefore: $0.remainingBefore,
                        remainingAfter: $0.remainingAfter, wonLeg: $0.wonLeg, dartsAtDouble: $0.dartsAtDouble)
        }
        let checkout: Stat
        if let only = history.outRules.first, history.outRules.count == 1,
           let rule = OutRule(rawValue: only) {
            checkout = Statistics.checkoutPercentage(records, checkable: RuleTables.checkouts(rule))
        } else if history.outRules.isEmpty {
            checkout = Stat.unavailable("No matches on this device yet.")
        } else {
            checkout = Stat.unavailable(
                "These matches were played under \(history.outRules.count) different out-rules, and "
                + "whether a visit began on a finish depends on the rule. Pooling them would not be a "
                + "checkout percentage of anything.")
        }
        // PD-018. Labelled "Recent form", never "Rating": OD-001 leaves the rating model open, and
        // the difference between "what you have been scoring" and "how good you are" is the whole
        // reason this is allowed to ship while that stays open. The window is in the label, because
        // a number without its sample is a claim rather than a description.
        let form = Statistics.recentForm(records)
        var formLine = StatPresentation.line("Recent form", form.average, kind: .average)
        if form.isAvailable {
            formLine = StatLine(label: formLine.label, value: formLine.value,
                                note: [formLine.note,
                                       "Your 3-dart average over your last \(form.legs) completed leg"
                                       + (form.legs == 1 ? "" : "s") + ". Not a rating."]
                                    .compactMap { $0 }.joined(separator: " "))
        }

        var lines: [StatLine] = [
            StatLine(label: "Matches", value: matchesValue(history),
                     note: matchesNote(history)),
            StatLine(label: "Legs won", value: "\(history.legsWon)", note: nil),
            formLine,
            StatPresentation.line("3-dart average", Statistics.threeDartAverage(records), kind: .average),
            StatPresentation.line("Checkout %", checkout, kind: .percent),
            StatPresentation.line("180s", Statistics.maximums(records), kind: .count),
            StatPresentation.line("Highest checkout", Statistics.highestCheckout(records), kind: .count),
        ]
        if history.matches == 0 {
            // A count of zero is a fact; every other figure is unavailable rather than zero, and now
            // says so in its drawn form as well as its words (PD-015).
            lines = lines.map { line in
                let isCount = line.label == "Matches" || line.label == "Legs won"
                return StatLine(label: line.label, value: isCount ? "0" : "—",
                                note: line.note ?? "No matches on this device yet.",
                                confidence: isCount ? .exact : .unavailable)
            }
        }
        return lines
    }

    /// Matches played out, with the ones that ended short named rather than folded in (PD-016).
    /// "12" meaning "nine played out and three walked away from" is a different claim to the one it
    /// looks like, so the count says which.
    private static func matchesValue(_ h: Journal.PersonHistory) -> String { "\(h.matches)" }

    private static func matchesNote(_ h: Journal.PersonHistory) -> String? {
        var parts: [String] = []
        if h.retired > 0 { parts.append("\(h.retired) ended in a retirement") }
        if h.abandoned > 0 { parts.append("\(h.abandoned) abandoned with no result") }
        if h.unreadable > 0 {
            parts.append("\(h.unreadable) more could not be replayed and are not counted here")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ") + "."
    }
}

/// What this phone has done lately: the figures Home opens on.
///
/// **Why Home has figures at all.** The founder, on a build: *"home page feels very bare & basic."*
/// It was — a title, a list of rows, and a button. A darts app's first screen should tell a player
/// something they want to know before they have tapped anything, and the only thing this device can
/// honestly tell them is what it has actually watched them throw.
///
/// **Every figure here comes from the audited `Statistics` layer**, over the same `VisitRecord`
/// shape a match's result screen uses. Nothing is computed twice and nothing is computed loosely:
/// an average with too small a sample comes back `unavailable` and the strip draws a dash, which is
/// the whole point of that layer and the reason a "bare" screen was never going to be fixed by
/// inventing numbers to fill it.
///
/// **The window is seven days and it is in the label.** A figure without its sample is a claim
/// rather than a description (PD-018), so the strip says *Last 7 days* on the screen, not only in
/// this comment.
public enum DeviceSummary {
    public struct Week: Equatable, Sendable {
        /// Matches started in the window, readable or not.
        public let matches: Int
        /// Legs completed in them.
        public let legs: Int
        /// Matches in the window whose rows would not replay. Their darts are in no figure here,
        /// and saying so is the difference between a small sample and a wrong one.
        public let unreadable: Int
        /// The figures themselves, already worded by `StatPresentation`.
        public let figures: [StatLine]
        /// True when the device has matches but none of them fall in the window — a different fact
        /// from an empty phone, and Home says a different thing for each.
        public let quietWeek: Bool

        public init(matches: Int, legs: Int, unreadable: Int, figures: [StatLine], quietWeek: Bool) {
            self.matches = matches
            self.legs = legs
            self.unreadable = unreadable
            self.figures = figures
            self.quietWeek = quietWeek
        }
    }

    /// - Parameter days: the window, in days back from `now`. Seven unless a test says otherwise.
    public static func week(in journal: Journal, now: Date = Date(), days: Int = 7) throws -> Week {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        // Archived matches count. Putting a match on a shelf is a decision about a list, not a
        // claim that the darts were not thrown (PD-026).
        let all = try journal.matches()
        let recent = all.filter { $0.startedAt >= cutoff }
        var records: [VisitRecord] = []
        var legs = 0, unreadable = 0, legOffset = 0
        for record in recent.reversed() {
            do {
                let replayed = try journal.replayVisits(record.id)
                // The renumbering `Journal.history` does, and one more separation on top of it.
                //
                // `history` pools one person, so renumbering per match is enough there. This pools
                // a whole device, and a leg holds **two** players' visits. Numbering per match would
                // have put both of them under one ordinal, and `bestLegInVisits` counts the visits
                // sharing an ordinal — so a 15-visit leg would have been reported as a 30-visit one,
                // for every player, on the first screen of the app. Each seat of each match gets its
                // own block instead, so no ordinal ever holds two people's darts.
                for seat in Seat.allCases {
                    let mine = replayed.visits.filter { $0.seat == seat }
                    guard !mine.isEmpty else { continue }
                    records.append(contentsOf: mine.map {
                        VisitRecord(legOrdinal: $0.legOrdinal + legOffset, visitOrdinal: $0.visitOrdinal,
                                    visitTotal: $0.visitTotal, dartsUsed: $0.dartsUsed, bust: $0.bust,
                                    remainingBefore: $0.remainingBefore, remainingAfter: $0.remainingAfter,
                                    wonLeg: $0.wonLeg, dartsAtDouble: $0.dartsAtDouble)
                    })
                    legOffset += mine.map(\.legOrdinal).max() ?? 0
                }
                legs += replayed.state.legsWonTotal.values.reduce(0, +)
            } catch {
                unreadable += 1
            }
        }
        // Both players' darts are in here, because this is what the *phone* has seen — two people at
        // one device are both throwing on it. It is labelled "on this phone" for exactly that
        // reason and is never presented as one person's average; a person's own figures live on
        // their page, where `PersonSummary` pools only the visits they threw.
        let figures = [
            StatPresentation.line("3-dart average", Statistics.threeDartAverage(records), kind: .average),
            StatPresentation.line("Best leg", Statistics.bestLegInVisits(records), kind: .count),
            StatPresentation.line("180s", Statistics.maximums(records), kind: .count),
        ]
        return Week(matches: recent.count, legs: legs, unreadable: unreadable,
                    figures: figures, quietWeek: recent.isEmpty && !all.isEmpty)
    }
}

/// A statistic as text. EXACT is a number; BOUNDED is a range and says so; UNAVAILABLE is a dash
/// and says why. A bounded figure is never collapsed to a point value.
///
/// `confidence` is carried through to the view (PD-015). It used to stop here: `line` read the
/// basis, chose the wording, and threw the basis away — so the screen received three kinds of
/// figure that it drew identically, and the one thing the honesty layer exists to communicate was
/// the one thing it could not.
public struct StatLine: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    public let note: String?
    public let confidence: StatItem.Confidence
    public var id: String { label }

    public init(label: String, value: String, note: String?,
                confidence: StatItem.Confidence = .exact) {
        self.label = label
        self.value = value
        self.note = note
        self.confidence = confidence
    }

    /// The drawn form, with the reason required where the design requires it.
    public var item: StatItem {
        switch confidence {
        case .exact: return .exact(label, value, note: note)
        case .range: return .range(label, value, why: note ?? "The exact figure is not known.")
        case .unavailable: return .unavailable(label, why: note ?? "Not available.")
        }
    }
}

public enum StatPresentation {
    public enum Kind: Sendable { case average, percent, count }

    public static func line(_ label: String, _ stat: Stat, kind: Kind) -> StatLine {
        switch stat.basis {
        case .exact:
            // Exact can still carry a disclosure — a first nine that excludes legs ended before nine darts.
            return StatLine(label: label, value: format(stat.value ?? 0, kind), note: stat.note,
                            confidence: .exact)
        case .bounded:
            let lower = format(stat.lower ?? 0, kind), upper = format(stat.upper ?? 0, kind)
            return StatLine(label: label, value: "\(lower)–\(upper)",
                            note: stat.note ?? "Range — the exact figure is not known",
                            confidence: .range)
        case .unavailable:
            return StatLine(label: label, value: "—", note: stat.note ?? "Not available",
                            confidence: .unavailable)
        }
    }

    static func format(_ v: Double, _ kind: Kind) -> String {
        switch kind {
        case .average: return String(format: "%.1f", v)
        case .percent: return String(format: "%.0f%%", v)
        case .count: return String(format: "%.0f", v)
        }
    }
}

/// The words on screen. The rejection and bust texts are the harness's (services/api scorer.html),
/// with the design's Snackbar form for a bust — "Bust. Score restored to 186. Wilson to throw." —
/// carrying the reason when the engine gives one.
public enum Copy {
    public static func rejected(_ reason: RejectionReason, total: Int) -> String {
        switch reason {
        case .IMPOSSIBLE_VISIT_TOTAL: return "\(total) cannot be scored with three darts."
        case .VISIT_TOTAL_OUT_OF_RANGE: return "A visit cannot exceed 180."
        case .NOT_YOUR_TURN: return "It is not that player's turn."
        case .MATCH_COMPLETE: return "The match is already complete."
        case .DARTS_USED_INVALID: return "Only a leg-winning visit can use fewer than three darts."
        case .DARTS_AT_DOUBLE_INVALID: return "That number of darts at a double is not possible from this score."
        // Under double-in the score recorded is what counted, from the opening double onward — so a
        // total no sequence starting with a double can make did not happen. 180 is three trebles.
        case .IMPOSSIBLE_OPENING_TOTAL:
            return "\(total) cannot be scored starting on a double. Enter only what counted, from the double."
        }
    }

    /// The engine's reason for a bust when it is more than "below zero", in the harness's words.
    public static func bustReason(_ reason: BustReason?, total: Int) -> String? {
        switch reason {
        case .REMAINDER_ONE: return "That leaves 1."
        case .NOT_CHECKOUT_POSSIBLE: return "\(total) cannot be finished on a double."
        case .BELOW_ZERO, .none: return nil
        }
    }

    public static func notSaved(_ error: Error) -> String {
        "Not saved, so not scored. \(error)"
    }

    public static let nothingToUndo = "Nothing to undo."

    public static func undone(_ player: String, _ total: Int, next: String) -> String {
        next.isEmpty ? "Undone: \(player)'s \(total)." : "Undone: \(player)'s \(total). \(next) to throw."
    }
}
