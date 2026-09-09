import SwiftUI
import ThroTokens

// SLATE, B.5 — the numeral system.
//
// The one number this product exists to move is a player's remaining score, and until now it was a
// single `Text` with `.minimumScaleFactor(0.5)` on it. Three consequences, all of them visible on a
// phone and none of them caught by anything:
//
//  - **It migrated sideways as it came down.** `501` and `41` are different widths in any face, so
//    a centred figure walked left and right across the screen through a leg. The number a player
//    glances at between darts was never in the same place twice.
//  - **It changed size as it came down.** `minimumScaleFactor` is what a figure does when nobody
//    chose a size for it: three digits shrank to fit and two did not, so the hero was smaller at
//    501 than at 41 — exactly backwards from what a player needs.
//  - **Every digit re-rendered on every change.** With one `Text` there is no such thing as "the
//    digit that changed", so nothing could land, and the app's most important moment was a swap.
//
// A register fixes all three by being what a scoreboard is: a fixed number of cells of a fixed
// width, right-aligned, with the empty leading ones **empty** — never a leading zero, which would
// be a number the player does not have, and never a ghost, which would be an opacity.

/// A figure in a fixed-cell register, with its basis drawn under it.
///
/// Every cell is its own `Text`, so a changed digit is independently animatable and an unchanged one
/// does not move at all. That is the whole reason for the construction: on a board, `140` becoming
/// `139` moves one digit, and a scoreboard where all three jump is a screen redrawing itself.
public struct ThroFigure: View {
    private let text: String
    private let role: ThroTypeRole
    private let cells: Int
    private let basis: ThroBasis
    private let ink: Color
    private let markInk: Color

    public init(_ text: String,
                role: ThroTypeRole,
                cells: Int,
                basis: ThroBasis = .exact,
                ink: Color,
                markInk: Color = ThroColor.colorMarkOnBoard) {
        self.text = text
        self.role = role
        self.cells = max(1, cells)
        self.basis = basis
        self.ink = ink
        self.markInk = markInk
    }

    /// A cell is 0.540 of the resolved point size. Measured off the condensed sport face's digit
    /// advance, not chosen: at 96 pt a cell is 51.8 pt and three of them are 155.5 pt, which is what
    /// makes two three-digit registers side by side an arithmetic question rather than a hope.
    public static let cellRatio: CGFloat = 0.540

    /// The width of a register of `cells` cells at `role`. A caller sizing a two-column head needs
    /// this before it lays anything out, and it must not have to render a figure to find out.
    public static func width(cells: Int, role: ThroTypeRole) -> CGFloat {
        CGFloat(max(1, cells)) * (ThroFigure.cellRatio * ThroFont.scaled(role.size, relativeTo: role.relativeTo)).rounded()
    }

    /// The cells, right-aligned, with the leading ones empty. `nil` is an empty cell and is drawn as
    /// nothing at all: a leading zero states a digit the player does not have.
    static func register(_ text: String, cells: Int) -> [Character?] {
        let characters = Array(text)
        let n = max(1, cells)
        // A figure longer than its register keeps its LAST n characters: an overflowing score is a
        // bug, and showing its tail is the reading that makes the bug visible rather than the one
        // that hides it behind an ellipsis.
        let kept = characters.count > n ? Array(characters.suffix(n)) : characters
        return Array(repeating: nil, count: n - kept.count) + kept.map { Optional($0) }
    }

    private var cellWidth: CGFloat {
        (ThroFigure.cellRatio * ThroFont.scaled(role.size, relativeTo: role.relativeTo)).rounded()
    }

    public var body: some View {
        let box = ThroTypography.capBox(role)
        let trim = ThroTypography.capTrim(role)
        let width = cellWidth
        return VStack(spacing: ThroSpacing.spacing1) {
            HStack(spacing: 0) {
                ForEach(Array(ThroFigure.register(text, cells: cells).enumerated()), id: \.offset) { cell in
                    Text(cell.element.map { String($0) } ?? "")
                        // Tracking is forced to zero inside a register: `scoreHero` carries −0.03 em
                        // and at 96 pt that is −2.88 pt per glyph, which pulls every digit off its
                        // own cell and tears the grid apart. `boardHero` is the role that already
                        // has it at zero; this holds the line for any role a caller passes.
                        .thro(role.tracking(em: 0))
                        .foregroundStyle(ink)
                        .fixedSize()
                        .frame(width: width, height: box, alignment: .bottom)
                        .offset(y: trim)
                        .clipped(antialiased: true)
                        // Per-cell identity. Without it SwiftUI treats the row as one changing view
                        // and there is no "the digit that changed" for anything to animate.
                        .id(cell.offset)
                }
            }
            .frame(height: box, alignment: .bottom)
            if basis != .absent {
                BasisRule(basis, figureWidth: width * CGFloat(cells), capHeight: box,
                          seedAngle: Double(cells) * 29)
                    .fill(basis == .struck ? ThroColor.colorBoardField : markInk)
                    .frame(height: BasisRule.height(basis))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThroFigure.spoken(text, basis: basis))
    }

    /// What a screen reader is told the figure is, basis included.
    ///
    /// The basis is spoken because it is the part a sighted reader gets from the shape under the
    /// number, and a listener who is told "58.4" has been told a fact when the app knows an
    /// interval. `exact` adds nothing, so the common case is not narrated.
    static func spoken(_ text: String, basis: ThroBasis) -> String {
        let value = text == "—" ? "not available" : text
        return basis.spoken.isEmpty ? value : "\(value), \(basis.spoken)"
    }
}
