import XCTest
@testable import ThroApp
import ThroNet

/// The You tab and a team on THRØ (PD-126). Signed in, with a side on THRØ, the tab said "None on this phone yet" and
/// offered to start one: true of the phone's own book, and the opposite of true about the person. It says their teams
/// now, the ones on THRØ first, and what it offers somebody with none depends on whether they are signed in.
final class YouTeamsTests: XCTestCase {

    func testSomebodySignedInIsOfferedATeamOnTHRO() {
        let words = YouScreen.noTeams(signedIn: true)
        XCTAssertEqual(words.text, "**No team yet.** Join one with your captain's code or start your own, and its fixtures come to you here.")
        XCTAssertEqual(words.button, "Join or start a team")
    }

    func testSomebodySignedOutIsOfferedTheBookOnThisPhoneAndToldThatIsWhatItIs() {
        let words = YouScreen.noTeams(signedIn: false)
        XCTAssertEqual(words.text, "**None yet.** Sign in to join your side on THRØ, or keep a team on this phone alone: roster, fixtures and results, without an account.")
        XCTAssertEqual(words.button, "Go to Discover")
    }

    func testATeamOnTHROSaysYourPartInItAndHowManyAreOnIt() {
        let team = TeamSummary(teamId: UUID(), name: "The Bell B", locality: "Stockton-on-Tees", role: "admin", members: 3)
        XCTAssertEqual(YouScreen.teamMeta(team), "On THRØ · Stockton-on-Tees · 3 members")
        let alone = TeamSummary(teamId: UUID(), name: "Solo", locality: nil, role: "player", members: 1)
        XCTAssertEqual(YouScreen.teamMeta(alone), "On THRØ · 1 member")
    }

    func testTheSectionIsNamedForWhatIsInIt() {
        XCTAssertEqual(YouScreen.teamsTitle(onThro: 1, kept: 0), "Your teams")
        XCTAssertEqual(YouScreen.teamsTitle(onThro: 0, kept: 2), "Teams kept on this phone")
        XCTAssertEqual(YouScreen.teamsTitle(onThro: 1, kept: 2), "Your teams")
    }
}
