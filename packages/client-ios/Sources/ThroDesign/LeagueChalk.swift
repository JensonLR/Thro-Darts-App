import SwiftUI
import ThroTokens

// League chalk (PD-046). A pub's board is chalked in more than one colour, and so is the leagues
// map: each league with teams on THRØ is drawn in a chalk of its own. Identity and not status — a
// league in pink is not in trouble — which is why the status inks are not borrowed for it. Colour
// is never the only thing that says which league: whatever is drawn in a league's chalk has the
// league's name written beside it, on the chip, on the team and in the pub's list.

/// The six chalks, dealt by a league's place and round again after the sixth.
public enum LeagueChalk {
    public static let all: [Color] = [ThroColor.colorLeague1OnBoard, ThroColor.colorLeague2OnBoard,
                                      ThroColor.colorLeague3OnBoard, ThroColor.colorLeague4OnBoard,
                                      ThroColor.colorLeague5OnBoard, ThroColor.colorLeague6OnBoard]

    /// The chalk for a place. Any integer is a place: round again after the last.
    public static func color(_ index: Int) -> Color {
        all[((index % all.count) + all.count) % all.count]
    }
}

/// A place on the leagues map, drawn as a small board.
///
/// A pub is ringed in the chalk of every league that plays there — one arc each, the way a
/// dartboard is segments — with the mark in the middle. A league placed by its own point, with no
/// pub known, is a ring inside a ring and no dart: where the league is roughly, not where you drink.
/// Out of the light (another league's pub while one is chosen) it is sunk: the bottom stop and grey
/// chalk, smaller. Never faded — the board has no alpha, and a faded pin is one nobody can read.
public struct BoardPin: View {
    public enum Kind: Sendable {
        case pub, league
        /// Places too close to tell apart at this scale, and how many: ringed in the chalk of every
        /// league among them, so a cluster still says whose pubs are in it.
        case count(Int)
    }
    public enum Light: Sendable { case field, lit, sunken }

    private let kind: Kind
    private let chalks: [Int]
    private let light: Light
    private let size: CGFloat

    public init(_ kind: Kind = .pub, chalks: [Int] = [], light: Light = .field, size: CGFloat = 32) {
        self.kind = kind
        self.chalks = chalks
        self.light = light
        self.size = size
    }

    private var ground: Color {
        switch light {
        case .field: return ThroColor.colorBoardField
        case .lit: return ThroColor.colorBoardLit
        case .sunken: return ThroColor.colorBoardSunken
        }
    }

    private var ink: Color { light == .sunken ? ThroColor.colorTextOnBoardSecondary : ThroColor.colorMarkOnBoard }

    private var weight: CGFloat {
        switch light {
        case .lit: return max(3, size * 0.1)
        case .field: return max(2.5, size * 0.08)
        case .sunken: return 1.5
        }
    }

    public var body: some View {
        ZStack {
            Circle().fill(ground)
            ring
            switch kind {
            case .pub:
                ThroMark().fill(ink).padding(size * 0.26)
            case .league:
                Circle().strokeBorder(ink, lineWidth: max(1.5, weight * 0.75)).padding(size * 0.3)
            case .count(let n):
                Text("\(n)")
                    .thro(ThroTypography.label.family(.sport).weight(.bold))
                    .foregroundStyle(light == .sunken ? ThroColor.colorTextOnBoardSecondary : ThroColor.colorTextOnBoard)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var ring: some View {
        if light == .sunken || chalks.isEmpty {
            Circle().strokeBorder(ink, lineWidth: weight)
        } else {
            let n = CGFloat(chalks.count)
            // A hair of board between segments, so two leagues read as two and not as one smear.
            let gap: CGFloat = chalks.count > 1 ? 0.03 : 0
            ForEach(Array(chalks.enumerated()), id: \.offset) { i, chalk in
                Circle()
                    .inset(by: weight / 2)
                    .trim(from: CGFloat(i) / n + gap / 2, to: CGFloat(i + 1) / n - gap / 2)
                    .stroke(LeagueChalk.color(chalk), style: StrokeStyle(lineWidth: weight, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
