import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The first screen after the opening, and the only one in THRØ that asks a person for anything.
//
// **Why it exists.** Sign-in lived four taps in — You, then SIGN IN, then a settings list with the
// ways in stacked under a paragraph. Nobody found it, so nobody had a THRØ ID, so nothing that
// needs one (a name on a team sheet, a friend, a league) could reach them. The founder:
// *"sign in should be at the loading page before main screen, should encourage people to sign up."*
//
// **Why it is a board and not a form.** The opening ends with a dart in a board. If the next frame
// is a white sheet with two grey buttons on it, the app has just told the player that the beautiful
// part is over. So this IS the board the dart landed in: the same lamp, the same chalk dust, the
// wordmark where the mark settled, and the ways in drawn as the keys the scoring screen uses. The
// handover is one world, not two.
//
// **Why "Not now" is real and easy to hit.** PD-012 is local-first: two people can score a match on
// one phone with no account, no network and no permission, and that is not a trial — it is the
// product. A gate that trapped them would be a lie about what THRØ is. So the door out is plain
// text, plainly placed, and the copy says what staying out costs, which is nothing on this phone.
// Encouraging is not the same as cornering.

/// The rules about when the welcome is shown, apart from any view so a test can state them.
public enum Welcome {
    /// Set once the screen has been answered, either way. A person is asked this question once.
    public static let seenKey = "thro.welcome.seen"

    /// Whether to show it at all.
    ///
    /// - `configured`: this build has a server to sign in to. Without one there is nothing to ask.
    /// - `signedIn`: already answered, by having an account.
    /// - `seen`: asked before, and answered either way.
    public static func shows(configured: Bool, signedIn: Bool, seen: Bool) -> Bool {
        configured && !signedIn && !seen
    }

    /// The headline. Short, and about the player rather than the product.
    public static let headline = "Get your name on it"

    /// What an account is actually for, in the terms this build can stand behind. Every clause is
    /// something THRØ does: a team names you in a lineup (V029), a league registers you (V014), a
    /// friend adds you by a code (PD-035).
    public static let body =
        "A THRØ ID is what a team puts in its lineup, what a league registers, and what a friend "
        + "adds by code. It takes one tap."

    /// The promise that makes the door out honest. It is checked by a test, because the day this
    /// stops being true is the day the sentence has to come off the screen.
    public static let promise = "Matches scored on this phone stay on this phone, signed in or not."

    /// The door out, worded for why the screen is up.
    public static func skip(_ ask: Ask) -> String {
        switch ask {
        case .atLaunch: return "Not now, just score"
        // Asked for from the You tab, "just score" would be answering a question nobody put: the
        // player came here on purpose and wants back where they were.
        case .fromYou: return "Back"
        }
    }

    /// Why the screen is up. It is the SAME screen either way — there is one way in and it is the
    /// good one — but the door out is worded for the person going through it, and only the launch
    /// ask is the one a person is asked once.
    public enum Ask {
        /// After the opening, unprompted, once ever.
        case atLaunch
        /// The player tapped SIGN IN on the You tab.
        case fromYou
    }
}

/// The welcome, on the board the opening left behind.
public struct WelcomeScreen: View {
    @ObservedObject private var account: AccountStore
    private let ask: Welcome.Ask
    private let onDone: () -> Void
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The blocks have arrived.
    @State private var arrived = false
    /// How much of the rule under the wordmark has been drawn, 0 to 1.
    @State private var chalk: CGFloat = 0

