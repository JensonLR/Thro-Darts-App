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
