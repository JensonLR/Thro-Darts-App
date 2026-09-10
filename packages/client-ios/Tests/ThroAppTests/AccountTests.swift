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

    func testTheDeviceIdReusesTheJournalsWhenItIsAUUID() {
        let defaults = UserDefaults(suiteName: "AccountTests.\(UUID().uuidString)")!
        let j = UUID().uuidString
        XCTAssertEqual(ThroServer.deviceId(journalDeviceId: j, defaults: defaults).uuidString, j)
        let minted = ThroServer.deviceId(journalDeviceId: "not-a-uuid", defaults: defaults)
        XCTAssertEqual(ThroServer.deviceId(journalDeviceId: nil, defaults: defaults), minted, "a minted id is kept")
    }
}
