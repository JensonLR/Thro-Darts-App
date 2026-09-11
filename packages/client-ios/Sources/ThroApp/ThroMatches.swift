import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// A sent match, onward (PD-043).
//
// A match sent from a phone is one player's word (PD-040). This is where it stops being: the player
// who sent it gives the other player a code; the other player enters it on their own phone, takes
// their seat, and confirms the result or contests it. Everything shown is the server's reading of its
// log — the legs, the winner, where it stands — so the phone shows it and keeps none of it as truth.
// The only thing here that can go stale is the list, and it is read again whenever the Live tab is.

// MARK: - the model

/// The matches this person has on THRØ, and the three things they can do about one: give the other
/// player a code, take their own seat with a code they were given, and answer for a result somebody
/// else sent.
@MainActor
public final class ThroMatchesModel: ObservableObject {
    @Published public private(set) var list: TeamsModel.Loading<[MatchOnRecord]> = .idle
    /// The code on show, and the match it is for: one slot, keyed, so a code made for one match is
    /// never shown on another's page — the team front's lesson.
    @Published public private(set) var code: MatchCode?
    @Published public private(set) var codeFor: UUID?
    /// The last refusal or failure, in the server's own words where it gave some.
    @Published public private(set) var note: String?
    @Published public private(set) var working = false

    public init() {}

    public var records: [MatchOnRecord] { if case .loaded(let l) = list { return l } else { return [] } }
    public func record(_ id: UUID) -> MatchOnRecord? { records.first { $0.matchId == id } }
    public func code(for matchId: UUID) -> MatchCode? { codeFor == matchId ? code : nil }

    /// Reads the list again. A list already on screen stays there while it does, and a failure then
    /// is a note rather than an empty screen.
    public func load(_ api: ThroAPI?, signedIn: Bool) async {
        guard let api, signedIn else { list = .idle; return }
        if case .loaded = list {} else { list = .loading }
        do { list = .loaded(try await api.myMatches()) } catch {
            let why = ThroAPI.refusal(error) ?? LeaguesModel.explain(error, what: "your matches on THRØ")
            if case .loaded = list { note = why } else { list = .failed(why) }
        }
    }

    public func makeCode(for matchId: UUID, _ api: ThroAPI?) async {
        guard let api else { note = "This build names no server."; return }
        working = true
        defer { working = false }
        do {
            code = try await api.matchCode(matchId)
            codeFor = matchId
            note = nil
        } catch { note = ThroAPI.refusal(error) ?? "A code could not be made just now." }
    }

    /// Takes the seat a code was made for. The match comes back as this person now reads it.
    @discardableResult
    public func claim(code raw: String, _ api: ThroAPI?) async -> MatchOnRecord? {
        guard let api else { note = "This build names no server."; return nil }
        working = true
        defer { working = false }
        do {
            let taken = try await api.claimMatch(code: ThroMatchWords.normalised(raw))
            keep(taken)
            note = nil
            return taken
        } catch { note = ThroAPI.refusal(error) ?? "That code could not be used just now."; return nil }
    }

    @discardableResult
    public func answer(_ matchId: UUID, agree: Bool, _ api: ThroAPI?) async -> MatchOnRecord? {
        guard let api else { note = "This build names no server."; return nil }
        working = true
        defer { working = false }
        do {
            let answered = try await api.answerMatch(matchId, agree: agree)
            keep(answered)
            note = nil
            return answered
        } catch { note = ThroAPI.refusal(error) ?? "Your answer did not reach THRØ. Try again."; return nil }
    }

    public func dismissNote() { note = nil }

    /// A match as the server now reads it, in the place of the one held, or first when it is new here.
    func keep(_ record: MatchOnRecord) {
        var all = records
        if let at = all.firstIndex(where: { $0.matchId == record.matchId }) { all[at] = record } else { all.insert(record, at: 0) }
        list = .loaded(all)
    }
}

// MARK: - the words

/// What a match on THRØ is called and where it stands, in words for the screen. Pure, so the
/// sentences are tested rather than looked at.
public enum ThroMatchWords {
    public enum Badge: Equatable, Sendable { case yourWord, needsYourAnswer, theirWord, confirmed, disputed, scoredLive }

    public static func badge(_ r: MatchOnRecord) -> Badge {
        switch r.standing {
        case "confirmed": return .confirmed
        case "disputed": return .disputed
        case "recorded": return .scoredLive
        default: return r.youSent ? .yourWord : (r.canAnswer ? .needsYourAnswer : .theirWord)
        }
    }

