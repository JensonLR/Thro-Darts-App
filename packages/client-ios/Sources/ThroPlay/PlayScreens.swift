import SwiftUI
import ThroTokens
import ThroDesign
import ThroEngine
import ThroJournal
#if canImport(UIKit)
import UIKit
#endif

// The Play slice for a match scored on this device: setup → ready → scoring → result.
//
// Theme: every screen follows the player's choice — System / Light / Dark, set in Settings (PD-003,
// amended by the founder to include setup and scoring). The export draws setup and scoring dark only
// and the rest light only; the other renderings are the token layer's, unreviewed by design. Each
// screen sets the window's preferred scheme and, when a scheme is chosen, its own environment, and
// paints its own background, because a colour scheme set on a subtree does not paint the window
// behind it.
//
// What the export does not draw, and is composed here from its own components rather than invented:
// a setup for a two-player local match (the export's only setup is Shadow's, which this follows);
// the PD-001 questions, rendered in the keypad's place; the PD-004 undo confirmation, likewise; a way
// to leave the scoring screen (a back chevron at the MatchHeader's leading edge — a TopBar there cost
// height the screen does not have). Each is listed in docs/runbooks/CLIENT_IOS.md.

public struct PlayFlow: View {
    enum Step {
        case setup(home: String, away: String)
        case ready(MatchSession)
        case scoring(MatchSession)
        case result(MatchSession)
    }

    private let journal: Journal
    private let onExit: () -> Void
    @State private var step: Step
    @State private var problem: String?

    /// Starts a new match, or resumes `resume` where it left off.
    public init(journal: Journal, resume: MatchId? = nil, onExit: @escaping () -> Void) {
        self.journal = journal
        self.onExit = onExit
        var initial = Step.setup(home: "", away: "")
        var problem: String?
        if let id = resume {
            do {
                let session = try MatchSession.open(id, in: journal)
                initial = session.isComplete ? .result(session) : .ready(session)
            } catch {
                problem = "\(error)"
            }
        }
        _step = State(initialValue: initial)
        _problem = State(initialValue: problem)
    }

    public var body: some View {
        switch step {
        case let .setup(home, away):
            MatchSetupScreen(initialHome: home, initialAway: away, problem: problem, onBack: onExit) { new in
                do {
                    step = .ready(try MatchSession.start(new, in: journal))
                    problem = nil
                } catch {
                    problem = "\(error)"
                }
            }
        case .ready(let session):
            MatchReadyScreen(session: session, onBack: onExit) { step = .scoring(session) }
        case .scoring(let session):
            ScoringScreen(session: session, onLeave: onExit) { step = .result(session) }
        case .result(let session):
            MatchResultScreen(session: session, onDone: onExit,
                              onPlayAgain: { step = .setup(home: session.name(.home), away: session.name(.away)) },
                              onReopen: { step = .scoring(session) })
        }
    }
}

// MARK: - Setup

/// After `shadow-setup`: eyebrow + title, the two players, then segmented choices, an information
/// row, and one primary action.
public struct MatchSetupScreen: View {
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @State private var home: String
    @State private var away: String
    @State private var game: Int = 501
    @State private var length: Int = 5
    @State private var first: Seat = .home
    @FocusState private var focused: NameField?
    private let problem: String?
    private let onBack: () -> Void
    private let onStart: (NewMatch) -> Void

    private enum NameField: Hashable { case home, away }

    public init(initialHome: String = "", initialAway: String = "", problem: String? = nil,
                onBack: @escaping () -> Void, onStart: @escaping (NewMatch) -> Void) {
        _home = State(initialValue: initialHome)
        _away = State(initialValue: initialAway)
        self.problem = problem
        self.onBack = onBack
        self.onStart = onStart
    }

