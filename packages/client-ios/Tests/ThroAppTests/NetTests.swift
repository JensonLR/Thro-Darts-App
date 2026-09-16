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

    /// PD-107: a registration task carries the player it is about, and the captain's three acts over it decode to what the server said.
    func testARegistrationTaskIsAssessedConfirmedAndSent() async throws {
        let inbox = #"{"sections":{"ACTION_REQUIRED":[{"taskId":"cccccccc-0000-0000-0000-000000000001","kind":"registration_required","reason":"Register Sam with the Teesside league","dueAt":"2026-09-20T00:00:00Z","state":"open","player":"aaaaaaaa-0000-0000-0000-000000000002"}]}}"#
        let assessed = #"{"missing":["age_band"],"manualOutstanding":["fee"],"submissionId":null,"state":null}"#
        let confirmed = #"{"taskId":"cccccccc-0000-0000-0000-000000000001","confirmed":"fee"}"#
        let ready = #"{"missing":[],"manualOutstanding":[],"submissionId":"eeeeeeee-0000-0000-0000-000000000003","state":"ready"}"#
        let sent = #"{"submissionId":"eeeeeeee-0000-0000-0000-000000000003","state":"delivered"}"#
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, inbox), (200, assessed), (200, confirmed), (200, ready), (200, sent), (409, #"{"error":"It cannot be sent from where it is."}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let sections = try await api.inbox()
        let task = try XCTUnwrap(sections["ACTION_REQUIRED"]?.first)
        XCTAssertEqual(task.player?.uuidString.lowercased(), "aaaaaaaa-0000-0000-0000-000000000002")
        let first = try await api.assessRegistration(task: task.taskId)
        XCTAssertEqual(first.missing, ["age_band"]); XCTAssertEqual(first.manualOutstanding, ["fee"]); XCTAssertNil(first.submissionId)
        try await api.confirmRequirement(task: task.taskId, requirement: "fee", note: "paid in cash")
        XCTAssertTrue(String(decoding: script.seen[2].httpBody ?? Data(), as: UTF8.self).contains("paid in cash"), "the note travels")
        let second = try await api.assessRegistration(task: task.taskId)
        XCTAssertEqual(second.state, "ready")
        let state = try await api.submitRegistration(submission: try XCTUnwrap(second.submissionId))
        XCTAssertEqual(state, "delivered")
        do { _ = try await api.submitRegistration(submission: try XCTUnwrap(second.submissionId)); XCTFail("a resend is refused") }
        catch let e as APIError { XCTAssertEqual(e.message, "It cannot be sent from where it is.") }
    }

    /// PD-108: a proposed date decodes with both dates and both teams; the inbox task points at it; answering carries the note.
    func testAProposedDateIsReadAnsweredAndProposed() async throws {
        let proposal = #"{"proposalId":"eeeeeeee-0000-0000-0000-000000000009","fixtureId":"ffffffff-0000-0000-0000-000000000001","leagueSeasonId":"ffffffff-0000-0000-0000-000000000002","state":"proposed","to":"2026-10-15T19:30:00Z","reason":"venue double-booked","byTeamId":"aaaaaaaa-0000-0000-0000-000000000001","byTeam":"Riverside A","toTeamId":"aaaaaaaa-0000-0000-0000-000000000002","toTeam":"Grange A","proposedAt":"2026-09-16T12:00:00Z","answeredAt":null,"scheduledAt":"2026-10-08T19:30:00Z","fixtureVersion":1}"#
        let inbox = #"{"sections":{"ACTION_REQUIRED":[{"taskId":"cccccccc-0000-0000-0000-000000000007","kind":"rearrangement_answer_due","reason":"Answer the proposed new date","dueAt":"2026-09-23T12:00:00Z","state":"open","player":null,"proposal":"eeeeeeee-0000-0000-0000-000000000009"}]}}"#
        let accepted = proposal.replacingOccurrences(of: #""state":"proposed""#, with: #""state":"accepted""#)
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, inbox), (200, proposal), (200, accepted), (200, #"{"proposals":[\#(proposal)]}"#), (200, proposal)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let sections = try await api.inbox()
        let task = try XCTUnwrap(sections["ACTION_REQUIRED"]?.first)
        let proposalId = try XCTUnwrap(task.proposal)
        let read = try await api.proposal(proposalId)
        XCTAssertEqual(read.byTeam, "Riverside A"); XCTAssertEqual(read.toTeam, "Grange A"); XCTAssertEqual(read.reason, "venue double-booked")
        XCTAssertLessThan(read.scheduledAt, read.to, "both dates arrive, the one it stands on and the one proposed")
        let answered = try await api.answerProposal(proposalId, answer: "accepted", note: "fine by us")
        XCTAssertEqual(answered.state, "accepted")
        XCTAssertTrue(String(decoding: script.seen[2].httpBody ?? Data(), as: UTF8.self).contains("fine by us"))
        let list = try await api.proposals(fixture: read.fixtureId)
        XCTAssertEqual(list.count, 1)
        let made = try await api.propose(fixture: read.fixtureId, team: read.byTeamId, to: read.to, reason: "cup night")
        XCTAssertEqual(made.state, "proposed")
        let sent = String(decoding: script.seen[4].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(sent.contains("2026-10-15T19:30:00Z") && sent.contains("cup night"), "the date goes as an instant, the reason as words: \(sent)")
    }

    /// PD-109: an event's page decodes with `you`; entering, withdrawing and checking in go to the right paths and read back.
    func testAnEventIsEnteredWithdrawnAndCheckedIn() async throws {
        let page = #"{"eventId":"dddddddd-0000-0000-0000-000000000001","name":"Sun Inn Open","startsAt":"2026-10-03T11:00:00Z","sessionEndsAt":"2026-10-03T22:00:00Z","venueId":null,"venue":"The Sun Inn","locality":"Stockton","venueLabel":null,"entrantKind":"player","access":"open","state":"open","entriesCloseAt":null,"capacity":32,"entries":5,"spotsRemaining":27,"you":{"entered":false,"checkedIn":false},"draw":[]}"#
        let entered = page.replacingOccurrences(of: #""you":{"entered":false,"checkedIn":false}"#, with: #""you":{"entered":true,"checkedIn":false}"#)
        let drawn = entered.replacingOccurrences(of: #""draw":[]"#, with: #""draw":[{"tieId":"eeeeeeee-0000-0000-0000-000000000001","round":1,"position":1,"homeId":"aaaaaaaa-0000-0000-0000-000000000001","home":"Alice Aims","awayId":null,"away":null,"isBye":true,"matchId":null}]"#)
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, page), (200, entered), (409, #"{"error":"This event is full: 32 places, all taken."}"#), (200, #"{"grantId":"99999999-0000-0000-0000-000000000001","expiresAt":"2026-10-04T22:00:00Z"}"#), (200, drawn), (200, page)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let id = UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!
        let first = try await api.event(id)
        XCTAssertEqual(first.you?.entered, false); XCTAssertEqual(first.spotsRemaining, 27)
        let second = try await api.enter(event: id)
        XCTAssertEqual(second.you?.entered, true)
        XCTAssertTrue(script.seen[1].url!.path.hasSuffix("/entries"))
        do { _ = try await api.enter(event: id); XCTFail("full is refused") } catch let e as APIError { XCTAssertEqual(e.message, "This event is full: 32 places, all taken.") }
        let grant = try await api.checkIn(event: id)
        XCTAssertEqual(grant.expiresAt, ISO8601DateFormatter().date(from: "2026-10-04T22:00:00Z"))
        XCTAssertEqual(script.seen[3].value(forHTTPHeaderField: "X-Thro-Device"), device.uuidString.lowercased(), "the phone checking in names itself")
        let withDraw = try await api.event(id)
        XCTAssertEqual(withDraw.draw.first?.isBye, true); XCTAssertEqual(withDraw.draw.first?.home, "Alice Aims")
        let out = try await api.withdraw(event: id)
        XCTAssertEqual(out.you?.entered, false)
        XCTAssertTrue(script.seen[5].url!.path.hasSuffix("/withdraw"))
    }

    /// PD-111: a tie decodes with its decision, and naming its match goes to the tie's own path with the match id.
    func testATieIsCitedAndReadsItsWinner() async throws {
        let decided = #"{"eventId":"dddddddd-0000-0000-0000-000000000001","name":"Friday Fours","startsAt":"2026-10-09T19:00:00Z","sessionEndsAt":"2026-10-09T23:00:00Z","venueId":null,"venue":null,"locality":null,"venueLabel":"the back room","entrantKind":"player","access":"open","state":"in_progress","entriesCloseAt":null,"capacity":null,"entries":4,"spotsRemaining":null,"you":{"entered":true,"checkedIn":true},"draw":[{"tieId":"eeeeeeee-0000-0000-0000-000000000001","round":1,"position":1,"homeId":"aaaaaaaa-0000-0000-0000-000000000001","home":"Alice Aims","awayId":"aaaaaaaa-0000-0000-0000-000000000002","away":"Bob Board","isBye":false,"matchId":"99999999-0000-0000-0000-000000000009","winnerId":"aaaaaaaa-0000-0000-0000-000000000001","outcome":"played","note":null}],"winnerId":null}"#
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001"), accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, decided)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let event = UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!, tie = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000001")!, match = UUID(uuidString: "99999999-0000-0000-0000-000000000009")!
        let page = try await api.citeTie(event: event, tie: tie, match: match)
        XCTAssertEqual(page.draw.first?.winnerId?.uuidString.lowercased(), "aaaaaaaa-0000-0000-0000-000000000001")
        XCTAssertEqual(page.draw.first?.outcome, "played")
        XCTAssertTrue(script.seen[0].url!.path.hasSuffix("/ties/eeeeeeee-0000-0000-0000-000000000001/match"))
        XCTAssertTrue(String(decoding: script.seen[0].httpBody ?? Data(), as: UTF8.self).contains("99999999-0000-0000-0000-000000000009"))
    }

    /// PD-110: a friendly decodes with both teams and its direction; a challenge goes with its date and message; the answer carries its note.
    func testAFriendlyIsChallengedReadAndAnswered() async throws {
        let friendly = #"{"friendlyId":"ffffffff-0000-0000-0000-000000000001","fromTeamId":"aaaaaaaa-0000-0000-0000-000000000001","fromTeam":"Riverside A","toTeamId":"aaaaaaaa-0000-0000-0000-000000000002","toTeam":"Grange A","playAt":"2026-09-25T19:30:00Z","venue":null,"message":"Friday, our board?","state":"proposed","proposedAt":"2026-09-16T12:00:00Z","answeredAt":null,"answerNote":null,"matchId":null,"version":1,"direction":"received"}"#
        let accepted = friendly.replacingOccurrences(of: #""state":"proposed""#, with: #""state":"accepted""#).replacingOccurrences(of: #""answerNote":null"#, with: #""answerNote":"see you Friday""#)
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, #"{"friendlies":[\#(friendly)]}"#), (200, accepted), (200, friendly.replacingOccurrences(of: "received", with: "sent")), (409, #"{"error":"A challenge between these two teams is already waiting for an answer."}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        let grange = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!
        let list = try await api.friendlies(team: grange)
        let first = try XCTUnwrap(list.first)
        XCTAssertEqual(first.direction, "received"); XCTAssertEqual(first.fromTeam, "Riverside A"); XCTAssertEqual(first.message, "Friday, our board?")
        let answered = try await api.answerFriendly(first.friendlyId, answer: "accepted", note: "see you Friday")
        XCTAssertEqual(answered.state, "accepted"); XCTAssertEqual(answered.answerNote, "see you Friday")
        XCTAssertTrue(String(decoding: script.seen[1].httpBody ?? Data(), as: UTF8.self).contains("see you Friday"))
        let made = try await api.challenge(from: first.fromTeamId, to: grange, playAt: first.playAt, message: "Friday, our board?")
        XCTAssertEqual(made.direction, "sent")
        let sent = String(decoding: script.seen[2].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(sent.contains("2026-09-25T19:30:00Z") && sent.contains(grange.uuidString.lowercased()), "the date goes as an instant and the team by id: \(sent)")
        do { _ = try await api.challenge(from: first.fromTeamId, to: grange, playAt: first.playAt, message: nil); XCTFail("a second open challenge is refused") }
        catch let e as APIError { XCTAssertEqual(e.message, "A challenge between these two teams is already waiting for an answer.") }
    }

    /// PD-114: approving a screen's code goes to the code's own path, upper-cased, and a refusal comes back in words.
    func testApprovingAScreensCodeIsSentAsTyped() async throws {
        let store = MemorySessionStore(Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false))
        let script = Script([(200, #"{"approved":true}"#), (404, #"{"error":"THRØ has no such code, or it has expired. Ask the screen for a new one."}"#)])
        let api = ThroAPI(configuration: config, deviceId: device, store: store, transport: script)
        try await api.approveScreen(code: " k7tq2m ")
        XCTAssertTrue(script.seen[0].url!.path.hasSuffix("/v1/auth/link/K7TQ2M/approve"), "trimmed and upper-cased: \(script.seen[0].url!.path)")
        do { try await api.approveScreen(code: "ZZZZZZ"); XCTFail("an unknown code is refused") }
        catch let e as APIError { XCTAssertEqual(e.message, "THRØ has no such code, or it has expired. Ask the screen for a new one.") }
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
