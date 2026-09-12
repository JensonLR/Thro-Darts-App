import SwiftUI
import ThroTokens

// A page with nothing on it is the board (PD-068).
//
// `EmptyState` is a card, and a card is the right answer for a section that is empty among sections that
// are not — *no tournaments listed yet* under Discover sits beside leagues that do exist, and reads
// correctly as one part of a page. It is the wrong answer when the empty state **is** the page. On an
// iPhone that card is most of the screen and looks like the page; on an iPad it is a notice in the corner
// of a sheet of cream, with 77% of the glass empty beneath it. Cards fixed this on the phone (PD-052) and
// did not transfer, and centring the card was tried in that same pass and rejected — the same emptiness,
// redistributed.
//
// So a page with nothing on it stops pretending to be a page with something on it. It is the field: the
// green, the lamp and the grain the app opens on, with the invitation chalked on it. **It fills any screen
// by construction**, because a background has no size of its own to be too small — which is the whole
// reason this answers the question and a bigger card does not.
//
// It is a *state* and not a size, so it is the same on a phone as on a tablet. A screen that changed shape
// by device would be two designs to keep in step, and the point of the field is that it is one.

/// The whole page, when there is nothing to put on it.
public struct ThroNothingYet: View {
    private let title: String
    private let message: String
    private let actionLabel: String?
    private let onAction: (() -> Void)?
    private let seed: UInt32

    public init(title: String, message: String, actionLabel: String? = nil,
                seed: UInt32 = ThroBoardSeed.home, onAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.seed = seed
        self.onAction = onAction
    }

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.42), grainSeed: seed) {
            // The lamp sits a little above the middle and the words sit under it, so the brightest part of
            // the field is behind the reading rather than beside it — the same arrangement the opening has.
            VStack(spacing: ThroSpacing.spacing4) {
                Spacer(minLength: ThroSpacing.spacing6)
                Text(title)
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .thro(ThroTypography.bodyLarge)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionLabel, let onAction {
                    // A chalk key, the app's own on-board control — the same style the welcome screen's
                    // ways in use. A filled green button here would be a block of the field on the field,
                    // and rolling a chalk box by hand would be a second vocabulary for a thing that
                    // already has one, without the press state the board's keys have.
                    Button(action: onAction) {
                        Text(actionLabel)
                            .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                            // `ChalkKeyStyle` grounds the key and boxes it, and sets no ink: a keypad key
                            // inherits the board's. On the field the ink is chalk, and without this the
                            // label came out near-black on lit green.
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .padding(.horizontal, ThroSpacing.spacing6)
                    }
                    .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 23))
                    // A keypad key is full width because it is one of twenty in a tray. This is one
                    // invitation on an empty page, and stretched to the measure it read as a bar rather
                    // than something to press, so it takes the width of its own words.
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.top, ThroSpacing.spacing2)
                }
                Spacer(minLength: ThroSpacing.spacing6)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            // The words are a column even here: a sentence the width of a tablet is not a sentence
            // somebody reads, whatever it is written on (PD-052).
            .throReadable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