    private var homeName: String { home.trimmingCharacters(in: .whitespaces).isEmpty ? "Home" : home.trimmingCharacters(in: .whitespaces) }
    private var awayName: String { away.trimmingCharacters(in: .whitespaces).isEmpty ? "Away" : away.trimmingCharacters(in: .whitespaces) }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Match setup", eyebrow: "Local match", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    if let problem {
                        Snackbar(problem, tone: .error)
                    }
                    // Platform keyboard behaviour, not design: names capitalise as names, Next moves
                    // to the away player, Done puts the keyboard away, and so does a drag.
                    ThroTextField("Home player", text: $home, placeholder: "Name")
                        .modifier(NameEntry())
                        .focused($focused, equals: .home)
                        .submitLabel(.next)
                        .onSubmit { focused = .away }
                    ThroTextField("Away player", text: $away, placeholder: "Name")
                        .modifier(NameEntry())
                        .focused($focused, equals: .away)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                    ThroDivider()
                    choice("Game", SegmentedControl([(301, "301"), (501, "501"), (701, "701")], selection: $game))
                    choice("Length", SegmentedControl([(3, "Bo3"), (5, "Bo5"), (7, "Bo7"), (9, "Bo9")], selection: $length))
                    choice("Throws first", SegmentedControl([(Seat.home, homeName), (Seat.away, awayName)], selection: $first))
                    ThroDivider()
                    HStack(alignment: .top, spacing: 10) {
                        Icon(.info, size: 16).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, 2)
                        Text("Matches scored on this device are self-reported and are not rated. They stay on this phone; sending them to THRØ is not built yet.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    ThroButton("Continue", variant: .primary, size: .large, fullWidth: true) {
                        onStart(NewMatch(homeName: homeName, awayName: awayName, startingScore: game, outRule: .double,
                                         legsMode: .bestOf, legsTarget: length, throwFirst: first))
                    }
                }
                .padding(.vertical, ThroSpacing.spacing6)
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
    }

    private func choice<Control: View>(_ label: String, _ control: Control) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Eyebrow(label)
            control
        }
    }
}

/// A person's name is typed as one: each word capitalised. iOS only; the Mac has no such keyboard.
private struct NameEntry: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(.words)
        #else
        content
        #endif
    }
}

// MARK: - Ready

/// After `ready` (Match ready), less the competition, board and ratings a local match does not have.
/// Also the resume point for a match in progress.
public struct MatchReadyScreen: View {
    @ObservedObject private var session: MatchSession
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    private let onBack: () -> Void
    private let onStart: () -> Void

