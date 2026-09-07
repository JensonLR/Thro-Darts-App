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
        case confirming(MatchSession)
    }

    private let journal: Journal
    private let onExit: () -> Void
    /// Who plays on this phone, and how a typed name becomes one of them (ADR-016).
    ///
    /// A closure rather than a store, because `ThroPlay` has no business knowing where the device's
    /// book of people lives — it knows about matches. The default keeps every match unattributed,
    /// which is exactly what every match written before ADR-016 is, and is readable for ever.
    private let people: [LocalPerson]
    private let resolvePerson: (String) -> String?
    @State private var step: Step
    @State private var problem: String?

    /// Starts a new match, or resumes `resume` where it left off.
    public init(journal: Journal, resume: MatchId? = nil, people: [LocalPerson] = [],
                resolvePerson: @escaping (String) -> String? = { _ in nil },
                onExit: @escaping () -> Void) {
        self.journal = journal
        self.people = people
        self.resolvePerson = resolvePerson
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

    /// The same match, with each name resolved to the person it refers to. If the book cannot be
    /// written the match is played and saved anyway, unattributed — losing a match to bookkeeping
    /// would be a far worse failure than not knowing whose it was.
    private func attributed(_ new: NewMatch) -> NewMatch {
        NewMatch(homeName: new.homeName, awayName: new.awayName, startingScore: new.startingScore,
                 inRule: new.inRule, outRule: new.outRule, legsMode: new.legsMode,
                 legsTarget: new.legsTarget, throwFirst: new.throwFirst,
                 homePlayerId: resolvePerson(new.homeName), awayPlayerId: resolvePerson(new.awayName))
    }

    public var body: some View {
        switch step {
        case let .setup(home, away):
            MatchSetupScreen(initialHome: home, initialAway: away, problem: problem, people: people,
                             onBack: onExit) { new in
                do {
                    step = .ready(try MatchSession.start(attributed(new), in: journal))
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
                              onReopen: { step = .scoring(session) },
                              onConfirmResult: { step = .confirming(session) })
        case .confirming(let session):
            ConfirmResultScreen(session: session) { step = .result(session) }
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
    /// Straight or double in. The engine also scores master-in, which competitions define and this
    /// screen does not offer, because no one asks for it at a pub board.
    @State private var inRule: InRule = .straight
    @FocusState private var focused: NameField?
    private let problem: String?
    private let onBack: () -> Void
    private let onStart: (NewMatch) -> Void

    private enum NameField: Hashable { case home, away }

    public init(initialHome: String = "", initialAway: String = "", problem: String? = nil,
                people: [LocalPerson] = [],
                onBack: @escaping () -> Void, onStart: @escaping (NewMatch) -> Void) {
        _home = State(initialValue: initialHome)
        _away = State(initialValue: initialAway)
        self.people = people
        self.problem = problem
        self.onBack = onBack
        self.onStart = onStart
    }

    /// Who plays on this phone (ADR-016). Tapping one fills the field, which is the whole feature:
    /// nobody wants to retype their opponent's name every Tuesday, and a name typed the same way
    /// every time is what makes a person's matches theirs rather than three strangers'.
    private let people: [LocalPerson]

    /// The people not already chosen for the other seat, so the same person cannot be both players.
    private func suggestions(excluding taken: String) -> [LocalPerson] {
        let takenKey = taken.trimmingCharacters(in: .whitespaces).lowercased()
        return people.filter { $0.name.lowercased() != takenKey }
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
                    known(suggestions(excluding: away)) { home = $0.name }
                    ThroTextField("Away player", text: $away, placeholder: "Name")
                        .modifier(NameEntry())
                        .focused($focused, equals: .away)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                    known(suggestions(excluding: home)) { away = $0.name }
                    ThroDivider()
                    choice("Game", SegmentedControl([(301, "301"), (501, "501"), (701, "701")], selection: $game))
                    choice("Length", SegmentedControl([(3, "Bo3"), (5, "Bo5"), (7, "Bo7"), (9, "Bo9")], selection: $length))
                    choice("Start on", SegmentedControl([(InRule.straight, "Any"), (InRule.double, "Double in")],
                                                        selection: $inRule))
                    choice("Throws first", SegmentedControl([(Seat.home, homeName), (Seat.away, awayName)], selection: $first))
                    ThroDivider()
                    HStack(alignment: .top, spacing: 10) {
                        Icon(.info, size: 16).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, 2)
                        Text("Matches scored on this device are self-reported and are not rated. They stay on this phone; sending them to THRØ is not built yet.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    ThroButton("Continue", variant: .primary, size: .large, fullWidth: true) {
                        onStart(NewMatch(homeName: homeName, awayName: awayName, startingScore: game,
                                         inRule: inRule, outRule: .double,
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

    /// The people this phone already knows, as a row of taps. Absent entirely when it knows nobody,
    /// so a first match looks exactly as it did before any of this existed.
    @ViewBuilder private func known(_ list: [LocalPerson], pick: @escaping (LocalPerson) -> Void) -> some View {
        if !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(list) { person in
                        Button { pick(person) } label: {
                            Text(person.name)
                                .thro(ThroTypography.metadata.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                                .lineLimit(1)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 12)
                                .background(ThroColor.colorBackgroundSecondary,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .padding(.top, -ThroSpacing.spacing3)
        }
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
                        if let inRule = session.inRuleLabel { Tag(inRule) }
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
    @AppStorage(ThroHaptics.enabledKey) private var haptics: Bool = true
    /// The player's own text size, read **before** this screen caps it — the cap is applied to the
    /// body below, so what arrives here is what they actually asked for.
    @Environment(\.dynamicTypeSize) private var typeSize
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
                            onBack: onLeave,
                            onEnd: session.mayEndShort ? session.offerToEnd : nil)
                // Everything above the keypad shares the height the keypad leaves. At ordinary text
                // sizes nothing scrolls and nothing is cut off: when a phone is short, the hero
                // numeral yields first.
                //
                // **Past the scoring ceiling it scrolls instead (PD-024)**, so a player who needs the
                // largest text gets it on the numbers they read rather than being capped at
                // `.accessibility1`. The keypad below is unaffected on purpose — see `lower`.
                if reflows {
                    ScrollView { upper }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    upper
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                lower
            }
            if let announcement = session.announcement {
                AnnouncementOverlay(announcement: announcement, session: session, onContinue: session.acknowledge)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
        // PD-015, amended by PD-024. Below the reflow threshold this is the one screen that must fit
        // without scrolling, so it is the one screen with a ceiling. Above it, the upper region
        // scrolls and the text grows the rest of the way.
        .throScoringTypeCeiling(reflowing: reflows)
        .onReceive(session.$state) { state in
            if state.isComplete { onComplete() }
        }
        // A match ended short is over too, and leaves for the same screen (PD-016).
        .onReceive(session.$ending) { if $0 != nil { onComplete() } }
        // PD-015. A bust and a won leg are the two things a player needs to know without looking at
        // the phone, so they are the two that get a distinct sensation rather than the keypad's tap.
        .onReceive(session.$announcement) { announcement in
            switch announcement {
            case .bust: ThroHaptics.play(.refused, enabled: haptics)
            case .legWon: ThroHaptics.play(.legWon, enabled: haptics)
            case nil: break
            }
        }
        .onAppear { setIdleTimer(disabled: keepScreenAwake) }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    /// Whether the screen has changed shape for a player who needs large text (PD-024).
    private var reflows: Bool { ThroDynamicType.reflows(at: typeSize) }

    /// The keypad, or whatever is standing in its place.
    ///
    /// One place at a time, in the keypad's own space — the precedent `PromptCard` and
    /// `RetractionCard` already set. Ending outranks a retraction proposal: a player who reaches for
    /// the way out while an undo is offered means the way out.
    ///
    /// **The keypad keeps the scoring ceiling at every text size**, which is what *pinned* means: the
    /// key under a thumb is the same size and in the same place whatever the player's setting. The
    /// cards do not — they carry the PD-001 question and a retraction's explanation, which are things
    /// to be read, so they grow with everything else above them.
    @ViewBuilder private var lower: some View {
        if let flow = session.endFlow {
            switch flow {
            case .choosing:
                EndMatchCard(session: session, onChoose: session.proposeEnding, onCancel: session.cancelEnding)
            case let .confirming(ending):
                EndMatchConfirmCard(session: session, ending: ending,
                                    onConfirm: session.confirmEnding, onCancel: session.cancelEnding)
            }
        } else if let prompt = session.prompt {
            PromptCard(prompt: prompt, onAnswer: session.answer, onCancel: session.cancelPrompt)
        } else if let proposal = session.retraction {
            RetractionCard(proposal: proposal, playerName: session.name(proposal.seat),
                           onConfirm: session.confirmRetraction, onCancel: session.cancelRetraction)
        } else {
            ScoreKeypad(value: session.entry, disabled: session.isComplete || session.announcement != nil,
                        onDigit: session.digit, onQuick: session.quick,
                        onMiss: session.miss, onClear: session.undoKey, onEnter: session.enter)
                .throPinnedKeypadTypeCeiling()
        }
    }

    private var upper: some View {
        VStack(spacing: 0) {
            legRow.padding(.top, ThroSpacing.spacing5).padding(.bottom, ThroSpacing.spacing2)
            remaining
                .padding(.top, ThroSpacing.spacing2)
                .padding(.bottom, ThroSpacing.spacing1)
                .layoutPriority(-1)
            if session.bust == nil, session.throwerMustOpen, let seat = session.thrower {
                // Not in. This is said before anything else, because a player whose 60 does not go on
                // the board must be told why on the same frame. Type and colour from the token layer;
                // no component is invented for it, since the export draws no double-in screen.
                Text("\(session.name(seat)) is not in. Enter what counts from the double — 0 if it did not come.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThroSpacing.spacing2)
                    .accessibilityAddTraits(.isStaticText)
            } else if session.bust == nil, session.throwerOnAFinish, let seat = session.thrower {
                // The hero already shows the number in brand green; the card names the fact, as the
                // export's checkout screen does with its value hidden — and now carries the route
                // (PD-013), which is the slot the export drew and nothing had ever filled.
                CheckoutCard(required: session.remaining(seat), route: session.throwerRoute,
                             compact: true, hideValue: true)
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

// MARK: - Ending a match short (PD-016)

/// The offer. Two buttons, because a retirement and an abandonment are different things and the app
/// must not pick for the player: one hands somebody the win, the other hands it to nobody.
///
/// Drawn in the system's idiom rather than invented — the same `Eyebrow` / heading / metadata /
/// button stack `RetractionCard` uses, because this is the same kind of moment: a serious, recorded
/// thing being offered with its consequence stated before it is taken.
public struct EndMatchCard: View {
    private let session: MatchSession
    private let onChoose: (Ending) -> Void
    private let onCancel: () -> Void

    public init(session: MatchSession, onChoose: @escaping (Ending) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.onChoose = onChoose
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Eyebrow("End this match")
            Text("How did it end?")
                .thro(ThroTypography.heading2)
                .foregroundStyle(ThroColor.colorTextPrimary)
            Text("The darts already thrown are kept either way. What differs is whether anybody won.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Seat.allCases, id: \.self) { seat in
                ThroButton("\(session.name(seat)) retires", variant: .secondary, size: .large,
                           fullWidth: true, action: { onChoose(.retired(by: seat)) })
            }
            ThroButton("Abandon — nobody wins", variant: .secondary, size: .large,
                       fullWidth: true, action: { onChoose(.abandoned) })
            ThroButton("Keep playing", variant: .ghost, size: .medium, action: onCancel)
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBackgroundPrimary)
    }
}

/// The confirmation. An ending is final and nothing undoes it, so it is never one tap away and the
/// consequence is spelt out in the same sentence as the button that causes it.
public struct EndMatchConfirmCard: View {
    private let session: MatchSession
    private let ending: Ending
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(session: MatchSession, ending: Ending,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.ending = ending
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var headline: String {
        switch ending {
        case let .retired(by): return "\(session.name(by)) retires?"
        case .abandoned: return "Abandon this match?"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Eyebrow("End this match")
            Text(headline)
                .thro(ThroTypography.heading2)
                .foregroundStyle(ThroColor.colorTextPrimary)
            Text(session.endingConsequence(ending))
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Said outright, because it is the part that would be a surprise. PD-004 makes a
            // mis-keyed visit undoable and a player will reasonably expect the same here.
            Text("This cannot be undone.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorStatusError)
            HStack(spacing: ThroSpacing.spacing2) {
                ThroButton("End the match", variant: .destructive, size: .large, fullWidth: true, action: onConfirm)
                ThroButton("Back", variant: .secondary, size: .large, fullWidth: true, action: onCancel)
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
    private let onConfirmResult: () -> Void

    public init(session: MatchSession, onDone: @escaping () -> Void, onPlayAgain: @escaping () -> Void,
                onReopen: @escaping () -> Void, onConfirmResult: @escaping () -> Void = {}) {
        self.session = session
        self.onDone = onDone
        self.onPlayAgain = onPlayAgain
        self.onReopen = onReopen
        self.onConfirmResult = onConfirmResult
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Result", eyebrow: "Local match", onBack: onDone)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section {
                        MatchSummary(
                            headline: session.resultHeadline,
                            won: session.winner != nil,
                            score: "\(session.legsWon(.home))–\(session.legsWon(.away))",
                            opponent: "\(session.name(.home)) v \(session.name(.away)) · \(session.formatLabel)"
                        )
                        if let detail = session.resultDetail {
                            Text(detail)
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Tag("Not rated", tone: .neutral, icon: .info).padding(.top, ThroSpacing.spacing4)
                    }
                    ThroDivider(inset: ThroSpacing.spaceScreenGutter)
                    ForEach(Seat.allCases, id: \.self) { seat in
                        section {
                            SectionHeader(session.name(seat))
                            StatGrid(session.statistics(for: seat).map(\.item))
                        }
                        ThroDivider(inset: ThroSpacing.spaceScreenGutter)
                    }
                    section {
                        SectionHeader("Evidence")
                        if session.ending == .abandoned {
                            // No result, so no label. A verification badge here would be attesting
                            // to nothing, and "self-reported" on an abandoned match reads as a
                            // claim somebody made rather than as the absence of one.
                            Text("There is no result to verify. The visits are recorded as thrown; nothing is claimed about who won, because nobody did.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                        VerificationState(session.verification, explain: true)
                        if session.verification == .participantConfirmed {
                            // Said plainly, because the label alone would flatter it. Two people at
                            // one phone is the weakest form of participant-confirmed: it is an
                            // assertion by somebody standing there, not corroboration by a second
                            // device, and the names are the ones typed at setup.
                            Text("\(session.name(.home)) and \(session.name(.away)) both confirmed this on this phone. That is two people agreeing, not two devices — and the names are the ones typed at the start.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if session.verification == .disputed {
                            Text("Somebody said this is not right. Nothing has been deleted: the result stands as recorded and is marked. Undo the visit that is wrong and confirm again.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if session.standing.stale {
                            Text("The result changed after it was agreed, so the agreement no longer applies to it. Confirm it again.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        }
                        Text("Saved on this device. Sending results to THRØ is not built yet, so this one has not left the phone.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                        if !session.awaitingAttestation.isEmpty {
                            ThroButton("Confirm the result", variant: .secondary, size: .large,
                                       fullWidth: true, action: onConfirmResult)
                        }
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
                            // Not on an ended match: the journal refuses it there (PD-016), and a
                            // button whose only outcome is a refusal is worse than no button.
                            if session.ending == nil {
                                ThroButton("Undo last visit", variant: .ghost, size: .medium, action: session.proposeRetraction)
                            }
                        }
                    }
                }
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
        // Undoing the visit that won a match reopens it. An ended match must NOT reopen: the engine
        // never said it was complete, so `state.isComplete` is false for a perfectly ended match and
        // this would have bounced straight back to the keypad on a retirement.
        .onReceive(session.$state) { state in
            if !state.isComplete && session.ending == nil { onReopen() }
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
    }
}

// MARK: - Confirming the result (PD-011)

/// One player at a time, on the one phone, saying whether the result is right.
///
/// **Why this exists.** `docs/design/DESIGN_UNSPECIFIED.md` called participant attestation the single
/// highest-value missing item, because PD-002 says one player's word never moves a rating and the
/// participant app had no way for the second player to say anything at all. The founder commissioned
/// this screen (PD-011) on PD-010's terms: tokens only, approved components, on the record.
///
/// **What it is honest about.** Two people at one phone is the weakest form of the trust model's
/// `participant-confirmed`: an assertion by somebody standing there, not corroboration by a second
/// independent device, under names typed at setup rather than accounts. It is still the difference
/// between one person's word and two, which is what PD-002 asks for — and every screen that shows
/// the label says which it is.
///
/// **What a refusal does.** Nothing is deleted. The result stands exactly as recorded and is marked
/// contested; the way to change it is the retraction PD-004 already defines. An app that let a
/// disagreement erase evidence would be worse than one that recorded no disagreement at all.
public struct ConfirmResultScreen: View {
    @ObservedObject private var session: MatchSession
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    private let onDone: () -> Void

    public init(session: MatchSession, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
    }

    private var asking: Seat? { session.awaitingAttestation.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Confirm the result", eyebrow: "Local match", onBack: onDone)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    MatchSummary(
                        headline: session.resultHeadline,
                        won: session.winner != nil,
                        score: "\(session.legsWon(.home))–\(session.legsWon(.away))",
                        opponent: "\(session.name(.home)) v \(session.name(.away)) · \(session.formatLabel)"
                    )
                    // A retirement is exactly the kind of result people later disagree about, so
                    // what is being confirmed is said before the question is asked.
                    if let detail = session.resultDetail {
                        Text(detail)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let seat = asking {
                        asking(seat)
                    } else {
                        done
                    }
                    Note("Nothing is deleted either way. A result somebody does not accept is marked, not removed — and the way to change it is to undo the visit that is wrong.")
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
    }

    /// The ask, addressed to one person by name, so the phone gets handed to the right hand.
    @ViewBuilder private func asking(_ seat: Seat) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            HStack(spacing: ThroSpacing.spacing3) {
                PlayerIdentity(PlayerRef(name: session.name(seat)), size: .medium)
                Spacer(minLength: 0)
            }
            Text("\(session.name(seat)) — is this right?")
                .thro(ThroTypography.heading3)
                .foregroundStyle(ThroColor.colorTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Hand the phone over. Each player says for themselves, and their answer is on the record with the match.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ThroButton("Yes, that is the result", variant: .primary, size: .large, fullWidth: true) {
                session.attest(seat, agrees: true)
            }
            ThroButton("No, something is wrong", variant: .secondary, size: .large, fullWidth: true) {
                session.attest(seat, agrees: false)
            }
            if let notice = session.notice, notice.tone == .error {
                Snackbar(notice.text, tone: .error)
            }
        }
    }

    /// Both have answered. What the answers add up to, in words rather than a label alone.
    @ViewBuilder private var done: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            VerificationState(session.verification, explain: true)
            Text(session.verification == .participantConfirmed
                 ? "Both players agreed. On this phone that means two people standing behind it, under the names typed at the start — not two devices, and not accounts."
                 : "Recorded as contested. The result stands exactly as it was; undo the visit that is wrong and ask again.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ThroButton("Done", variant: .primary, size: .large, fullWidth: true, action: onDone)
        }
    }
}

/// The same quiet line the club screens use. Declared here because `ThroPlay` does not import them.
private struct Note: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.info, size: 16).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, 2)
            Text(text)
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
