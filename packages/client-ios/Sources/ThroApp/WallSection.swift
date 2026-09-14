import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens
import ThroVenueKit

// Putting a league on the pub telly, from the phone (PD-089).
//
// **There is deliberately no button that turns the television on**, and the reason is worth stating because
// somebody will look for one. **No iOS API can start screen mirroring** — only the person can, from Control
// Centre — and `AVRoutePickerView`, which looks exactly like the answer, is a *media* route picker for
// `AVPlayer` and does not mirror a screen at all. A control labelled "Cast to TV" that could not cast
// anything would be a promise the app cannot keep. So this screen does the two things it honestly can: it
// takes the choice of league, and it says the words that get somebody from here to a picture.
//
// It lives on **Live** rather than in Settings because it is a thing somebody does on a match night, in a
// room, with a telly in front of them — not a preference they set once and forget.

struct WallSection: View {
    @StateObject private var leagues: ThroVenueLeagues
    @State private var chosen: UUID?
    @State private var picking = false
    private let choice: ThroVenueChoice

    init(api: ThroAPI, choice: ThroVenueChoice = ThroVenueChoice()) {
        _leagues = StateObject(wrappedValue: ThroVenueLeagues(api: api))
        self.choice = choice
        _chosen = State(initialValue: choice.season)
    }

    /// A league with a published season. One without cannot fill a screen.
    private var choosable: [PublicLeague] { leagues.leagues.filter { $0.shownSeason != nil } }

    private var chosenLeague: PublicLeague? {
        chosen.flatMap { season in choosable.first { $0.shownSeason?.leagueSeasonId == season } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader("On the telly", meta: chosen == nil ? nil : "Set")

            if let league = chosenLeague {
                Note("**\(league.name) is on the screen** whenever this phone is mirroring, and its "
                     + "table, fixtures and games in play turn over by themselves. Score a match and the "
                     + "match takes the screen instead; finish it and the league comes back.")
            } else if chosen != nil {
                // A season id is held but its league is not in the list — it was chosen on this phone
                // before, and the league has since gone or is still loading. Say which rather than
                // showing a name THRØ cannot stand behind.
                Note("**A league is set for the screen.** THRØ cannot read its name just now, so it is "
                     + "not shown here rather than guessed.")
            } else {
                Note("**Put your league on the pub screen.** Pick it here, then mirror this phone to the "
                     + "television. No Apple TV needed: an HDMI adapter works and never drops out.")
            }

            ThroButton(chosen == nil ? "Put a league on the telly" : "Change the league",
                       variant: chosen == nil ? .primary : .secondary, size: .medium, icon: .radio) {
                picking = true
            }
            if chosen != nil {
                ThroTextButton("Take it off the telly", tone: .quiet) {
                    chosen = nil
                    choice.season = nil
                }
            }
            HowToMirror()
        }
        .task { if !leagues.read { await leagues.load() } }
        .sheet(isPresented: $picking) {
            WallLeaguePicker(leagues: choosable, reading: !leagues.read, trouble: leagues.trouble) { season in
                chosen = season
                choice.season = season
                picking = false
            } onCancel: { picking = false }
        }
    }
}

/// The steps, written for somebody standing in a pub rather than reading a manual.
private struct HowToMirror: View {
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            ThroTextButton(open ? "Hide how" : "How to get it on the screen", tone: .quiet) { open.toggle() }
            if open {
                // Cable first. AirPlay is listed second on purpose: pub guest Wi-Fi commonly isolates
                // clients from each other, which kills AirPlay discovery stone dead, and a landlord who
                // tries the wireless way first and fails concludes the app is broken.
                Note("**With a cable — the one that always works.** A Lightning or USB-C to HDMI adapter, "
                     + "£20 or so, into the television. It appears by itself; there is nothing to press.")
                Note("**Or over AirPlay.** Swipe down from the top right for Control Centre, tap Screen "
                     + "Mirroring, pick the Apple TV. If it does not appear, the pub's Wi-Fi is probably "
                     + "keeping devices apart from each other — use the cable.")
                Note("**Then leave the phone plugged in.** The screen stays on this app while it is "
                     + "mirroring, and a phone on 4% at nine o'clock is the whole evening's board gone.")
            }
        }
    }
}

/// The list of leagues, phone-shaped.
///
/// Not `ThroVenueChooser`: that is drawn at television size for somebody holding a remote six metres away,
/// and the same view on a phone would be enormous. The *rule* is shared — a league with no published
/// season is not offered — and only the drawing differs.
private struct WallLeaguePicker: View {
    let leagues: [PublicLeague]
    let reading: Bool
    let trouble: String?
    let chose: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TopBar("Which league?", eyebrow: "On the telly", onBack: onCancel)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    if let trouble {
                        Note(trouble)
                    } else if reading {
                        Note("Reading the leagues…")
                    } else if leagues.isEmpty {
                        // Saying "none" with no reason sends somebody looking for a fault in the app.
                        Note("**No league has published a season yet.** There is nothing a screen could "
                             + "show. This fills in as leagues publish.")
                    }
                    ForEach(leagues) { league in
                        if let season = league.shownSeason {
                            CardGroup {
                                CardRow(icon: .trophy, label: league.name, value: season.label) {
                                    chose(season.leagueSeasonId)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary)
    }
}