    public static func label(_ badge: Badge) -> String {
        switch badge {
        case .yourWord: return "Your word"
        // Short enough to sit whole beside a row's words: "Needs your answer" was cut to
        // "NEEDS YOUR AN…" in the list, which is a status nobody can read.
        case .needsYourAnswer: return "To answer"
        case .theirWord: return "Their word"
        case .confirmed: return "Confirmed"
        case .disputed: return "Disputed"
        case .scoredLive: return "Scored live"
        }
    }

    /// The other player's name where THRØ may show it; else the name typed for them on this phone at
    /// the oche, which is this phone's own to show back; else nobody's.
    public static func name(_ r: MatchOnRecord, typed: String? = nil) -> String? {
        if let shown = r.theirs?.name?.trimmingCharacters(in: .whitespaces), !shown.isEmpty { return shown }
        if let local = typed?.trimmingCharacters(in: .whitespaces), !local.isEmpty { return local }
        return nil
    }

    public static func title(_ r: MatchOnRecord, typed: String? = nil) -> String {
        "You v " + (name(r, typed: typed) ?? "your opponent")
    }

    /// The score as the reader reads it — their own legs first — and how it came out.
    public static func result(_ r: MatchOnRecord) -> String {
        let score = "\(r.yourLegs)–\(r.theirLegs)"
        switch r.ending {
        case "abandoned": return "Abandoned at \(score)"
        case "retired": return r.retired == r.yours?.seat ? "Lost \(score), you retired" : "Won \(score), they retired"
        default:
            switch r.youWon {
            case .some(true): return "Won \(score)"
            case .some(false): return "Lost \(score)"
            case .none: return "\(score), not finished"
            }
        }
    }

    /// How it came out, without the score: the line under the score on the match's own page.
    public static func outcome(_ r: MatchOnRecord) -> String {
        switch r.ending {
        case "abandoned": return "Abandoned"
        case "retired": return r.retired == r.yours?.seat ? "You retired" : "They retired, so it is your win"
        default:
            switch r.youWon {
            case .some(true): return "Your win"
            case .some(false): return "Their win"
            case .none: return "Not finished"
            }
        }
    }

    public static func format(_ f: MatchOnRecord.Format) -> String {
        let legs = f.legsMode == "best_of" ? "best of \(f.legsTarget)" : "first to \(f.legsTarget)"
        let out: String
        switch f.outRule {
        case "double": out = "double out"
        case "master": out = "master out"
        default: out = "straight out"
        }
        return "\(f.startingScore) · \(legs) · \(out)"
    }

    /// What its standing means for this reader, in a sentence or two.
    public static func explanation(_ r: MatchOnRecord, typed: String? = nil) -> String {
        let them = name(r, typed: typed) ?? "the other player"
        let opening = name(r, typed: typed) ?? "The other player"
        switch badge(r) {
        case .yourWord:
            if r.ending == "abandoned" {
                return "Sent from your phone. It was abandoned, so there is no result for anybody to confirm."
            }
            return r.canGiveCode
                ? "Sent from your phone, so it is your word until \(them) confirms it. They are not on this match yet: give them a code and it goes on their record too."
                : "Sent from your phone, so it is your word until \(them) confirms it."
        case .needsYourAnswer:
            return "\(opening) sent this from their phone. Confirm it if that is how it went, or contest it if it is not."
        case .theirWord:
            return "\(opening) sent this from their phone. It was abandoned, so there is no result to answer for."
        case .confirmed:
            return r.youSent ? "\(opening) confirmed it, so it stands as agreed by you both."
                             : "You confirmed it, so it stands as agreed by you both."
        case .disputed:
            return r.youSent ? "\(opening) contested it, so it stands as disputed."
                             : "You contested it, so it stands as disputed. If you change your mind, you can still confirm it."
        case .scoredLive:
            return "Scored on THRØ as it was played, so there is nothing for either of you to confirm."
        }
    }

    /// What the share sheet carries: the code, and the control it is entered under, named as that
    /// control is named. A share that sends somebody to a screen that does not exist is a dead end —
    /// the team code's lesson.
    public static func share(_ code: MatchCode) -> String {
        "Our darts match is on THRØ. Put it on your record too: enter the code \(code.spoken) in THRØ under Live → Enter a code."
    }

    /// Case, spaces and dashes are how a code is said across a table, not part of it.
    public static func normalised(_ raw: String) -> String { raw.uppercased().filter { !$0.isWhitespace && $0 != "-" } }
}

// MARK: - the Live tab's block

/// Which page of a sent match is open over the Live tab.
enum ThroMatchSheet: Identifiable, Equatable {
    case match(UUID)
    case enterCode

    var id: String {
        switch self {
        case .match(let id): return "match-\(id.uuidString)"
        case .enterCode: return "enter-code"
        }
    }
}