    public init(account: AccountStore, ask: Welcome.Ask = .atLaunch, onDone: @escaping () -> Void) {
        self.account = account
        self.ask = ask
        self.onDone = onDone
    }

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.18), grainSeed: ThroBoardSeed.home) {
            // **Everything a hand touches is in the bottom half, everything it reads is in the top.**
            // The first version centred one block and left a hole above and below it. A board is
            // written top-down and the keys go where the thumb is, so the composition is the one a
            // scoreboard already has: the heading chalked at the top, the choices at the bottom.
            // Masthead, ask, choices — with the slack SHARED between the first two gaps rather than
            // all of it dumped below the sentence. One spacer left a hole in the middle of the
            // screen with the writing pinned above it and the keys pinned below.
            VStack(spacing: 0) {
                masthead
                Spacer(minLength: ThroSpacing.spacing5)
                pitch
                Spacer(minLength: ThroSpacing.spacing5)
                choices
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        }
        // No `.ignoresSafeArea()` here. `ThroBoard` already bleeds its lamp, dust and vignette to
        // every edge while keeping its CONTENT inside the safe area — the distinction that exists
        // because the scoring screen once put its rail under the Dynamic Island. Overriding it here
        // cut the top off the wordmark.
        .throAppearance(Appearance(stored: appearanceRaw))
        .onAppear(perform: enter)
        // Answered by signing in: the screen goes as soon as the account arrives, without a second
        // tap to dismiss something the player has already finished with.
        .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { finish() } }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - arriving
    //
    // **The rule is drawn, it does not fade in.** Every other screen in THRØ uses `throEntrance`,
    // which rises and fades on a 45 ms stagger — right for a list of rows settling, wrong for the
    // one screen that is a moment. Here the wordmark appears, a line of chalk is drawn across the
    // board under it, and only then does the rest arrive. It is the app's own gesture — the same
    // `ChalkRule.trim` the component was built with — rather than an effect borrowed from
    // somewhere, and `throLanding` is deliberately NOT used: that one is the impact of a dart and
    // belongs to the outcome of a match and nothing else.

    /// The beat each block arrives on, in seconds after the screen appears.
    enum Beat {
        static let wordmark = 0.00
        static let rule = 0.18
        static let ruleDraw = 0.62
        static let heading = 0.44
        static let keys = 0.58
        static let footer = 0.74
    }

    private func enter() {
        guard !reduceMotion else { arrived = true; chalk = 1; return }
        withAnimation(.throEnter(ThroMotion.motionDurationEmphasis)) { arrived = true }
        // Drawn rather than eased to a stop: chalk leaves the board at the speed it was moving.
        withAnimation(.easeOut(duration: Beat.ruleDraw).delay(Beat.rule)) { chalk = 1 }
    }

    private var shown: Bool { arrived || reduceMotion }

    /// One block arriving on its own beat.
    private func arriving<V: View>(_ after: Double, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : ThroSpacing.motionTravelMedium)
            .animation(reduceMotion ? nil : .throEnter(ThroMotion.motionDurationEmphasis).delay(after), value: arrived)
    }

    // MARK: - the heading

    @ViewBuilder private var masthead: some View {
        VStack(spacing: ThroSpacing.spacing4) {
            arriving(Beat.wordmark) {
                ThroWordmark(capHeight: ThroTypography.display.capHeight * 1.35, color: ThroColor.colorTextOnBoard)
                    .accessibilityLabel("THRØ")
            }
            ChalkRule(weight: ThroSpacing.spaceChalkRuleWeight, seedAngle: 41, trim: chalk)
                .fill(ThroColor.colorMarkOnBoard)
                .frame(height: ThroSpacing.spaceChalkRuleWeight * 2)
                .accessibilityHidden(true)
        }
        .padding(.top, ThroSpacing.spacing6)
    }

    @ViewBuilder private var pitch: some View {
        arriving(Beat.heading) {
            VStack(spacing: ThroSpacing.spacing3) {
                Text(Welcome.headline)
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Welcome.body)
                    .thro(ThroTypography.bodyLarge)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - the choices

    @ViewBuilder private var choices: some View {
        VStack(spacing: ThroSpacing.spacing5) {
            arriving(Beat.keys) { waysIn }
            arriving(Beat.footer) {
                VStack(spacing: ThroSpacing.spacing3) {
                    // The rule that closes the board. A scoreboard is ruled top and bottom, and the
                    // screen had one line at the top and an open bottom, which is what left it
                    // feeling like a page rather than a board. It is drawn from the RIGHT, so the
                    // two rules meet the composition from opposite ends.
                    ChalkRule(weight: ThroSpacing.spaceChalkRuleWeight, seedAngle: 113, trim: chalk)
                        .fill(ThroColor.colorMarkOnBoard)
                        .frame(height: ThroSpacing.spaceChalkRuleWeight * 2)
                        .scaleEffect(x: -1, y: 1, anchor: .center)
                        .padding(.bottom, ThroSpacing.spacing2)
                        .accessibilityHidden(true)
                    Button(action: skip) {
                        Text(Welcome.skip(ask))
                            .thro(ThroTypography.labelStrong)
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .underline()
                            .throTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusControl, pressedFill: ThroColor.colorBoardSunken))
                    Text(Welcome.promise)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, ThroSpacing.spacing5)
    }

    // MARK: - the ways in

    @ViewBuilder private var waysIn: some View {
        switch account.state {
        case .busy(let what):
            VStack(spacing: ThroSpacing.spacing3) {
                ProgressView().tint(ThroColor.colorTextOnBoard)
                Text(what)
                    .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                // The free server sleeps. Saying so is kinder than a spinner that looks stuck.
                Text("Waiting on THRØ. The first sign-in of the day can take up to a minute.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThroSpacing.spacing5)
        default:
            VStack(spacing: ThroSpacing.spacing3) {
                if case .failed(let why, _) = account.state {
                    // Boxed in chalk, the way anything that matters gets boxed on a board — rather
                    // than a line of loose red text floating between the sentence and the keys.
                    // The words are the server's own, or `SignInProblem`'s; never a domain and a code.
                    Text(why)
                        .thro(ThroTypography.label)
                        .foregroundStyle(ThroColor.colorStatusErrorOnBoard)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, ThroSpacing.spacing3)
                        .padding(.horizontal, ThroSpacing.spacing4)
                        .frame(maxWidth: .infinity)
                        .overlay(ChalkBox(weight: 2).fill(ThroColor.colorStatusErrorOnBoard))
                        .padding(.bottom, ThroSpacing.spacing2)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }
                // **Two keys, not three.** Three identical boxes had no hierarchy in them and read
                // as a list of equally likely choices, which is not true: almost everybody arrives
                // with an Apple or a Google account, and a passkey is PD-030's fallback for the few
                // who have neither. So the two real ways in are keys and the third is a quiet line,
                // which is also what takes the screen from three rectangles down to two.
                wayIn("Continue with Apple", symbol: "apple.logo", lighting: .lit, seed: 11) {
                    Task { await account.signInWithApple() }
                }
                if account.configuration.googleClientID != nil {
                    wayIn("Continue with Google", symbol: nil, lighting: .field, seed: 53) {
                        Task { await account.signInWithGoogle() }
                    }
                }
                Button { Task { await account.usePasskey() } } label: {
                    HStack(spacing: ThroSpacing.spacing2) {
                        Icon(.lock, size: 15)
                        Text("Use a passkey instead")
                            .thro(ThroTypography.label)
                    }
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .frame(maxWidth: .infinity)
                    .throTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusControl, pressedFill: ThroColor.colorBoardSunken))
                .padding(.top, ThroSpacing.spacing1)
            }
        }
    }

    /// One way in: a chalk key, full width, at the scoring target's height. The same control the
    /// keypad is made of, because this screen is the same board.
    private func wayIn(_ title: String, symbol: String?, icon: ThroIcon? = nil,
                       lighting: ChalkKeyStyle.Lighting, seed: Double,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing2) {
                // Apple's own mark, as Sign in with Apple requires of a custom button.
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .medium)) }
                if let icon { Icon(icon, size: 18) }
                Text(title)
                    .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
            }
            .foregroundStyle(ThroColor.colorTextOnBoard)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChalkKeyStyle(lighting, minHeight: ThroSpacing.touchTargetScoring, seedAngle: seed))
    }

    // MARK: - leaving

    private func skip() {
        ThroHaptics.play(.key)
        finish()
    }

    private func finish() {
        // Answering the question answers it however it was reached: somebody who signs in from the
        // You tab is not asked again at the next launch.
        UserDefaults.standard.set(true, forKey: Welcome.seenKey)
        onDone()
    }
}
