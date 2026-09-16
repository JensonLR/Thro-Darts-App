import XCTest
@testable import ThroApp
import ThroJournal
import ThroNet

/// Your ACCOUNT's profile — the name, the picture and the way out of THRØ.
///
/// Named apart from `ProfileTests`, which is about a club member's page: two different profiles,
/// two different files, and this one nearly cost the other eleven tests by sharing its name.
final class AccountProfileTests: XCTestCase {

    // MARK: - a picture is an adult's

    func testAPictureIsAnAdultsAndTheTwoRefusalsAreDifferentFacts() {
        // The same rule as every other picture in THRØ (PD-014), reached through the same function
        // rather than copied — a second copy is a second thing to forget to change.
        XCTAssertNil(AccountPicture.refusal(ageBand: "adult"))
        XCTAssertEqual(AccountPicture.refusal(ageBand: "adult"), ImagePolicy.mayHavePicture(ageBand: "adult") ? nil : "x")

        let minor = AccountPicture.refusal(ageBand: "minor")
        let unknown = AccountPicture.refusal(ageBand: "unknown")
        XCTAssertNotNil(minor); XCTAssertNotNil(unknown)
        // Two different facts, so two different sentences: one of them the person can change.
        XCTAssertNotEqual(minor, unknown)
        XCTAssertTrue(unknown!.contains("18 or over"), "it says what to do: \(unknown!)")
        XCTAssertFalse(minor!.contains("18 or over"), "and a child is not told to declare themselves an adult")
    }

    func testTheKeyIsPerAccountSoASharedPhoneNeverInheritsAFace() {
        let a = UUID(), b = UUID()
        XCTAssertNotEqual(AccountPicture.key(a), AccountPicture.key(b))
        XCTAssertTrue(AccountPicture.key(a).contains(a.uuidString))
    }

    // MARK: - the name, where it is read

    @MainActor func testTheMarkFallsBackToInitialsTheSameWayEverythingElseDoes() {
        func initials(_ name: String) -> String {
            YourProfileScreen(account: store(), profile: profile(name: name), accountId: UUID(),
                              images: nil, picture: { _ in nil }, onBack: {}).initials
        }
        XCTAssertEqual(initials("Jenson Raper"), "JR")
        XCTAssertEqual(initials("Jenson R."), "JR")
        XCTAssertEqual(initials("Prince"), "P")
        XCTAssertEqual(initials("  "), "?", "a mark rather than an empty circle")
        XCTAssertEqual(initials("ann marie o'brien"), "AM")
    }

    func testTheNoteUnderTheNameTellsTheTwoStatesApart() {
        // Somebody who has not named themselves needs an instruction; somebody who has needs to
        // know who sees it. The same sentence for both would be useless to one of them.
        let unnamed = YourProfileScreen.nameNote(named: false)
        let named = YourProfileScreen.nameNote(named: true)
        XCTAssertNotEqual(unnamed, named)
        XCTAssertTrue(unnamed.lowercased().contains("tap"), unnamed)
        XCTAssertTrue(named.lowercased().contains("teams and leagues"), named)
    }

    // MARK: - the way out

    func testTheDeleteScreenNamesEverythingTheServerActuallyDestroys() {
        let goes = DeleteAccountScreen.goes.joined(separator: " ").lowercased()
        // Each of these is a step in V031's `identity.erase_account`. If a step is added there and
        // not said here, the screen is lying by omission about what a person is agreeing to.
        for thing in ["name", "apple", "google", "passkey", "session", "friend", "player record"] {
            XCTAssertTrue(goes.contains(thing), "the list does not mention \(thing)")
        }
    }

    func testItSaysWhatStaysAndWhyRatherThanClaimingEverythingGoes() {
        let stays = DeleteAccountScreen.stays.joined(separator: " ").lowercased()
        // A match is two people's record. "Everything will be deleted" would be false, and saying
        // nothing while keeping it would be worse.
        XCTAssertTrue(stays.contains("matches you have played"))
        XCTAssertTrue(stays.contains("no name on it"), "and it says the kept record names nobody")
        XCTAssertTrue(stays.contains("this phone"), "the local matches are a separate thing and are named")
        XCTAssertFalse(DeleteAccountScreen.goes.joined().lowercased().contains("everything"),
                       "nothing on the list overclaims")
    }

    func testTheFinalityIsStatedBeforeTheSecondAskAndAgainInIt() {
        // Signing in again is the thing people assume will bring it back, so it is said outright.
        XCTAssertTrue(DeleteAccountScreen.finality.contains("cannot be undone"))
        XCTAssertTrue(DeleteAccountScreen.finality.lowercased().contains("brand new account"))
    }

    // MARK: - the ways in (PD-102)

    func testTheWaysInAreNamedAndOnlyWhatIsMissingIsOffered() throws {
        let json = #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"displayName":"Jenson","named":true,"ageBand":"adult","credentials":3,"ways":["passkey","apple","google"]}"#
        let all = WaysIn(profile: try JSONDecoder().decode(Profile.self, from: Data(json.utf8)))
        XCTAssertEqual(all.held, [.apple, .google, .passkey], "every way held, by name, in one order")
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.offers(googleConfigured: true), [.passkey], "Apple and Google are set up; only another passkey is offered")