/// "On THRØ": the matches this person has on THRØ, each with where it stands, and the way in for
/// somebody who was given a code.
struct ThroMatchesBlock: View {
    @ObservedObject var model: ThroMatchesModel
    /// The name typed on this phone for the other seat, when this phone scored the match.
    let typedOpponent: (MatchOnRecord) -> String?
    let onOpen: (MatchOnRecord) -> Void
    let onEnterCode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader("On THRØ", meta: model.records.isEmpty ? nil : "\(model.records.count)")
            switch model.list {
            case .idle, .loading:
                HStack(spacing: ThroSpacing.spacing2) {
                    ProgressView()
                    Text("Reading your matches").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                }
            case .failed(let why):
                Note(why, icon: .info)
            case .loaded(let records):
                if records.isEmpty {
                    Note("**A match you send shows here**, with where it stands: your word, or agreed by you both once the other player confirms it.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            ThroMatchRow(record: record, typed: typedOpponent(record)) { onOpen(record) }
                            ThroDivider()
                        }
                    }
                }
            }
            HStack(spacing: ThroSpacing.spacing3) {
                Text("Played somebody who sent the match?")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThroSpacing.spacing2)
                ThroButton("Enter a code", variant: .secondary, size: .small) { onEnterCode() }
            }
            .padding(.top, ThroSpacing.spacing1)
        }
    }
}

/// One match on THRØ, in a list: who, the score and how it came out, and where it stands.
struct ThroMatchRow: View {
    let record: MatchOnRecord
    let typed: String?
    let action: () -> Void

    var body: some View {
        let badge = ThroMatchWords.badge(record)
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ThroMatchWords.title(record, typed: typed))
                        .thro(ThroTypography.label.weight(.semibold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                    Text(ThroMatchWords.result(record) + " · " + record.openedAt.formatted(.dateTime.day().month(.abbreviated)))
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                // The status is never the thing that gives way: the row's words truncate first.
                Tag(ThroMatchWords.label(badge), tone: Self.tone(badge))
                    .fixedSize()
                    .layoutPriority(1)
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
        .accessibilityElement(children: .combine)
    }

    static func tone(_ badge: ThroMatchWords.Badge) -> Tag.Tone {
        switch badge {
        case .confirmed: return .success
        case .disputed: return .error
        case .needsYourAnswer: return .warning
        case .scoredLive: return .info
        case .yourWord, .theirWord: return .neutral
        }
    }
}

// MARK: - one match

/// One match on THRØ: the score as the server replays it, where it stands, and the one thing this
/// reader can do about it — give the other player a code, or answer for the result.
struct ThroMatchScreen: View {
    @ObservedObject var model: ThroMatchesModel
    let matchId: UUID
    let api: ThroAPI?
    let typed: String?
    let onClose: () -> Void
    @State private var contesting = false
    /// The board, followed live while the match is still going (PD-044).
    @StateObject private var watch = MatchWatchModel()

    /// Nobody has won it and it has not ended short: there is still something to follow.
    static func stillGoing(_ r: MatchOnRecord) -> Bool { r.winner == nil && r.ending == nil }

