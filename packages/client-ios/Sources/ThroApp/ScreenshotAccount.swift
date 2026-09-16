#if DEBUG
import Foundation
import ThroNet

/// A signed-in account for screenshots, and for nothing else.
///
/// **Why it exists.** The simulator cannot sign in to anything real, so every screen that is only
/// shown to a signed-in person — the profile, friends, the delete screen — could be seen on the
/// founder's phone and nowhere else, and was being designed blind. Launched with
/// `-ThroScreenshotAccount`, a Debug build stands up an account store over a transport that answers
/// from memory. Nothing of the account leaves the phone and nothing is stored; a Release build does
/// not contain this file at all. The one exception is the public front — the leagues, the events,
/// the venues and other teams' fronts, which carry no account and need no session — passed through
/// to the real server, because a map of the leagues is only worth looking at with the real leagues on it.
///
///     xcrun simctl launch <device> app.thro.darts -ThroScreenshotAccount adult
///
/// The value picks who is signed in: `adult` (named, 18 or over, two ways in), `new` (no name, age
/// not said, one way in), or `failing` (every change is refused, to see the failure states).
enum ScreenshotAccount {
    static let argument = "-ThroScreenshotAccount"

    @MainActor static func storeIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountStore? {
        guard let i = arguments.firstIndex(of: argument) else { return nil }
        let who = arguments.indices.contains(i + 1) ? arguments[i + 1] : "adult"
        let stage = Stage(who)
        let configuration = ServerConfiguration(baseURL: URL(string: "https://screenshots.invalid")!,
                                                googleClientID: "screenshots.apps.googleusercontent.com")
        // Placeholders, not credentials: nothing here is sent anywhere, because `Stage` is the only
        // transport this store has and it answers from memory.
        let session = Session(accountId: Stage.accountId, playerId: Stage.playerId, accessToken: "staged-not-a-token",
                              refreshToken: "staged-not-a-token", accessExpiresAt: .distantFuture, created: false)
        let api = ThroAPI(configuration: configuration, deviceId: UUID(), store: MemorySessionStore(session), transport: stage)
        return AccountStore(api: api, configuration: configuration, services: Refusing(), transport: stage)
    }

    /// The server, played from memory.
    final class Stage: Transport, @unchecked Sendable {
        static let accountId = UUID(uuidString: "5C4EE45E-0000-4000-8000-000000000001")!
        static let playerId = UUID(uuidString: "5C4EE45E-0000-4000-8000-000000000002")!
        private let lock = NSLock()
        private var name: String?
        private var band: String
        private let credentials: Int
        private let failing: Bool
        /// Nothing is pre-agreed, which is the whole point of PD-088: a switch found already on is not
        /// consent. A screenshot that staged them on would be a screenshot of the defect V045 removed.
        private var consents: Set<String> = []

        /// Kept in step with `Consent.WHY_NOT_LIVE` by hand — there is no shared string between a Kotlin
        /// server and a Swift stage, and a stage that invented its own wording would be a screenshot of
        /// a sentence nobody ever sees.
        static let whyNotLive = "A live screen can be seen by anyone in the room, so THRØ only names "
            + "players who are 18 or over and have said yes. Your results are published the same as "
            + "everybody else's."

        init(_ who: String) {
            failing = who == "failing"
            switch who {
            case "new":
                name = nil; band = "unknown"; credentials = 1
            // The under-18 account, which PD-088 gave a reason to be able to look at: it is the only
            // state where the live switch refuses, and the refusal is the one sentence in the app that
            // a young player reads about why their name will not be on a screen.
            case "minor":
                name = "Sam C."; band = "minor"; credentials = 2
            default:
                name = "Jenson R."; band = "adult"; credentials = 2
            }
        }