        let appleOnly = WaysIn(profile: Profile(accountId: UUID(), playerId: nil, displayName: "Sam", named: true, ageBand: "adult",
                                                credentials: 1, ways: ["apple"]))
        XCTAssertEqual(appleOnly.offers(googleConfigured: true), [.google, .passkey], "Apple is not offered twice")
        XCTAssertEqual(appleOnly.offers(googleConfigured: false), [.passkey], "and Google is not offered by a build without it")

        // A profile from an older server, or cached by an older build, names no ways: everything is offered, as before.
        let older = WaysIn(profile: profile(name: "Sam"))
        XCTAssertEqual(older.held, [])
        XCTAssertEqual(older.offers(googleConfigured: true), [.apple, .google, .passkey])
        XCTAssertEqual(older.count, 1)
    }

    // MARK: - reaching an organiser (PD-104)

    func testTheContactEmailFieldIsOfferedOnlyToWhoeverTheServerSaysMayGiveOne() throws {
        let organiser = #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"displayName":"Lee","named":true,"ageBand":"adult","credentials":1,"organiser":true,"contactEmail":"lee@example.org"}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(organiser.utf8))
        XCTAssertTrue(p.mayGiveContactEmail)
        XCTAssertEqual(p.contactEmail, "lee@example.org")
        let player = #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000002","playerId":null,"displayName":"Sam","named":true,"ageBand":"adult","credentials":1,"organiser":false,"contactEmail":null}"#
        XCTAssertFalse(try JSONDecoder().decode(Profile.self, from: Data(player.utf8)).mayGiveContactEmail, "an adult who runs nothing is not offered the field")
        XCTAssertFalse(profile(name: "Sam").mayGiveContactEmail, "and a profile from an older server, or an older cache, is not either")
    }

    // MARK: - the rating (PD-105)

    func testARatingReadsAsARangeANumberWithItsMarginOrAnHonestDash() throws {
        let provisional = #"{"playerId":"aaaaaaaa-0000-0000-0000-000000000001","model":"glicko2","version":"1.0.0","stage":"provisional","display":{"kind":"provisional","low":1380,"high":1620,"matches":1,"comparedAcross":2},"asOf":{"commit":1,"seq":5},"lines":[{"matchId":"bbbbbbbb-0000-0000-0000-000000000001","outcome":"won","delta":112,"opponent":null,"opponentRating":1500,"expected":0.50,"words":"Beat an opponent, rated about 1500. An even contest."}]}"#
        let p = try JSONDecoder().decode(RatingAnswer.self, from: Data(provisional.utf8))
        XCTAssertEqual(p.figure, "1380–1620", "a range, never a bare number, while provisional")
        XCTAssertTrue(p.isProvisional)
        XCTAssertEqual(p.lines.first?.words, "Beat an opponent, rated about 1500. An even contest.")
        XCTAssertNil(p.lines.first?.opponent, "an opponent THRØ may not name is not named")
        let established = #"{"playerId":"aaaaaaaa-0000-0000-0000-000000000001","model":"glicko2","version":"1.0.0","stage":"provisional","display":{"kind":"established","value":1612,"plusMinus":180,"matches":15,"comparedAcross":6},"asOf":{"commit":1,"seq":5},"lines":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(RatingAnswer.self, from: Data(established.utf8)).figure, "1612 ± 180")
        let unrated = #"{"playerId":"aaaaaaaa-0000-0000-0000-000000000001","model":"glicko2","version":"1.0.0","stage":"provisional","display":{"kind":"unrated","matches":0,"comparedAcross":0},"asOf":{"commit":0,"seq":0},"lines":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(RatingAnswer.self, from: Data(unrated.utf8)).figure, "—")
    }

    // MARK: - helpers

    private func profile(name: String) -> Profile {
        Profile(accountId: UUID(), playerId: UUID(), displayName: name, named: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                ageBand: "adult", credentials: 1)
    }

    @MainActor private func store() -> AccountStore {
        AccountStore(api: ThroAPI(configuration: ServerConfiguration(baseURL: URL(string: "https://example.invalid")!),
                                  deviceId: UUID(), store: NoSessionStore()),
                     configuration: ServerConfiguration(baseURL: URL(string: "https://example.invalid")!),
                     services: NoSignInServices())
    }
}

/// A session store that keeps nothing: these tests never sign in.
private struct NoSessionStore: SessionStore {
    func load() -> Session? { nil }
    func save(_ session: Session) {}
    func clear() {}
}

/// Ceremonies that are never run here.
private struct NoSignInServices: SignInServices {
    func appleIdentityToken(nonce: String) async throws -> String? { nil }
    func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String? { nil }
    func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration? { nil }
    func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion? { nil }
}
