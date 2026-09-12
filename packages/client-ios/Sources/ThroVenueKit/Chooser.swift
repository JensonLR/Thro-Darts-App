import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The one screen in a venue that anybody operates (PD-079).
//
// **Once, with a remote, by whoever puts the screen up.** After that the wall never asks anything again —
// which is the requirement, because the person who switches the TV on at opening time is not the person who
// set it up and will not be setting it up again.
//
// **One step, not two.** A league is picked and the season comes with it: `PublicLeague.shownSeason` is the
// one running today, else the newest, and that rule already exists and is already what the phone shows. A
// second screen asking which season would be asking a landlord a question they have no way to get wrong and
// no reason to be asked.

/// Which league this screen is for.
public struct ThroVenueChooser: View {
    @StateObject private var leagues: ThroVenueLeagues
    private let chose: (UUID) -> Void

    public init(api: ThroAPI, chose: @escaping (UUID) -> Void) {
        _leagues = StateObject(wrappedValue: ThroVenueLeagues(api: api))
        self.chose = chose
    }

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.16), grainSeed: 0xC0DE) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing6) {
                Text("THRØ")
                    .thro(ThroTypography.display)
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                Text("Which league is this screen for?")
                    .thro(ThroTypography.heading2)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.85))
                Text("Pick it once. The screen shows that league's table, fixtures and results from then on, "
                     + "and never asks again.")
                    .thro(ThroTypography.bodyLarge)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.6))
                    .frame(maxWidth: 1100, alignment: .leading)

                if let trouble = leagues.trouble {
                    Text(trouble)
                        .thro(ThroTypography.heading3)
                        .foregroundStyle(ThroColor.throBronzeOnink)
                } else if !leagues.read {
                    Text("Reading…")
                        .thro(ThroTypography.heading3)
                        .foregroundStyle(ThroColor.throChalk.opacity(0.6))
                } else if choosable.isEmpty {
                    // A league with no published season cannot fill a screen, and saying "none" with no
                    // reason would send somebody looking for a fault in the television.
                    Text("No league here has published a season yet. There is nothing this screen could show.")
                        .thro(ThroTypography.heading3)
                        .foregroundStyle(ThroColor.throChalk.opacity(0.7))
                        .frame(maxWidth: 1100, alignment: .leading)
                }

                ScrollView {
                    // Capped, and not the width of a television. A row of two words with two metres of
                    // green after it reads as a mistake; the eye should not have to travel the whole
                    // wall to find the season label at the end of a league's name.
                    LazyVStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                        ForEach(choosable) { league in
                            Button {
                                if let season = league.shownSeason { chose(season.leagueSeasonId) }
                            } label: {
                                // The whole row, not just the ink. A remote does not miss, but this module
                                // builds for a phone too and a finger landing beside a league's name should
                                // pick that league rather than nothing.
                                row(league).throRowTapTarget()
                            }
                            .buttonStyle(ThroVenuePick())
                        }
                    }
                    .frame(maxWidth: 1200, alignment: .leading)
                    .padding(.vertical, ThroSpacing.spacing2)
                    .padding(.horizontal, ThroSpacing.spacing2)
                }
            }
            .padding(.horizontal, ThroSpacing.spaceSectionGap * 2)
            .padding(.vertical, ThroSpacing.spaceSectionGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await leagues.load() }
    }

    /// Only leagues that have something to show. Offering one that would open on an empty wall is offering
    /// somebody a way to get it wrong.
    private var choosable: [PublicLeague] {
        leagues.leagues.filter { $0.shownSeason != nil }
    }

    private func row(_ league: PublicLeague) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing4) {
            Text(league.name)
                .thro(ThroTypography.heading2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: ThroSpacing.spacing4)
            if let locality = league.locality {
                Text(locality)
                    .thro(ThroTypography.bodyLarge)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            if let season = league.shownSeason {
                Text(season.label)
                    .thro(ThroTypography.metadata)
                    .opacity(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row that shows where the remote is pointing.
///
/// **Focus, not a press.** A finger tells a phone where it is by touching; a remote tells a TV by moving a
/// highlight, and a row that looked the same focused as unfocused would leave somebody pressing select at
/// random. This is the one control in THRØ whose whole job is to answer *which one is this*, so it says it
/// with the chalk the rest of the board is drawn in rather than the system's grey slab.
struct ThroVenuePick: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Named `Lit` and not `Body`: `ButtonStyle` has an associated type called Body, and a nested
        // struct of that name silently becomes the protocol's witness instead of a view.
        Lit(configuration: configuration)
    }

    private struct Lit: View {
        let configuration: ThroVenuePick.Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            let lit = focused || configuration.isPressed
            configuration.label
                .foregroundStyle(lit ? ThroColor.colorTextOnBoard : ThroColor.throChalk.opacity(0.72))
                .padding(.horizontal, ThroSpacing.spacing6)
                .padding(.vertical, ThroSpacing.spacing4)
                .background {
                    RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
                        .fill(ThroColor.throChalk.opacity(lit ? 0.14 : 0.04))
                }
                .overlay {
                    // `ChalkBox`, not `ChalkRule`: a rule is a single horizontal line, and the first
                    // build of this drew one straight through every league's name. Looked at once and
                    // obvious; invisible in the code, where both are "a chalk shape".
                    ChalkBox(weight: lit ? 4 : 2, seedAngle: 11)
                        .fill(ThroColor.throChalk.opacity(lit ? 0.85 : 0.22))
                }
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.15), value: lit)
        }
    }
}
