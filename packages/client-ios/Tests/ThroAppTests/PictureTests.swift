import Foundation
import XCTest
import ThroJournal
@testable import ThroApp

/// Who may have a picture, and who is told why not (PD-014).
///
/// **These exist because the picker was the only thing missing, and it was missing everywhere.**
/// `ClubStore.setAvatar` was public and tested and had no caller; `EditClubScreen` was written and
/// had no route, so no club on a phone could be renamed, recoloured, badged or deleted.
///
/// These tests would not have caught that, and neither would any test here: nothing in this
/// repository constructs a screen. That is what `tools/check_screens_reachable.py` is for. What
/// these hold is the rule the picker obeys, which is a different question and also worth holding.
final class PictureTests: XCTestCase {

    private func member(_ band: AgeBand, role: OrgRole = .member) -> ClubMember {
        ClubMember(id: "m", name: "Sam Rowe", role: role, ageBand: band, joined: "2024")
    }

    private func club(role: OrgRole?) -> Club {
        Club(id: "c", name: "The Feathers A", kind: .club, meta: "Crediton", yourRole: role,
             members: [member(.adult)])
    }

    /// **The refusal is the store's rule, not a second copy of it.**
    ///
    /// A screen that decided for itself who may have a picture would be a screen that can drift into
    /// offering something `ClubBook.setAvatar` throws on. This asserts the two agree on every band
    /// there is, so adding a band cannot leave the picker guessing.
    func testTheRefusalFollowsTheStoresRuleRatherThanRestatingIt() {
        for band in [AgeBand.adult, .minor, .unknown] {
            let allowed = ImagePolicy.mayHavePicture(ageBand: band.rawValue)
            XCTAssertEqual(PicturePolicy.refusal(for: band) == nil, allowed,
                           "\(band.rawValue): the picker and the store disagree about who may have one")
        }
    }

    /// Only an adult. Unknown is refused for the reason `packages/authz` gives: what is not known is
    /// whether this is a child.
    func testOnlyAnAdultMayHaveOne() {
        XCTAssertNil(PicturePolicy.refusal(for: .adult))
        XCTAssertNotNil(PicturePolicy.refusal(for: .minor))
        XCTAssertNotNil(PicturePolicy.refusal(for: .unknown))
    }

    /// The two refusals are different sentences, because they are different facts and one of them is
    /// actionable. "Not allowed" for both would tell an admin nothing about which is which.
    func testTheTwoRefusalsSayWhichCaseTheyAre() {
        let minor = PicturePolicy.refusal(for: .minor) ?? ""
        let unknown = PicturePolicy.refusal(for: .unknown) ?? ""
        XCTAssertNotEqual(minor, unknown)
        XCTAssertTrue(minor.contains("under 18"), "a minor's refusal names the reason")
        XCTAssertTrue(minor.contains("not a setting"), "and says it is not something to turn on")
        XCTAssertTrue(unknown.contains("age has been recorded"),
                      "an unknown age's refusal says what is missing")
        // Both name what would change the answer, because for one of them nothing does.
        XCTAssertTrue(unknown.contains("adult"))
    }

    /// The unknown-age wording is shown in two places — a club member whose age was never given, and
    /// a person on this phone, for whom there is nowhere to give one — so it must not say "member".
    func testTheUnknownRefusalReadsForAPersonAsWellAsAMember() {
        let unknown = PicturePolicy.refusal(for: .unknown) ?? ""
        XCTAssertFalse(unknown.contains("member"),
                       "PersonScreen shows this too, and a person on this phone is not a member")
    }

    /// PD-023: the refusal for an unrecorded age says **where a picture does come from**, rather
    /// than leaving it open. The person in the photograph answers for their own age, which arrives
    /// with an account — and until then the page says which rule and why, not just "no".
    func testTheUnrecordedAgeRefusalSaysWhereAPictureComesFrom() {
        let unknown = PicturePolicy.refusal(for: .unknown) ?? ""
        XCTAssertTrue(unknown.contains("arrives with an account"))
        XCTAssertTrue(unknown.contains("answers for their own age"),
                      "which is the whole of the decision: not whoever is holding the phone")
        // A minor's refusal must NOT say that, because for them nothing changes with an account.
        XCTAssertFalse((PicturePolicy.refusal(for: .minor) ?? "").contains("account"))
    }

    /// The top bar's actions: what is offered, in what order, and what is left out.
    ///
    /// **The bar itself is the thing that was broken**, and no test here can see a layout — that is
    /// `tools/check_screen_bars.py`'s job. What is testable is that the bar is asked for the right
    /// actions: an action nobody may take is absent rather than present and refusing, which is the
    /// rule every other control on these screens follows.
    func testTheTopBarOffersOnlyTheActionsTheViewerMayTake() {
        XCTAssertEqual(ClubScreen.actions(edit: nil, announce: nil).map(\.label), [])
        XCTAssertEqual(ClubScreen.actions(edit: {}, announce: nil).map(\.label), ["Edit"])
        XCTAssertEqual(ClubScreen.actions(edit: nil, announce: {}).map(\.label), ["Announce"])
        XCTAssertEqual(ClubScreen.actions(edit: {}, announce: {}).map(\.label), ["Edit", "Announce"],
                       "and in that order, because Announce is the one furthest from the back button")
    }

    /// Renaming, recolouring, badging and deleting a club are an admin's. An official runs fixtures
    /// and announcements; what the club is *called* is not theirs to change.
    func testOnlyAnAdminMayEditAClubsIdentity() {
        XCTAssertTrue(club(role: .admin).mayEditIdentity)
        XCTAssertFalse(club(role: .official).mayEditIdentity)
        XCTAssertFalse(club(role: .member).mayEditIdentity)
        XCTAssertFalse(club(role: nil).mayEditIdentity, "a stranger cannot edit a club")
        // It is the same answer as the roster's, and deliberately a separate property: the day one
        // moves, the other must move on purpose rather than by sharing a name.
        for role in [OrgRole.admin, .official, .member] {
            XCTAssertEqual(club(role: role).mayEditIdentity, club(role: role).mayManageMembers)
        }
    }
}