        /// The public front's reads, which the real server answers (see the note above): the leagues,
        /// the events and the venues, and the front of any team but the staged one — a league's team
        /// opened from the leagues board, read as nobody, exactly as a stranger would see it. Staging
        /// every team as the account's own made the board say "You play for it" of a stranger's side.
        static let passedThrough: Set<String> = ["/v1/leagues", "/v1/events", "/v1/venues"]
        static let stagedTeam = "/v1/teams/5c4ee45e-0000-4000-8000-0000000000c1"

        static func passesThrough(_ method: String, _ path: String) -> Bool {
            guard method == "GET" else { return false }
            // The staged team and everything under it (its friendlies, its inbox) are the stage's; other teams are real.
            return passedThrough.contains(path) || (path.hasPrefix("/v1/teams/") && !path.hasPrefix(stagedTeam))
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let method = request.httpMethod ?? "GET"
            let path = request.url?.path ?? ""
            if Stage.passesThrough(method, path), let real = ServerConfiguration.fromInfoPlist(),
               var parts = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
                parts.scheme = real.baseURL.scheme
                parts.host = real.baseURL.host
                parts.port = real.baseURL.port
                if let url = parts.url {
                    var forwarded = URLRequest(url: url)
                    forwarded.setValue("application/json", forHTTPHeaderField: "Accept")
                    return try await URLSessionTransport().send(forwarded)
                }
            }
            let (code, body) = lock.withLock { answer(method, path, request.httpBody) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }

        private func answer(_ method: String, _ path: String, _ body: Data?) -> (Int, String) {
            switch (method, path) {
            case ("GET", "/v1/me"):
                return (200, profile)
            case ("PUT", "/v1/me/profile"):
                if failing { return (503, #"{"error":"THRØ could not save that just now. Nothing changed."}"#) }
                let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                if let n = sent["displayName"] as? String { name = n }
                if let b = sent["ageBand"] as? String { band = b }
                return (200, profile)
            // PD-088, staged with the same rule the server applies: `live` is refused for anyone not
            // recorded as an adult, and the sentence comes back rather than an error.
            case ("POST", "/v1/me/consent"):
                let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let scope = sent["scope"] as? String ?? ""
                let given = sent["given"] as? Bool ?? false
                if given, scope == "live", band != "adult" {
                    return (200, #"{"scope":"live","given":false,"why":"\#(Self.whyNotLive)"}"#)
                }
                if given { consents.insert(scope) } else { consents.remove(scope) }
                return (200, #"{"scope":"\#(scope)","given":\#(given)}"#)
            case ("DELETE", "/v1/me"):
                if failing { return (500, #"{"error":"the account could not be erased"}"#) }
                return (200, #"{"erased":true,"credentials":\#(credentials),"sessions":3,"devices":1,"friendships":1,"claims":1,"consents":1}"#)
            case ("GET", "/v1/friends"):
                return (200, #"{"friends":[{"accountId":"5c4ee45e-0000-4000-8000-00000000000a","displayName":"Ethan T.","since":"2026-09-10T19:00:00Z"}]}"#)
            case ("POST", "/v1/friends/invite"):
                return (200, #"{"code":"K7TQ2M4X","expiresAt":"2026-09-18T12:00:00Z"}"#)
            case ("POST", "/v1/auth/logout"):
                return (200, "{}")
            case ("GET", "/v1/me/matches"):
                // One still going, shared by the other player (PD-044); one this account sent, with the
                // other seat nobody's yet; one it took with a code and confirmed (PD-043).
                return (200, #"{"matches":[{"matchId":"5c4ee45e-0000-4000-8000-0000000000b3","openedAt":"2026-09-11T19:05:00Z","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"best_of","legsTarget":5,"throwFirst":"home"},"selfReported":true,"seats":[{"seat":"home","you":false,"name":"Ethan T.","claimable":false},{"seat":"away","you":true,"name":"Jenson R.","claimable":false}],"legs":{"home":1,"away":1},"visits":24,"ending":null,"retired":null,"winner":null,"sentBy":"home","answers":{"home":null,"away":null},"standing":"self-reported"},{"matchId":"5c4ee45e-0000-4000-8000-0000000000b1","openedAt":"2026-09-10T19:30:00Z","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"first_to","legsTarget":3},"selfReported":true,"seats":[{"seat":"home","you":true,"name":"Jenson R.","claimable":false},{"seat":"away","you":false,"name":null,"claimable":true}],"legs":{"home":3,"away":1},"visits":41,"ending":null,"retired":null,"winner":"home","sentBy":"home","answers":{"home":null,"away":null},"standing":"self-reported"},{"matchId":"5c4ee45e-0000-4000-8000-0000000000b2","openedAt":"2026-09-08T20:10:00Z","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"best_of","legsTarget":5},"selfReported":true,"seats":[{"seat":"home","you":false,"name":"Ethan T.","claimable":false},{"seat":"away","you":true,"name":"Jenson R.","claimable":false}],"legs":{"home":2,"away":3},"visits":52,"ending":null,"retired":null,"winner":"away","sentBy":"home","answers":{"home":null,"away":"confirmed"},"standing":"confirmed"}]}"#)
            case ("GET", "/v1/me/teams"):
                return (200, #"{"teams":[{"teamId":"5c4ee45e-0000-4000-8000-0000000000c1","name":"The Bell B","locality":"Stockton-on-Tees","role":"admin","members":3}]}"#)
            default:
                // The desk's answers (PD-107..PD-113) first: the staged team's friendlies live under its path.
                if let staged = Self.desk(method, path, body) { return staged }
                // The team this account runs, as its admin reads it: a handle on each entry (PD-045).
                if method == "GET", path.hasPrefix("/v1/teams/") {
                    return (200, #"{"teamId":"5c4ee45e-0000-4000-8000-0000000000c1","name":"The Bell B","locality":"Stockton-on-Tees","venue":null,"seasons":[{"league":"Teesside Thursday League","label":"2026/27","division":null,"leagueSeasonId":"5c4ee45e-0000-4000-8000-0000000000f5","accepted":true}],"roster":[{"name":"Jenson R.","role":"admin","memberId":"5c4ee45e-0000-4000-8000-0000000000d1"},{"name":"Ethan T.","role":"captain","memberId":"5c4ee45e-0000-4000-8000-0000000000d2"},{"name":null,"role":"player","memberId":"5c4ee45e-0000-4000-8000-0000000000d3"}],"yourRole":"admin"}"#)
                }
                if method == "POST", path.hasPrefix("/v1/matches/"), path.hasSuffix("/code") {
                    return (200, #"{"code":"M4TC7H2Q","seat":"away","expiresAt":"2026-09-18T12:00:00Z"}"#)
                }
                if path.hasPrefix("/v1/me/inbox") || path.contains("discovery") { return (200, #"{"sections":{}}"#) }
                return (404, #"{"error":"not staged for screenshots"}"#)
            }
        }

        // MARK: - PD-107..PD-113 on the phone: the inbox's tasks, a proposed date, an event through its rounds, a
        // team's friendlies and its fixture. One scene, played from memory, in the words the server uses.
        static let me = playerId.uuidString.lowercased()
        static let ethan = "5c4ee45e-0000-4000-8000-0000000000a2"
        static let sam = "5c4ee45e-0000-4000-8000-0000000000a3"
        static let regTask = "5c4ee45e-0000-4000-8000-0000000000e1"
        static let moveTask = "5c4ee45e-0000-4000-8000-0000000000e2"
        static let proposal = "5c4ee45e-0000-4000-8000-0000000000f1"
        static let submission = "5c4ee45e-0000-4000-8000-0000000000f2"
        static let event = "5c4ee45e-0000-4000-8000-0000000000f3"
        static let tie = "5c4ee45e-0000-4000-8000-0000000000f4"
        static let season = "5c4ee45e-0000-4000-8000-0000000000f5"
        static let fixture = "5c4ee45e-0000-4000-8000-0000000000f6"
        static let friendlyIn = "5c4ee45e-0000-4000-8000-0000000000f7"
        static let friendlyOut = "5c4ee45e-0000-4000-8000-0000000000f8"
        nonisolated(unsafe) static var feeConfirmed = false
        nonisolated(unsafe) static var sent = false
        nonisolated(unsafe) static var proposalState = "proposed"
        nonisolated(unsafe) static var checkedIn = false
        nonisolated(unsafe) static var friendlyInState = "proposed"

        static func desk(_ method: String, _ path: String, _ body: Data?) -> (Int, String)? {
            let sentBody = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            switch (method, path) {
            case ("GET", "/v1/me/rating"):
                return (200, #"{"playerId":"\#(me)","model":"glicko2","version":"1","stage":"provisional","display":{"kind":"provisional","low":1460,"high":1620,"value":null,"plusMinus":null,"matches":4,"comparedAcross":11},"asOf":{"commit":1,"seq":1},"lines":[{"matchId":"5c4ee45e-0000-4000-8000-0000000000b2","outcome":"won","delta":38,"opponent":"Ethan T.","opponentRating":1510,"words":"Won 3–2 against Ethan T. (about 1510): up 38."},{"matchId":"5c4ee45e-0000-4000-8000-0000000000b1","outcome":"won","delta":22,"opponent":null,"opponentRating":null,"words":"Won 3–1 against a player THRØ may not name: up 22."}]}"#)
            case ("GET", "/v1/me/inbox"):
                return (200, #"{"sections":{"ACTION_REQUIRED":[{"taskId":"\#(regTask)","kind":"registration_required","reason":"Register Sam with the Teesside Thursday League","dueAt":"2026-10-01T18:30:00Z","state":"open","player":"\#(sam)","proposal":null},{"taskId":"\#(moveTask)","kind":"rearrangement_answer_due","reason":"Answer the proposed new date","dueAt":"2026-09-23T12:00:00Z","state":"\#(proposalState == "proposed" ? "open" : "done")","player":null,"proposal":"\#(proposal)"}],"UPCOMING":[{"taskId":"5c4ee45e-0000-4000-8000-0000000000e3","kind":"result_submission_due","reason":"Send Thursday's result to the league","dueAt":"2026-10-10T12:00:00Z","state":"open","player":null,"proposal":null}]}}"#)
            case ("POST", "/v1/tasks/\(regTask)/assess"):
                return feeConfirmed
                    ? (200, #"{"missing":[],"manualOutstanding":[],"submissionId":"\#(submission)","state":"\#(sent ? "delivered" : "ready")"}"#)
                    : (200, #"{"missing":[],"manualOutstanding":["fee"],"submissionId":null,"state":null}"#)
            case ("POST", "/v1/tasks/\(regTask)/confirm"):
                feeConfirmed = true; return (200, #"{"taskId":"\#(regTask)","confirmed":"fee"}"#)
            case ("POST", "/v1/submissions/\(submission)/submit"):
                if sent { return (409, #"{"error":"a submission does not move from delivered to submitted"}"#) }
                sent = true; return (200, #"{"submissionId":"\#(submission)","state":"delivered"}"#)
            case ("GET", "/v1/proposals/\(proposal)"), ("POST", "/v1/proposals/\(proposal)/answer"):
                if method == "POST" { proposalState = (sentBody["answer"] as? String) == "accepted" ? "accepted" : "declined" }
                return (200, proposalJson)
            case ("GET", "/v1/fixtures/\(fixture)/proposals"):
                return (200, #"{"proposals":[\#(proposalJson)]}"#)
            case ("GET", "/v1/me/discovery"):
                return (200, #"{"sections":{"ALREADY_ENTERED":[\#(card)],"THIS_WEEKEND":[{"eventId":"5c4ee45e-0000-4000-8000-0000000000f9","name":"Stockton Saturday Open","tournament":null,"venue":"Riverside WMC","locality":"Stockton-on-Tees","startsAt":"2026-09-19T11:00:00Z","entriesCloseAt":"2026-09-18T20:00:00Z","entrantKind":"player","access":"open","capacity":64,"spotsRemaining":23,"entered":false,"qualifies":true,"series":[],"reasons":["this weekend","open entry","23 places left"]}]}}"#)
            case ("GET", "/v1/events/\(event)"), ("POST", "/v1/events/\(event)/check-in"), ("POST", "/v1/events/\(event)/ties/\(tie)/match"):
                if method == "POST", path.hasSuffix("check-in") { checkedIn = true; return (200, #"{"grantId":"5c4ee45e-0000-4000-8000-0000000000fa","expiresAt":"2026-09-20T23:00:00Z"}"#) }
                return (200, eventPage(decided: method == "POST"))
            case ("GET", "/v1/teams/5c4ee45e-0000-4000-8000-0000000000c1/friendlies"):
                return (200, #"{"friendlies":[\#(friendly(friendlyIn, from: "The Sun Inn A", fromId: "5c4ee45e-0000-4000-8000-0000000000c2", to: "The Bell B", toId: "5c4ee45e-0000-4000-8000-0000000000c1", at: "2026-09-25T19:30:00Z", message: "Friday, our board, first to five?", state: friendlyInState, direction: "received")),\#(friendly(friendlyOut, from: "The Bell B", fromId: "5c4ee45e-0000-4000-8000-0000000000c1", to: "Riverside A", toId: "5c4ee45e-0000-4000-8000-0000000000c3", at: "2026-10-02T19:30:00Z", message: nil, state: "accepted", direction: "sent"))]}"#)
            case ("POST", "/v1/friendlies/\(friendlyIn)/answer"):
                friendlyInState = (sentBody["answer"] as? String) == "accepted" ? "accepted" : "declined"
                return (200, friendly(friendlyIn, from: "The Sun Inn A", fromId: "5c4ee45e-0000-4000-8000-0000000000c2", to: "The Bell B", toId: "5c4ee45e-0000-4000-8000-0000000000c1", at: "2026-09-25T19:30:00Z", message: "Friday, our board, first to five?", state: friendlyInState, direction: "received"))
            case ("GET", "/v1/seasons/\(season)/fixtures"):
                return (200, #"{"fixtures":[{"fixtureId":"\#(fixture)","divisionId":null,"division":null,"scheduledAt":"2026-10-08T19:30:00Z","state":"scheduled","home":"The Bell B","away":"Riverside A","homeTeamId":"5c4ee45e-0000-4000-8000-0000000000c1","awayTeamId":"5c4ee45e-0000-4000-8000-0000000000c3","venue":"The Bell","locality":"Stockton-on-Tees","decided":null,"version":1}]}"#)
            case ("GET", "/v1/fixtures/\(fixture)/team/5c4ee45e-0000-4000-8000-0000000000c1"):
                return (200, #"{"fixtureId":"\#(fixture)","leagueSeasonId":"\#(season)","teamId":"5c4ee45e-0000-4000-8000-0000000000c1","home":true,"opponent":"Riverside A","opponentTeamId":"5c4ee45e-0000-4000-8000-0000000000c3","scheduledAt":"2026-10-08T19:30:00Z","state":"scheduled","venue":"The Bell","version":1,"matchId":null,"yourRole":"admin","mayNameLineup":true,"members":[{"playerId":"\#(me)","name":"Jenson R.","availability":"available","availabilityVersion":1,"role":"admin"},{"playerId":"\#(ethan)","name":"Ethan T.","availability":null,"availabilityVersion":0,"role":"captain"},{"playerId":"\#(sam)","name":null,"availability":"maybe","availabilityVersion":1,"role":"player"}],"lineup":{"version":0,"players":[]}}"#)
            default:
                return nil
            }
        }

        static var proposalJson: String {
            #"{"proposalId":"\#(proposal)","fixtureId":"\#(fixture)","leagueSeasonId":"\#(season)","state":"\#(proposalState)","to":"2026-10-15T19:30:00Z","reason":"venue double-booked","byTeamId":"5c4ee45e-0000-4000-8000-0000000000c3","byTeam":"Riverside A","toTeamId":"5c4ee45e-0000-4000-8000-0000000000c1","toTeam":"The Bell B","proposedAt":"2026-09-16T12:00:00Z","answeredAt":null,"scheduledAt":"2026-10-08T19:30:00Z","fixtureVersion":1}"#
        }

        static var card: String {
            #"{"eventId":"\#(event)","name":"Sun Inn Open","tournament":null,"venue":"The Sun Inn","locality":"Stockton-on-Tees","startsAt":"2026-09-16T19:00:00Z","entriesCloseAt":null,"entrantKind":"player","access":"open","capacity":8,"spotsRemaining":4,"entered":true,"qualifies":true,"series":[],"reasons":["you are entered","tonight","drawn"]}"#
        }

        static func eventPage(decided: Bool) -> String {
            let quoted = { (s: String) -> String in "\"" + s + "\"" }
            let matchId = decided ? quoted("5c4ee45e-0000-4000-8000-0000000000b2") : "null"
            let winner = decided ? quoted(me) : "null"
            let outcome = decided ? quoted("played") : "null"
            return #"{"eventId":"\#(event)","name":"Sun Inn Open","startsAt":"2026-09-16T19:00:00Z","sessionEndsAt":"2026-09-16T23:00:00Z","venueId":null,"venue":"The Sun Inn","locality":"Stockton-on-Tees","venueLabel":null,"entrantKind":"player","access":"open","state":"in_progress","entriesCloseAt":null,"capacity":8,"entries":4,"spotsRemaining":4,"you":{"entered":true,"checkedIn":\#(checkedIn)},"draw":[{"tieId":"\#(tie)","round":1,"position":1,"homeId":"\#(me)","home":"Jenson R.","awayId":"\#(ethan)","away":"Ethan T.","isBye":false,"matchId":\#(matchId),"winnerId":\#(winner),"outcome":\#(outcome),"note":null},{"tieId":"5c4ee45e-0000-4000-8000-0000000000fb","round":1,"position":2,"homeId":"\#(sam)","home":null,"awayId":null,"away":null,"isBye":true,"matchId":null,"winnerId":"\#(sam)","outcome":"bye","note":null}],"winnerId":null,"entrants":null}"#
        }

        static func friendly(_ id: String, from: String, fromId: String, to: String, toId: String, at: String, message: String?, state: String, direction: String) -> String {
            let quoted = { (s: String) -> String in "\"" + s + "\"" }
            let m = message.map(quoted) ?? "null"
            let note = state == "accepted" ? quoted("see you Friday") : "null"
            let answered = state == "proposed" ? "null" : quoted("2026-09-16T13:00:00Z")
            return #"{"friendlyId":"\#(id)","fromTeamId":"\#(fromId)","fromTeam":"\#(from)","toTeamId":"\#(toId)","toTeam":"\#(to)","playAt":"\#(at)","venue":null,"message":\#(m),"state":"\#(state)","proposedAt":"2026-09-16T12:00:00Z","answeredAt":\#(answered),"answerNote":\#(note),"matchId":null,"version":1,"direction":"\#(direction)"}"#
        }

        private var profile: String {
            let n = name.map { "\"\($0)\"" } ?? "\"New player\""
            let agreed = consents.map { "\"\($0)\"" }.joined(separator: ",")
            return #"{"accountId":"\#(Stage.accountId.uuidString.lowercased())","playerId":"\#(Stage.playerId.uuidString.lowercased())","displayName":\#(n),"named":\#(name != nil),"ageBand":"\#(band)","credentials":\#(credentials),"consents":[\#(agreed)]}"#
        }
    }

    /// Ceremonies that never open anything: a screenshot has no Apple ID to sign in with.
    struct Refusing: SignInServices {
        func appleIdentityToken(nonce: String) async throws -> String? { nil }
        func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String? { nil }
        func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration? { nil }
        func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion? { nil }
    }
}
#endif