    public init(session: MatchSession, onBack: @escaping () -> Void, onStart: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        self.onStart = onStart
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Match ready", eyebrow: "Local match", onBack: onBack)
            ScrollView {
                VStack(spacing: ThroSpacing.spacing6) {
                    PlayerComparison(
                        home: PlayerRef(name: session.name(.home)),
                        away: PlayerRef(name: session.name(.away)),
                        rows: session.visits.isEmpty ? [] : [
                            .init("Legs", home: "\(session.legsWon(.home))", away: "\(session.legsWon(.away))"),
                        ]
                    )
                    HStack(spacing: ThroSpacing.spacing2) {
                        Tag("\(session.record.startingScore)")
                        Tag(session.lengthLabel)
                        Tag(session.outRuleLabel)
                    }
                    ThroButton(session.visits.isEmpty ? "Start scoring" : "Continue scoring",
                               variant: .primary, size: .large, fullWidth: true, action: onStart)
                    Text("\(session.name(session.thrower ?? .home)) throws first. Scored on this device; self-reported and not rated.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
    }
}

// MARK: - Scoring

/// After `scoring`, `scoring-checkout` and `scoring-bust`: MatchHeader, leg state with the other
/// player's remaining, the remaining score, the checkout card when the thrower is on a finish, the
/// turn indicator, and the keypad — or, when PD-001 has a question, the question in its place.
public struct ScoringScreen: View {
    @ObservedObject private var session: MatchSession
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(ScoringPreferences.keepScreenAwakeKey) private var keepScreenAwake: Bool = true
    private let onLeave: () -> Void
    private let onComplete: () -> Void

    public init(session: MatchSession, onLeave: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.session = session
        self.onLeave = onLeave
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatchHeader(competition: "\(session.name(.home)) v \(session.name(.away))", format: session.formatLabel,
                            onBack: onLeave)
                // Everything above the keypad shares the height the keypad leaves. Nothing scrolls
                // and nothing is cut off: when a phone is short, the hero numeral yields first.
                upper
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if let prompt = session.prompt {
                    PromptCard(prompt: prompt, onAnswer: session.answer, onCancel: session.cancelPrompt)
                } else if let proposal = session.retraction {
                    RetractionCard(proposal: proposal, playerName: session.name(proposal.seat),
                                   onConfirm: session.confirmRetraction, onCancel: session.cancelRetraction)
                } else {
                    ScoreKeypad(value: session.entry, disabled: session.isComplete || session.announcement != nil,
                                onDigit: session.digit, onQuick: session.quick,
                                onMiss: session.miss, onClear: session.undoKey, onEnter: session.enter)
                }
            }
            if let announcement = session.announcement {
                AnnouncementOverlay(announcement: announcement, session: session, onContinue: session.acknowledge)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
        .onReceive(session.$state) { state in
            if state.isComplete { onComplete() }
        }
        .onAppear { setIdleTimer(disabled: keepScreenAwake) }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    private var upper: some View {
        VStack(spacing: 0) {
            legRow.padding(.top, ThroSpacing.spacing5).padding(.bottom, ThroSpacing.spacing2)
            remaining
                .padding(.top, ThroSpacing.spacing2)
                .padding(.bottom, ThroSpacing.spacing1)
                .layoutPriority(-1)
            if session.bust == nil, session.throwerOnAFinish, let seat = session.thrower {
                // The hero already shows the number in brand green; the card names the fact, as the
                // export's checkout screen does with its value hidden.
                CheckoutCard(required: session.remaining(seat), compact: true, hideValue: true)
                    .padding(.top, ThroSpacing.spacing2)
            }
            if let seat = session.thrower {
                TurnIndicator(player: session.name(seat), dartsThrown: 0, active: true)
                    .padding(.top, ThroSpacing.spacing4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        // A refusal floats over the top of this region and clears on the next key; it takes no height.
        .overlay(alignment: .top) {
            if let notice = session.notice {
                Snackbar(notice.text, tone: tone(notice.tone))
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spacing2)
            }
        }
    }

    private var legRow: some View {
        HStack {
            LegState(home: session.legsWon(.home), away: session.legsWon(.away),
                     bestOf: session.record.legsMode == .bestOf ? session.record.legsTarget : nil)
            Spacer()
            if let seat = session.thrower {
                Text("\(session.name(seat.opponent)) \(session.remaining(seat.opponent))")
                    .thro(ThroTypography.metadata.family(.sport).weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder private var remaining: some View {
        if let bust = session.bust {
            RemainingScore(value: bust.restored, label: "\(session.name(bust.seat)) requires", state: .bust)
        } else if let seat = session.thrower {
            RemainingScore(value: session.remaining(seat), label: "\(session.name(seat)) requires",
                           state: session.throwerOnAFinish ? .checkout : .normal)
        }
    }

    private func tone(_ t: MatchSession.Notice.Tone) -> Snackbar.Tone {
        switch t {
        case .neutral: return .neutral
        case .success: return .success
        case .error: return .error
        }
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// PD-005: a bust or a won leg is announced over the scoring screen so both players see it, and
/// scoring resumes only when someone taps Continue (or the scrim). After the export's Dialog —
/// raised surface, radius-card, hairline, elevation-3, 340 wide — with the number in the sport hero
/// face, because the number is what the opponent needs to read from across the oche.
struct AnnouncementOverlay: View {
    let announcement: MatchSession.Announcement
    @ObservedObject var session: MatchSession
    let onContinue: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            // The scrim is a second way to continue for someone who can see it; VoiceOver has the button.
            ThroColor.colorScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onContinue)
                .accessibilityHidden(true)
            card
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            // After layout, so the element exists to receive focus.
            DispatchQueue.main.async { focused = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            // One element, read in one breath: "Bust. Alex stays on 141. That leaves 1. Sam to throw."
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                announcementBody
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($focused)
            ThroButton("Continue", variant: .primary, size: .large, fullWidth: true, action: onContinue)
                .padding(.top, ThroSpacing.spacing2)
        }
        .padding(ThroSpacing.spacing6)
        .frame(maxWidth: 340)
        .background(ThroColor.colorBackgroundRaised)
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: ThroSpacing.borderWidthHairline))
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
        .throElevation3()
        .padding(ThroSpacing.spaceScreenGutter)
    }

    @ViewBuilder private var announcementBody: some View {
        switch announcement {
        case let .bust(seat, restored, reason, next):
            Eyebrow("Bust", color: ThroColor.colorStatusError)
            Text("\(session.name(seat)) stays on")
                .thro(ThroTypography.heading3)
                .foregroundStyle(ThroColor.colorTextSecondary)
            Text("\(restored)")
                .thro(ThroTypography.sportHero)
                .foregroundStyle(ThroColor.colorStatusError)
            if let reason {
                Text(reason)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextSecondary)
            }
            if let next {
                Text("\(session.name(next)) to throw")
                    .thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.04))
                    .foregroundStyle(ThroColor.colorTextPrimary)
            }
        case let .legWon(leg, winner, legsHome, legsAway, next):
            Eyebrow("Leg \(leg)", color: ThroColor.colorTextBrand)
            Text("\(session.name(winner)) takes it")
                .thro(ThroTypography.heading3)
                .foregroundStyle(ThroColor.colorTextSecondary)
            Text("\(legsHome)–\(legsAway)")
                .thro(ThroTypography.sportHero)
                .foregroundStyle(ThroColor.colorTextPrimary)
            Text("\(session.name(.home)) – \(session.name(.away)) · \(session.lengthLabel)")
                .thro(ThroTypography.metadata.family(.sport))
                .foregroundStyle(ThroColor.colorTextSecondary)
            if let next {
                Text("\(session.name(next)) throws first")
                    .thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.04))
                    .foregroundStyle(ThroColor.colorTextPrimary)
            }
        }
    }
}

/// PD-001's question, in the keypad's place. The preset is the primary button; "Not sure" records
/// unknown; Cancel submits nothing.
public struct PromptCard: View {
    private let prompt: MatchSession.Prompt
    private let onAnswer: (Int?) -> Void
    private let onCancel: () -> Void

    public init(prompt: MatchSession.Prompt, onAnswer: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onAnswer = onAnswer
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Eyebrow(prompt.context)
            Text(prompt.question)
                .thro(ThroTypography.heading2)
                .foregroundStyle(ThroColor.colorTextPrimary)
            HStack(spacing: ThroSpacing.spacing2) {
                ForEach(prompt.options, id: \.self) { option in
                    ThroButton("\(option)", variant: option == prompt.preset ? .primary : .secondary,
                               size: .large, fullWidth: true) { onAnswer(option) }
                }
            }
            HStack(spacing: ThroSpacing.spacing2) {
                ThroButton("Not sure", variant: .ghost, size: .medium) { onAnswer(nil) }
                Spacer()
                ThroButton("Cancel", variant: .ghost, size: .medium, action: onCancel)
            }
            Text("Not sure is recorded as unknown — never as zero.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBackgroundPrimary)
    }
}

/// PD-004's undo, in the keypad's place. Confirming appends a retraction that strikes the visit;
/// nothing is deleted, and the struck visit stays in the record.
public struct RetractionCard: View {
    private let proposal: MatchSession.RetractionProposal
    private let playerName: String
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(proposal: MatchSession.RetractionProposal, playerName: String,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.proposal = proposal
        self.playerName = playerName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Eyebrow("Undo last visit")
            Text("Strike \(playerName)'s \(proposal.visitTotal)?")
                .thro(ThroTypography.heading2)
                .foregroundStyle(ThroColor.colorTextPrimary)
            Text("\(playerName) goes back to \(proposal.restoresTo). The visit stays in the record as struck; nothing is deleted.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
            HStack(spacing: ThroSpacing.spacing2) {
                ThroButton("Undo", variant: .destructive, size: .large, fullWidth: true, action: onConfirm)
                ThroButton("Keep", variant: .secondary, size: .large, fullWidth: true, action: onCancel)
            }
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBackgroundPrimary)
    }
}

// MARK: - Result

/// After `result` and `shadow-result`. No RatingMovement (OD-001: no rating model is validated) and
/// no TournamentProgress (there is no tournament). Evidence is self-reported, and the sync line says
/// plainly that nothing has left the phone, because no sync exists to queue it for.
public struct MatchResultScreen: View {
    @ObservedObject private var session: MatchSession
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    private let onDone: () -> Void
    private let onPlayAgain: () -> Void
    private let onReopen: () -> Void

    public init(session: MatchSession, onDone: @escaping () -> Void, onPlayAgain: @escaping () -> Void,
                onReopen: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        self.onPlayAgain = onPlayAgain
        self.onReopen = onReopen
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Result", eyebrow: "Local match", onBack: onDone)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section {
                        MatchSummary(
                            headline: session.winner.map { "\(session.name($0)) wins" } ?? "In progress",
                            won: session.winner != nil,
                            score: "\(session.legsWon(.home))–\(session.legsWon(.away))",
                            opponent: "\(session.name(.home)) v \(session.name(.away)) · \(session.formatLabel)"
                        )
                        Tag("Not rated", tone: .neutral, icon: .info).padding(.top, ThroSpacing.spacing4)
                    }
                    ThroDivider(inset: ThroSpacing.spaceScreenGutter)
                    ForEach(Seat.allCases, id: \.self) { seat in
                        section {
                            SectionHeader(session.name(seat))
                            StatGrid(session.statistics(for: seat).map { StatItem(label: $0.label, value: $0.value, note: $0.note) })
                        }
                        ThroDivider(inset: ThroSpacing.spaceScreenGutter)
                    }
                    section {
                        SectionHeader("Evidence")
                        VerificationState(.selfReported, explain: true)
                        Text("Saved on this device. Sending results to THRØ is not built yet, so this one has not left the phone.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    ThroDivider(inset: ThroSpacing.spaceScreenGutter)
                    if let proposal = session.retraction {
                        RetractionCard(proposal: proposal, playerName: session.name(proposal.seat),
                                       onConfirm: session.confirmRetraction, onCancel: session.cancelRetraction)
                    } else {
                        section {
                            ThroButton("Done", variant: .primary, size: .large, fullWidth: true, action: onDone)
                            ThroButton("Play again", variant: .secondary, size: .large, fullWidth: true, action: onPlayAgain)
                            // The mis-key that ends a match is the one that most needs undoing (PD-004).
                            ThroButton("Undo last visit", variant: .ghost, size: .medium, action: session.proposeRetraction)
                        }
                    }
                }
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
        .onReceive(session.$state) { state in
            if !state.isComplete { onReopen() }
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
    }
}