    var body: some View {
        let record = model.record(matchId)
        VStack(spacing: 0) {
            BoardHeader(title: record.map { ThroMatchWords.title($0, typed: typed) } ?? "Your match",
                        eyebrow: "On THRØ", onBack: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spaceSectionGap) {
                    if let record {
                        // Still going: the board, live off the stream. Finished: the score.
                        if ThroMatchScreen.stillGoing(record) {
                            LiveBoardSlate(watch: watch, them: ThroMatchWords.name(record, typed: typed) ?? "Them",
                                           format: ThroMatchWords.format(record.format))
                        } else {
                            score(record)
                        }
                        standing(record)
                        if record.canGiveCode { codeSlate(record) }
                        if record.canAnswer { answering(record) }
                    } else {
                        Text("This match is not in your list any more. Close this page and the list is read again.")
                            .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = model.note { Snackbar(note, tone: .error) }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing7)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throEntrance(0)
        .onAppear { model.dismissNote() }
        .task(id: matchId) {
            if let r = model.record(matchId), ThroMatchScreen.stillGoing(r) { await watch.follow(api, r) }
        }
        // A match that finishes while it is watched is read again, so its page says where it stands.
        .onChange(of: LiveBoardWords.finished(watch.board)) { _, finished in
            if finished { Task { await model.load(api, signedIn: true) } }
        }
        .confirmationDialog("Contest this result?", isPresented: $contesting, titleVisibility: .visible) {
            Button("Contest it", role: .destructive) { Task { await model.answer(matchId, agree: false, api) } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It stands as disputed, and the player who sent it sees that you contested it. You can still confirm it later.")
        }
    }

    private func score(_ r: MatchOnRecord) -> some View {
        ThroSlate(seed: 57) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                Eyebrow(ThroMatchWords.format(r.format), color: ThroColor.colorTextOnBoardSecondary)
                Text("\(r.yourLegs)–\(r.theirLegs)")
                    .thro(ThroTypography.display.family(.sport).weight(.bold).tracking(em: 0.04))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .accessibilityLabel("You \(r.yourLegs), \(ThroMatchWords.name(r, typed: typed) ?? "your opponent") \(r.theirLegs)")
                Text(ThroMatchWords.outcome(r) + " · " + r.openedAt.formatted(date: .abbreviated, time: .omitted))
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ThroSpacing.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func standing(_ r: MatchOnRecord) -> some View {
        let badge = ThroMatchWords.badge(r)
        return CardGroup("Where it stands") {
            CardPad {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                    Tag(ThroMatchWords.label(badge), tone: ThroMatchRow.tone(badge))
                    Text(ThroMatchWords.explanation(r, typed: typed))
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The code for the other seat, drawn as the friend code is: on the slate, big enough to read
    /// across a table, with the share beside it.
    private func codeSlate(_ r: MatchOnRecord) -> some View {
        ThroSlate(seed: 33) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                Eyebrow("A code for " + (ThroMatchWords.name(r, typed: typed) ?? "the other player"),
                        color: ThroColor.colorTextOnBoardSecondary)
                if let code = model.code(for: r.matchId) {
                    Text(code.spoken)
                        .thro(ThroTypography.display.family(.sport).weight(.bold).tracking(em: 0.08))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityLabel("The match code, \(code.code.map(String.init).joined(separator: " "))")
                    Text("Say it or show it to them. Good until \(code.expiresAt.formatted(.dateTime.day().month(.abbreviated))), for this match and one player.")
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: ThroMatchWords.share(code)) {
                        Text("SHARE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                            .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                    }
                    .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 41))
                    .fixedSize()
                } else {
                    Text("They enter it on their own phone, and the match goes on their record too. Then they confirm the result, or contest it.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { Task { await model.makeCode(for: r.matchId, api) } } label: {
                        Text("MAKE THE CODE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                            .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                    }
                    .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 41))
                    .fixedSize()
                    .disabled(model.working)
                }
            }
            .padding(ThroSpacing.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Confirm or contest; once answered, the other one, because the latest answer is the one that stands.
    private func answering(_ r: MatchOnRecord) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader(r.yourAnswer == nil ? "Your answer" : "Change your answer")
            HStack(spacing: ThroSpacing.spacing3) {
                // Full width, as the match card's Continue is: two share the row, and the one left
                // after an answer spans it rather than sitting small at its start.
                if r.yourAnswer != "confirmed" {
                    ThroButton("Confirm result", variant: .primary, size: .large, fullWidth: true) {
                        Task { await model.answer(r.matchId, agree: true, api) }
                    }
                    .disabled(model.working)
                }
                if r.yourAnswer != "contested" {
                    ThroButton("Contest", variant: .secondary, size: .large, fullWidth: true) { contesting = true }
                        .disabled(model.working)
                }
            }
        }
    }
}

// MARK: - entering a code

/// Entering a code somebody gave you for their match: the seat becomes yours, and the match opens
/// on the answer they are waiting for.
struct MatchCodeEntryScreen: View {
    @ObservedObject var model: ThroMatchesModel
    let api: ThroAPI?
    let onClaimed: (MatchOnRecord) -> Void
    let onClose: () -> Void
    @State private var code = ""

    var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: "Enter a code", eyebrow: "On THRØ", onBack: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    Text("The player who sent your match can make a code for you on their phone. Enter it here and the match goes on your record too; then you confirm the result, or contest it.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: ThroSpacing.spacing3) {
                        ThroTextField("Code", text: $code, placeholder: "ABCD EFGH")
                            .autocorrectionDisabled()
                            .codeKeyboard()
                        ThroButton("Take my seat", variant: .primary, size: .large) {
                            let entered = code
                            Task {
                                if let taken = await model.claim(code: entered, api) {
                                    code = ""
                                    onClaimed(taken)
                                }
                            }
                        }
                        .disabled(ThroMatchWords.normalised(code).count != 8 || model.working)
                        .padding(.top, 22)
                    }
                    if let note = model.note { Snackbar(note, tone: .error) }
                    Note("A code is for one match and one player, and it works once. Nobody is searched for: a code handed over is how THRØ knows the two of you played.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throEntrance(0)
        .onAppear { model.dismissNote() }
    }
}

private extension View {
    /// A code is written in capitals, so the phone's keyboard starts in them. The Mac the package's
    /// tests run on has no such keyboard, and no such modifier.
    @ViewBuilder func codeKeyboard() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }
}
