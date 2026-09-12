import Foundation
import XCTest
@testable import ThroNet

/// The wire, driven by a scripted transport: what the client sends, what it does with a 401, what
/// it decodes, and the two encodings the server and the phone must agree on.
final class NetTests: XCTestCase {

    /// Answers in order; records every request it saw.
    final class Script: Transport, @unchecked Sendable {
        var answers: [(Int, String)]
        var seen: [URLRequest] = []
        init(_ answers: [(Int, String)]) { self.answers = answers }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            seen.append(request)
            guard !answers.isEmpty else { throw APIError.unreachable("script exhausted") }
            let (code, body) = answers.removeFirst()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }

    private let config = ServerConfiguration(baseURL: URL(string: "https://api.example")!, googleClientID: "12345-abc.apps.googleusercontent.com")
    private let device = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private func session(_ token: String = "acc-1", refresh: String = "ref-1") -> String {
        """
        {"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":"bbbbbbbb-0000-0000-0000-000000000001","accessToken":"\(token)","refreshToken":"\(refresh)","accessExpiresAt":"2026-09-12T10:15:00.123456Z","created":true}
        """
    }

    // MARK: - erasing an account (V031)

    func testErasingRefreshesAStaleTokenInsteadOfGivingUp() async throws {
        // **The defect this exists for.** The first version of `eraseAccount` called `send` with the
        // bearer directly instead of `authorised`, so it never refreshed. Access tokens are short:
        // deleting worked right after signing in and answered 401 an hour later, and the 401 was
        // read as "already gone" — which signed the phone out and left the account standing. The
        // founder's report was "doesn't work every time", which is exactly what that looks like.
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "stale",
                                               refreshToken: "ref-0", accessExpiresAt: .distantPast, created: false))
        let script = Script([(401, #"{"error":"expired"}"#),
                             (200, session("acc-2", refresh: "ref-2")),
                             (200, #"{"erased":true,"credentials":2,"sessions":1,"devices":1,"friendships":0,"claims":1,"consents":1}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let gone = try await api.eraseAccount()
        XCTAssertEqual(gone.credentials, 2)
        XCTAssertEqual(script.seen.map { $0.url!.path }, ["/v1/me", "/v1/auth/refresh", "/v1/me"],
                       "it refreshed and tried again rather than reporting a failure")
        XCTAssertEqual(script.seen.first?.httpMethod, "DELETE")
        // A bodyless DELETE was answered 411 by the deployed server, so a body goes with it.
        XCTAssertEqual(script.seen.first?.httpBody, Data("{}".utf8))
        XCTAssertNil(store.load(), "and the session is forgotten once the account really is gone")
    }

    func testAFailedErasureLeavesTheSessionAloneSoTheFailureCanBeSeen() async throws {
        // Signing out on any failure took the screen showing the error off the screen with it, so a
        // failure was indistinguishable from a success — with the account still there.
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc-1",
                                               refreshToken: "ref-1", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(411, #"{"error":"Content-Length is required"}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        do {
            _ = try await api.eraseAccount()
            XCTFail("a 411 is not a successful erasure")
        } catch {
            XCTAssertNotNil(store.load(), "still signed in, because the account is still there")
        }
    }

    func testSignInSendsTheDeviceAndKeepsTheSession() async throws {
        let script = Script([(200, session())])
        let store = MemorySessionStore()
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let s = try await api.signIn(.apple, idToken: "id.token")
        XCTAssertEqual(s.accessToken, "acc-1")
        XCTAssertEqual(store.load()?.refreshToken, "ref-1", "the session is kept for the next launch")
        let req = try XCTUnwrap(script.seen.first)
        XCTAssertEqual(req.url?.path, "/v1/auth/apple")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Thro-Device"), device.uuidString.lowercased())
        let body = try XCTUnwrap(req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(body["idToken"], "id.token")
        XCTAssertEqual(body["deviceId"], device.uuidString.lowercased())
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "a first sign-in carries no bearer")
    }

    func testAnAuthorisedCallRefreshesOnceOnA401AndRetries() async throws {
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "stale", refreshToken: "ref-0", accessExpiresAt: .distantPast, created: false))
        let script = Script([(401, #"{"error":"expired"}"#), (200, session("acc-2", refresh: "ref-2")),
                             (200, #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"displayName":"Sam","named":true,"ageBand":"adult","credentials":2}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let me = try await api.me()
        XCTAssertEqual(me.displayName, "Sam")
        XCTAssertEqual(me.credentials, 2)
        XCTAssertEqual(script.seen.map { $0.url!.path }, ["/v1/me", "/v1/auth/refresh", "/v1/me"])
        XCTAssertEqual(script.seen[2].value(forHTTPHeaderField: "Authorization"), "Bearer acc-2", "the retry carries the renewed token")
        XCTAssertEqual(store.load()?.refreshToken, "ref-2", "the rotated refresh token replaced the old one")
    }

    func testARefusedRefreshSignsOutRatherThanLooping() async throws {
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "stale", refreshToken: "reused", accessExpiresAt: .distantPast, created: false))
        let script = Script([(401, "{}"), (401, #"{"error":"unknown, expired, or reused"}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        do { _ = try await api.me(); XCTFail("should have thrown") } catch let e as APIError { XCTAssertEqual(e, .signedOut) }
        XCTAssertNil(store.load(), "a session the server no longer honours is not kept")
        XCTAssertEqual(script.seen.count, 2, "no third attempt")
        let signedOut = await api.isSignedIn
        XCTAssertFalse(signedOut)
    }

    func testAnErrorBodyBecomesWordsNotACode() {
        XCTAssertEqual(APIError.status(422, #"{"outcome":"refused","why":"you do not run this team"}"#).message, "you do not run this team")
        XCTAssertEqual(APIError.status(429, "").message, "Too many attempts. Wait a minute and try again.")
        XCTAssertEqual(APIError.status(500, "boom").message, "The server answered 500.")
    }

    func testInboxAndDiscoveryDecodeWhatTheServerSends() async throws {
        let inbox = #"{"sections":{"ACTION_REQUIRED":[{"taskId":"cccccccc-0000-0000-0000-000000000001","kind":"registration_required","reason":"Register Sam with the Teesside league","dueAt":"2026-09-20T00:00:00Z","state":"open"}],"COMPLETED":[]}}"#
        let cards = #"{"sections":{"ALL":[{"eventId":"dddddddd-0000-0000-0000-000000000001","name":"Stockton Saturday Open","tournament":null,"venue":"Riverside WMC","locality":"Stockton","startsAt":"2026-09-12T11:00:00Z","entriesCloseAt":null,"entrantKind":"player","access":"open","capacity":64,"spotsRemaining":63,"entered":false,"qualifies":true,"series":[],"reasons":["starts 2026-09-12","open entry","capacity 64"]}]}}"#
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: Script([(200, inbox), (200, cards)]))
        let tasks = try await api.inbox()
        XCTAssertEqual(tasks["ACTION_REQUIRED"]?.first?.reason, "Register Sam with the Teesside league")
        XCTAssertEqual(tasks["COMPLETED"]?.count, 0)
        let events = try await api.discovery(locality: "Stockton")
        let card = try XCTUnwrap(events["ALL"]?.first)
        XCTAssertEqual(card.spotsRemaining, 63)
        XCTAssertEqual(card.reasons.count, 3, "every reason the server gave reaches the screen")
        XCTAssertTrue(card.qualifies)
    }

    func testBase64URLRoundTripsAndMatchesTheServersAlphabet() {
        let bytes = Data([0xfb, 0xff, 0xbf, 0x00, 0x01])
        let s = Base64URL.encode(bytes)
        XCTAssertFalse(s.contains("+") || s.contains("/") || s.contains("="), "URL-safe, no padding: \(s)")
        XCTAssertEqual(Base64URL.decode(s), bytes)
        XCTAssertEqual(Base64URL.decode("MVjFj8SuzN3i59lQQQD0pPST6ZInV33V2qY2pKNUN50")?.count, 32, "a challenge the staging server issued decodes to 32 bytes")
    }

    func testPKCEAndTheGoogleRedirectFollowGooglesRules() throws {
        let pkce = PKCE(verifierBytes: Data(repeating: 7, count: 32))
        XCTAssertEqual(pkce, PKCE(verifierBytes: Data(repeating: 7, count: 32)), "deterministic for a fixed verifier")
        XCTAssertNotEqual(pkce.challenge, PKCE(verifierBytes: Data(repeating: 8, count: 32)).challenge)
        XCTAssertNotEqual(PKCE().verifier, PKCE().verifier, "a fresh one is random")
        XCTAssertEqual(pkce.challenge.count, 43, "SHA-256 in base64url is 43 characters")
        XCTAssertEqual(config.googleRedirectScheme, "com.googleusercontent.apps.12345-abc")
        XCTAssertEqual(GoogleOAuth.redirectURI(for: config), "com.googleusercontent.apps.12345-abc:/oauth2redirect")
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(configuration: config, pkce: pkce, nonce: "n1"))
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["code_challenge_method"], "S256")
        // PD-063: THRØ reads one claim from the token it gets back — the subject — so it asks for one
        // scope. Asserted as *what must not be there* as well as what must, because the failure this
        // guards is somebody adding `email` back for a feature that never lands: a scope requested is
        // data handed over, and data handed over is a line on a store's privacy label whether or not
        // anything reads it.
        XCTAssertEqual(items["scope"], "openid")
        for asked in ["email", "profile", "phone", "address"] {
            XCTAssertFalse(items["scope"]!.contains(asked),
                           "THRØ asks Google for no \(asked): it stores none and tells the player so")
        }
        XCTAssertEqual(items["redirect_uri"], "com.googleusercontent.apps.12345-abc:/oauth2redirect")
        XCTAssertNil(ServerConfiguration(baseURL: config.baseURL, googleClientID: "").googleClientID, "an empty plist value is no client id")
        XCTAssertEqual(GoogleOAuth.code(from: URL(string: "com.googleusercontent.apps.12345-abc:/oauth2redirect?code=4%2Fabc&scope=openid")!), "4/abc")
    }

    func testTheGoogleCodeExchangeAsksForAnIdTokenWithTheVerifier() async throws {
        let script = Script([(200, #"{"id_token":"google.id.token","access_token":"x"}"#)])
        let pkce = PKCE(verifierBytes: Data(repeating: 1, count: 32))
        let token = try await GoogleOAuth.exchange(code: "4/abc", configuration: config, pkce: pkce, transport: script)
        XCTAssertEqual(token, "google.id.token")
        let req = try XCTUnwrap(script.seen.first)
        XCTAssertEqual(req.url, GoogleOAuth.tokenEndpoint)
        let form = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(form.contains("code_verifier=\(pkce.verifier)"), form)
        XCTAssertTrue(form.contains("grant_type=authorization_code"))
        XCTAssertFalse(form.contains("client_secret"), "an iOS client has no secret to send")
    }
}

/// ADR-007 on the phone: the wire format parsed as the server writes it, the id kept for a resume.
final class StreamParserTests: XCTestCase {
    func testFramesAreAssembledAndCommentsAreNotEvents() {
        var p = SSEParser()
        XCTAssertNil(p.feed(": match abc; replaying from the start"))
        XCTAssertNil(p.feed("retry: 3000"))
        XCTAssertNil(p.feed(""))
        XCTAssertNil(p.feed("id: match:m:5-9"))
        XCTAssertNil(p.feed("event: VisitRecorded"))
        XCTAssertNil(p.feed("data: {\"player\":\"home\","))
        XCTAssertNil(p.feed("data: \"visitTotal\":60}"))
        let e = p.feed("")
        XCTAssertEqual(e, StreamEvent(id: "match:m:5-9", type: "VisitRecorded", data: "{\"player\":\"home\",\n\"visitTotal\":60}"))
        XCTAssertEqual(p.lastEventId, "match:m:5-9", "the id is what a reconnect resumes from")
        XCTAssertNil(p.feed(": ping"), "a heartbeat completes nothing")
        XCTAssertNil(p.feed(""))
        XCTAssertEqual(p.lastEventId, "match:m:5-9")
    }

    func testTheStalenessDeadlineIsThreeMissedHeartbeats() {
        XCTAssertEqual(ThroAPI.staleAfter, 45)
    }
}
