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

    /// The door out.
    public static let skip = "Not now, just score"
}

/// The welcome, on the board the opening left behind.
public struct WelcomeScreen: View {
    @ObservedObject private var account: AccountStore
    private let onDone: () -> Void
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue

    public init(account: AccountStore, onDone: @escaping () -> Void) {
        self.account = account
        self.onDone = onDone
    }

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.26), grainSeed: ThroBoardSeed.home) {
            // Three groups and two flexible gaps: the name at the top, the ask in the middle, the
            // way past it at the bottom. Five spacers made five gaps of equal weight, which is how
            // a screen ends up with a hole in the middle of it.
            VStack(spacing: 0) {
                VStack(spacing: ThroSpacing.spacing4) {
                    ThroWordmark(capHeight: ThroTypography.display.capHeight * 1.3, color: ThroColor.colorTextOnBoard)
                        .accessibilityLabel("THRØ")
                        .throEntrance(0)
                    // The rule the wordmark sits on, drawn the way a board's own rules are.
                    ChalkRule(weight: ThroSpacing.spaceChalkRuleWeight, seedAngle: 41)
                        .fill(ThroColor.colorMarkOnBoard)
                        .frame(height: ThroSpacing.spaceChalkRuleWeight * 2)
                        .padding(.horizontal, ThroSpacing.spacing7)
                        .throEntrance(1)
                }
                .padding(.top, ThroSpacing.spacing7)

                Spacer(minLength: ThroSpacing.spacing5)

                // The ask: the sentence and the ways in are ONE thing, so they hold together as a
                // block in the middle of the board rather than drifting to opposite ends of it.
                VStack(spacing: ThroSpacing.spacing6) {
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
                            .padding(.horizontal, ThroSpacing.spacing3)
                    }
                    .throEntrance(2)
                    waysIn
                        .throEntrance(3)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)

                Spacer(minLength: ThroSpacing.spacing5)

                VStack(spacing: ThroSpacing.spacing3) {
                    Button(action: skip) {
                        Text(Welcome.skip)
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
                        .padding(.horizontal, ThroSpacing.spacing5)
                }
                .padding(.bottom, ThroSpacing.spacing5)
                .throEntrance(4)
            }
        }
        // No `.ignoresSafeArea()` here. `ThroBoard` already bleeds its lamp, dust and vignette to
        // every edge while keeping its CONTENT inside the safe area — the distinction that exists
        // because the scoring screen once put its rail under the Dynamic Island. Overriding it here
        // cut the top off the wordmark.
        .throAppearance(Appearance(stored: appearanceRaw))
        // Answered by signing in: the screen goes as soon as the account arrives, without a second
        // tap to dismiss something the player has already finished with.
        .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { finish() } }
        .accessibilityAddTraits(.isModal)
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
                    // The server's own sentence, on the board, in the board's error ink. Never
                    // "something went wrong".
                    Text(why)
                        .thro(ThroTypography.label)
                        .foregroundStyle(ThroColor.colorStatusErrorOnBoard)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, ThroSpacing.spacing1)
                }
                wayIn("Continue with Apple", symbol: "apple.logo", lighting: .lit, seed: 11) {
                    Task { await account.signInWithApple() }
                }
                if account.configuration.googleClientID != nil {
                    wayIn("Continue with Google", symbol: nil, lighting: .field, seed: 53) {
                        Task { await account.signInWithGoogle() }
                    }
                }
                wayIn("Use a passkey", symbol: nil, icon: .lock, lighting: .field, seed: 97) {
                    Task { await account.usePasskey() }
                }
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
        UserDefaults.standard.set(true, forKey: Welcome.seenKey)
        onDone()
    }
}
