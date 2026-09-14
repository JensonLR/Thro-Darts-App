import Combine
import Foundation
import XCTest
@testable import ThroApp
@testable import ThroNet

/// The account store's states, reached with fake ceremonies and a scripted server: no device,
/// no dialog, and every sentence the screen can show asserted as text.
@MainActor
final class AccountTests: XCTestCase {

    final class Ceremonies: SignInServices, @unchecked Sendable {
        var apple: String?? = .some("apple.token")
        var passkeyRegistration: PasskeyRegistration?? = .some(PasskeyRegistration(credentialID: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3])))
        var passkeyAssertion: PasskeyAssertion?? = .some(PasskeyAssertion(credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]), signature: Data([4])))
        func appleIdentityToken(nonce: String) async throws -> String? { try unwrap(apple) }
        func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String? { "google.token" }
        func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration? { try unwrap(passkeyRegistration) }
        func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion? { try unwrap(passkeyAssertion) }
        private func unwrap<T>(_ v: T??) throws -> T? { if let v { return v } else { throw APIError.unreachable("ceremony broke") } }
    }

    private let config = ServerConfiguration(baseURL: URL(string: "https://api.example")!, googleClientID: nil)
    private let sessionJSON = #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"accessToken":"acc","refreshToken":"ref","accessExpiresAt":"2026-09-12T10:15:00Z","created":true}"#
    private let meJSON = #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"displayName":"Player","named":false,"ageBand":"unknown","credentials":1}"#

    private func store(_ answers: [(Int, String)], services: Ceremonies = Ceremonies(), session: Session? = nil) -> (AccountStore, NetTests.Script) {
        let script = NetTests.Script(answers)
        let api = ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(session), transport: script)
        return (AccountStore(api: api, configuration: config, services: services, transport: script), script)
    }

    func testStartWithNoSessionIsSignedOutAndAsksTheServerNothing() async {
        let (account, script) = store([])
        await account.start()
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertTrue(script.seen.isEmpty)
    }

    func testSignInWithAppleReachesTheProfile() async {
        let (account, script) = store([(200, sessionJSON), (200, meJSON)])
        await account.signInWithApple()
        guard case .signedIn(let p) = account.state else { return XCTFail("expected signedIn, got \(account.state)") }
        XCTAssertFalse(p.named)
        XCTAssertEqual(p.credentials, 1)
        XCTAssertEqual(script.seen.map { $0.url!.path }, ["/v1/auth/apple", "/v1/me"])
    }

    func testACancelledCeremonyPutsTheScreenBackWhereItWas() async {
        let ceremonies = Ceremonies(); ceremonies.apple = .some(nil)
        let (account, script) = store([], services: ceremonies)
        await account.signInWithApple()
        XCTAssertEqual(account.state, .signedOut, "a cancel is not a failure")
        XCTAssertTrue(script.seen.isEmpty, "nothing was sent for a cancel")
    }

    func testAServerRefusalIsWordsAndTheAccountIsUnchanged() async {
        let (account, _) = store([(401, #"{"error":"the token does not verify: audience mismatch"}"#)])
        await account.signInWithApple()
        XCTAssertEqual(account.state, .failed("the token does not verify: audience mismatch", wasSignedIn: false))
        account.dismissFailure()
        XCTAssertEqual(account.state, .signedOut)
    }

    func testGoogleWithoutAClientIdSaysSoInsteadOfOpeningNothing() async {
        let (account, script) = store([])
        await account.signInWithGoogle()
        XCTAssertEqual(account.state, .failed("Sign in with Google is not set up in this build yet.", wasSignedIn: false))
        XCTAssertTrue(script.seen.isEmpty)
    }

    func testAPasskeyAddsToASignedInAccountAndSignsInWhenOut() async {
        let options = #"{"challengeId":"c1","publicKey":{"rp":{"id":"api.example","name":"THRØ"},"user":{"id":"AQID","name":"Player","displayName":"Player"},"challenge":"AAAA","pubKeyCredParams":[],"excludeCredentials":[],"authenticatorSelection":{},"attestation":"none","timeout":1}}"#
        let held = Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)
        let (signedIn, script) = store([(200, meJSON), (200, options), (200, sessionJSON), (200, meJSON.replacingOccurrences(of: "\"credentials\":1", with: "\"credentials\":2"))], session: held)
        await signedIn.start()
        await signedIn.usePasskey()
        guard case .signedIn(let p) = signedIn.state else { return XCTFail("expected signedIn, got \(signedIn.state)") }
        XCTAssertEqual(p.credentials, 2, "a second way in")
        XCTAssertEqual(script.seen.map { $0.url!.path }, ["/v1/me", "/v1/auth/passkey/register/options", "/v1/auth/passkey/register", "/v1/me"])
        XCTAssertNotNil(script.seen[1].value(forHTTPHeaderField: "Authorization"), "the options are asked for as the signed-in account, so the passkey joins it")

        let request = #"{"challengeId":"c2","publicKey":{"challenge":"AAAA","rpId":"api.example","userVerification":"required","timeout":1}}"#
        let (out, script2) = store([(200, request), (200, sessionJSON), (200, meJSON)])
        await out.usePasskey()
        guard case .signedIn = out.state else { return XCTFail("expected signedIn, got \(out.state)") }
        XCTAssertEqual(script2.seen.map { $0.url!.path }, ["/v1/auth/passkey/options", "/v1/auth/passkey", "/v1/me"])
    }

    func testSignOutForgetsTheSessionEvenIfTheServerIsUnreachable() async {
        let held = Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)
        let (account, _) = store([(200, meJSON)], session: held)
        await account.start()
        await account.signOut()
        XCTAssertEqual(account.state, .signedOut)
        let still = await account.api.isSignedIn
        XCTAssertFalse(still)
    }

    // MARK: - who is signed in, at once
    //
    // The founder, on a cold start: "Loaded me to home screen and when i checked profile tab it said
    // checking." Knowing who was signed in took a round trip to a server that sleeps.

    private let held = Session(accountId: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!, playerId: nil,
                               accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)

    private func known(_ name: String = "Jenson R.") -> Profile {
        Profile(accountId: held.accountId, playerId: nil, displayName: name, named: true, ageBand: "adult", credentials: 2)
    }

    private func json(_ profile: Profile) -> String {
        String(decoding: try! JSONEncoder().encode(profile), as: UTF8.self)
    }

    private func store(_ answers: [(Int, String)], session: Session?, cache: ProfileCache) -> (AccountStore, NetTests.Script) {
        let script = NetTests.Script(answers)
        let api = ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(session), transport: script)
        return (AccountStore(api: api, configuration: config, services: Ceremonies(), transport: script, cache: cache), script)
    }

    func testAPhoneThatKnowsWhoIsSignedInSaysSoWithNoNetwork() async {
        // Offline in a pub, the old store would have said "Checking" for as long as the signal
        // stayed away. The script answers nothing: every request fails as unreachable.
        let (account, script) = store([], session: held, cache: MemoryProfileCache(known()))
        await account.start()
        XCTAssertEqual(account.state, .signedIn(known()), "who they are, from this phone")
        XCTAssertTrue(account.settled)
        XCTAssertTrue(account.holdsSession)
        XCTAssertEqual(script.seen.map { $0.url!.path }, ["/v1/me"], "and THRØ was still asked")
    }

    func testTheServerCorrectsWhatThePhoneRemembered() async {
        let cache = MemoryProfileCache(known())
        let (account, _) = store([(200, json(known("J. Raper")))], session: held, cache: cache)
        await account.start()
        XCTAssertEqual(account.profile?.displayName, "J. Raper")
        XCTAssertEqual(cache.load()?.displayName, "J. Raper", "and the phone remembers the new one")
    }

    func testASessionTHRONoLongerHonoursSignsThePhoneOutAndForgetsThePerson() async {
        let cache = MemoryProfileCache(known())
        // The access token is refused, and so is the refresh: the session family is gone.
        let (account, _) = store([(401, #"{"error":"no principal"}"#), (401, #"{"error":"refresh refused"}"#)],
                                 session: held, cache: cache)
        await account.start()
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertFalse(account.holdsSession)
        XCTAssertNil(cache.load(), "nothing about them is kept once the session is gone")
    }

    func testAHeldSessionWithNothingRememberedIsStillHeldWhenTHROCannotBeReached() async {
        // The first launch of this build: a session, no profile yet, and no signal. Saying signed out
        // would be untrue, and would put the sign-in board in front of somebody who is signed in.
        let (account, _) = store([], session: held, cache: MemoryProfileCache())
        await account.start()
        guard case .failed(_, let stillHeld, _) = account.state else { return XCTFail("\(account.state)") }
        XCTAssertTrue(stillHeld)
        XCTAssertTrue(account.holdsSession)
        XCTAssertTrue(account.settled, "the opening does not wait forever")
    }

    func testAProfileRememberedForSomebodyElseIsNotShown() async {
        let stranger = Profile(accountId: UUID(), playerId: nil, displayName: "Somebody Else", named: true,
                               ageBand: "adult", credentials: 1)
        let (account, _) = store([], session: held, cache: MemoryProfileCache(stranger))
        await account.start()
        XCTAssertNil(account.profile, "a shared phone never shows the last person's name for this one")
    }

    func testSigningInIsRememberedForTheNextLaunch() async {
        let cache = MemoryProfileCache()
        let (account, _) = store([(200, sessionJSON), (200, meJSON)], session: nil, cache: cache)
        await account.signInWithApple()
        XCTAssertEqual(cache.load()?.accountId, held.accountId)
        XCTAssertTrue(account.holdsSession)
    }

    // MARK: - the page stays while the account changes
    //
    // "Delete account doesn't work." Every change set the store busy, which took the profile page —
    // and the delete screen on it — off the screen; an erasure that failed told a screen that no
    // longer existed.

    private final class Seen { var states: [AccountStore.State] = [] }

    /// Every state the store passes through while `body` runs.
    private func states(of account: AccountStore, during body: () async -> Void) async -> [AccountStore.State] {
        let seen = Seen()
        let watch = account.$state.sink { seen.states.append($0) }
        await body()
        watch.cancel()
        return seen.states
    }

    private func allSignedIn(_ states: [AccountStore.State]) -> Bool {
        states.allSatisfy { if case .signedIn = $0 { return true } else { return false } }
    }

    func testSavingANameNeverTakesTheProfileOffTheScreen() async {
        let (account, _) = store([(200, json(known())), (200, json(known("Jenson Raper")))],
                                 session: held, cache: MemoryProfileCache(known()))
        await account.start()
        let seen = await states(of: account) { await account.setDisplayName("Jenson Raper") }
        XCTAssertTrue(allSignedIn(seen), "signed in the whole way through: \(seen)")
        XCTAssertEqual(account.profile?.displayName, "Jenson Raper")
        XCTAssertNil(account.working)
    }

    func testANameThatWouldNotSaveIsSaidOnThePageItWasTypedOn() async {
        let (account, _) = store([(200, json(known())), (503, #"{"error":"THRØ could not save that just now."}"#)],
                                 session: held, cache: MemoryProfileCache(known()))
        await account.start()
        await account.setDisplayName("Jenson Raper")
        XCTAssertEqual(account.state, .signedIn(known()), "still signed in, still the old name")
        XCTAssertEqual(account.problem, "THRØ could not save that just now.")
        account.dismissProblem()
        XCTAssertNil(account.problem)
    }

    func testAnErasureThatFailsLeavesThePersonSignedInAndSaysWhy() async {
        let (account, _) = store([(200, json(known())), (500, #"{"error":"the account could not be erased"}"#)],
                                 session: held, cache: MemoryProfileCache(known()))
        await account.start()
        var outcome: AccountStore.Erased?
        let seen = await states(of: account) { outcome = await account.eraseAccount() }
        XCTAssertEqual(outcome, .failed("the account could not be erased"))
        XCTAssertTrue(allSignedIn(seen), "the delete screen stayed to say so: \(seen)")
        XCTAssertTrue(account.holdsSession)
        XCTAssertNil(account.working)
    }

    func testAnErasureThatWorksSaysWhatWentAndForgetsThePerson() async {
        let cache = MemoryProfileCache(known())
        let erased = #"{"erased":true,"credentials":2,"sessions":3,"devices":0,"friendships":0,"claims":1,"consents":1}"#
        let (account, _) = store([(200, json(known())), (200, erased)], session: held, cache: cache)
        await account.start()
        let outcome = await account.eraseAccount()
        guard case .erased(let gone) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(gone.credentials, 2)
        XCTAssertEqual(gone.sessions, 3)
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertFalse(account.holdsSession)
        XCTAssertNil(cache.load(), "the phone keeps nothing about the person it erased")
        let still = await account.api.isSignedIn
        XCTAssertFalse(still)
    }

    func testTheDeviceIdReusesTheJournalsWhenItIsAUUID() {
        let defaults = UserDefaults(suiteName: "AccountTests.\(UUID().uuidString)")!
        let j = UUID().uuidString
        XCTAssertEqual(ThroServer.deviceId(journalDeviceId: j, defaults: defaults).uuidString, j)
        let minted = ThroServer.deviceId(journalDeviceId: "not-a-uuid", defaults: defaults)
        XCTAssertEqual(ThroServer.deviceId(journalDeviceId: nil, defaults: defaults), minted, "a minted id is kept")
    }
}
