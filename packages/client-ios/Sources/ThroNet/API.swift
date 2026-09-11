import CryptoKit
import Foundation

// ThroNet — the phone's side of the wire. Sign-in, the session THRØ issues, and the reads and
// commands the server offers. Nothing in the scoring path depends on this module (Package.swift
// says so and `tools/check_absence_claims.py` holds it): the journal writes the phone's own truth
// without it, and this module carries that truth nowhere — the only things it sends are a sign-in
// and, later, the commands a person explicitly makes.

/// Where the server is and how a sign-in provider knows this app.
public struct ServerConfiguration: Sendable, Equatable {
    public let baseURL: URL
    /// The Google OAuth iOS client id, or nil when this build has none — the button then says so.
    public let googleClientID: String?

    public init(baseURL: URL, googleClientID: String? = nil) {
        self.baseURL = baseURL
        self.googleClientID = googleClientID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// The WebAuthn relying party is the API's host; passkeys are bound to it.
    public var relyingParty: String { baseURL.host ?? "" }

    /// Google requires an iOS client's redirect to use its reversed client id as the URL scheme.
    public var googleRedirectScheme: String? {
        guard let id = googleClientID, id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return "com.googleusercontent.apps." + String(id.dropLast(".apps.googleusercontent.com".count))
    }

    /// Read from the app's Info.plist: `THROAPIBaseURL` and `THROGoogleClientID`.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> ServerConfiguration? {
        guard let raw = bundle.object(forInfoDictionaryKey: "THROAPIBaseURL") as? String,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil else { return nil }
        return ServerConfiguration(baseURL: url, googleClientID: bundle.object(forInfoDictionaryKey: "THROGoogleClientID") as? String)
    }
}

/// THRØ's own session: a short-lived access token and a refresh token that rotates.
public struct Session: Codable, Sendable, Equatable {
    public let accountId: UUID
    public let playerId: UUID?
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresAt: Date
    /// True when this sign-in created the account.
    public let created: Bool

    public init(accountId: UUID, playerId: UUID?, accessToken: String, refreshToken: String, accessExpiresAt: Date, created: Bool) {
        self.accountId = accountId; self.playerId = playerId; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.accessExpiresAt = accessExpiresAt; self.created = created
    }
}

/// Codable rather than only Decodable because the phone keeps the last one it was given
/// (`ProfileCache`), so a signed-in person is shown as themselves before the server has answered.
public struct Profile: Codable, Sendable, Equatable {
    public let accountId: UUID?
    public let playerId: UUID?
    public let displayName: String?
    /// False while the name is the placeholder the server gives a new account.
    public let named: Bool
    public let ageBand: String
    /// How many ways into the account exist (PD-032): one is fragile, and the screen says so.
    public let credentials: Int?
    /// The terms in force, and whether this account has accepted them (PD-050).
    ///
    /// **Both optional, deliberately.** The phone keeps the last profile it was given, and a field made
    /// non-optional here would stop a cache written by an older build from decoding at all — a signed-in
    /// person would be shown as nobody because the terms had changed since they last opened the app.
    public let termsVersion: String?
    public let acceptedTerms: Bool?

    public init(accountId: UUID?, playerId: UUID?, displayName: String?, named: Bool, ageBand: String, credentials: Int?,
                termsVersion: String? = nil, acceptedTerms: Bool? = nil) {
        self.accountId = accountId; self.playerId = playerId; self.displayName = displayName
        self.named = named; self.ageBand = ageBand; self.credentials = credentials
        self.termsVersion = termsVersion; self.acceptedTerms = acceptedTerms
    }
}

public struct InboxItem: Decodable, Sendable, Equatable, Identifiable {
    public let taskId: UUID
    public let kind: String
    public let reason: String
    public let dueAt: Date?
    public let state: String
    public var id: UUID { taskId }
}

/// A league as its public front shows it: seasons newest first, each with its divisions and teams,
/// each team with its home venue where one is known and the BASIS that venue was connected on.
/// Dates arrive as `yyyy-MM-dd` strings and stay strings: they are calendar days, not instants.
public struct PublicLeague: Decodable, Sendable, Equatable, Identifiable {
    public struct Source: Decodable, Sendable, Equatable {
        public let source: String
        public let url: String?
        public let retrievedOn: String
    }
    public struct Venue: Decodable, Sendable, Equatable {
        public let venueId: UUID
        public let name: String
        public let locality: String?
        public let postcode: String?
        public let latitude: Double?
        public let longitude: Double?
        /// "stated by the source", or "inferred from the team's name" — shown, never hidden.
        public let basis: String?
    }
    public struct Team: Decodable, Sendable, Equatable, Identifiable {
        public let teamId: UUID
        public let name: String
        public let venue: Venue?
        public var id: UUID { teamId }
    }
    public struct Division: Decodable, Sendable, Equatable, Identifiable {
        public let divisionId: UUID
        public let name: String
        public let ordinal: Int
        public let teams: [Team]
        public var id: UUID { divisionId }
    }
    public struct Season: Decodable, Sendable, Equatable, Identifiable {
        public let leagueSeasonId: UUID
        public let label: String
        public let startsOn: String
        public let endsOn: String
        public let current: Bool
        public let divisions: [Division]
        public var id: UUID { leagueSeasonId }
    }
    public let leagueId: UUID
    public let name: String
    public let shortName: String?
    public let playsOn: String?
    public let locality: String?
    /// Where the league says it is: its pin and its distance until a venue of its own is placed.
    /// Absent on a wire from before V030, which is the same as unplaced.
    public let latitude: Double?
    public let longitude: Double?
    /// The league's own pages, for the fixtures and tables THRØ does not hold.
    public let website: String?
    public let sources: [Source]
    /// What the league published about itself.
    public let seasons: [Season]
    /// Teams whose own admin or captain says they play in this league (PD-049): their say, beside the
    /// seasons and never inside them. Optional: a server from before V039 does not send it.
    public let saidTeams: [Team]?
    public var id: UUID { leagueId }

    /// The season to show: the one running today, else the newest.
    public var shownSeason: Season? { seasons.first(where: \.current) ?? seasons.first }
}

/// An open-entry event as its public notice shows it: what, where, when, how many places. Who is
/// in it, and whether you may be, is the signed-in discovery model's business.
public struct PublicEvent: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: UUID
    public let name: String
    public let tournament: String?
    public let venue: PublicLeague.Venue?
    public let venueLabel: String?
    public let startsAt: Date
    public let entriesCloseAt: Date?
    public let entrantKind: String
    public let capacity: Int?
    public var id: UUID { eventId }
}

/// A league season's table, as the server computes it (PD-054).
///
/// Every field the app needs to say *why* the table reads as it does travels with it: which rules ordered
/// it and whose they are, which step separated each row from the one above, how many fixtures have gone by
/// with no result, and how much of each row came from a match scored on THRØ rather than somebody's word.
public struct LeagueStandings: Decodable, Sendable, Equatable {

    /// Which rules ordered the table. Never absent: a standard nobody can see is a standard THRØ imposed.
    public struct Rules: Decodable, Sendable, Equatable {
        public let policyId: UUID?
        public let version: Int?
        /// `league` when the league approved these, `thro` when it has said nothing and the standard applied.
        public let whose: String
        /// The sentence to print beside the table.
        public let says: String
        public let orderedBy: [String]

        /// True when these are the league's own rules rather than THRØ's standard.
        public var leagues: Bool { whose == "league" }
    }

    public struct Row: Decodable, Sendable, Equatable, Identifiable {
        public let position: Int
        /// The chain step that put this row above the next, or nil when nothing in the chain could.
        public let separatedBy: String?
        public let teamId: UUID
        public let name: String
        public let played: Int
        public let won: Int
        public let drawn: Int
        public let lost: Int
        public let legsFor: Int
        public let legsAgainst: Int
        public let legDifference: Int
        public let points: Int
        public let awardedFor: Int
        public let awardedAgainst: Int
        /// How many of the played fixtures cite a match scored on THRØ (PD-020).
        public let evidenced: Int
        public var id: UUID { teamId }
    }

    public struct Division: Decodable, Sendable, Equatable, Identifiable {
        public let divisionId: UUID?
        public let name: String
        public let ordinal: Int?
        /// Fixtures whose night has been and gone with no result entered.
        public let awaitingResults: Int
        public let rows: [Row]
        public var id: String { divisionId?.uuidString ?? name }
    }

    public let leagueSeasonId: UUID
    public let leagueId: UUID
    public let league: String
    public let label: String
    public let state: String
    public let rules: Rules
    public let divisions: [Division]
}

/// A team the caller is in, as the server lists it.
public struct TeamSummary: Decodable, Sendable, Equatable, Identifiable {
    public let teamId: UUID
    public let name: String
    public let locality: String?
    public let role: String
    public let members: Int
    public var id: UUID { teamId }
    public init(teamId: UUID, name: String, locality: String?, role: String, members: Int) {
        self.teamId = teamId; self.name = name; self.locality = locality; self.role = role; self.members = members
    }
}

/// A team's front: what anyone may see, and, with a bearer, what you are in it.
public struct TeamFront: Decodable, Sendable, Equatable {
    public struct Member: Decodable, Sendable, Equatable {
        /// Nil when the person may not be named (a minor, or consent not settled): counted, not shown.
        public let name: String?
        public let role: String
        /// The roster entry's own handle, for the team's admin alone, to name a captain with (PD-045).
        /// Not a person's id; nil for everybody else.
        public let memberId: UUID?
    }
    public struct SeasonLine: Decodable, Sendable, Equatable {
        public let league: String
        public let label: String
        public let division: String?
    }
    /// A league the team's own admin or captain says it plays in (PD-049): its say, not the league's.
    public struct LeagueSaid: Decodable, Sendable, Equatable, Identifiable {
        public let leagueId: UUID
        public let name: String
        public var id: UUID { leagueId }
    }
    public let teamId: UUID
    public let name: String
    public let locality: String?
    public let venue: PublicLeague.Venue?
    /// What a league published about the team.
    public let seasons: [SeasonLine]
    public let roster: [Member]
    public let yourRole: String?
    /// What the team says about itself. Optional: a server from before V039 does not send it.
    public let saysItPlaysIn: [LeagueSaid]?
    /// True when one of the team's own players took it on (PD-047) rather than anybody appointing them,
    /// which the front says in those words. Optional: a server from before V038 does not send it.
    public let adopted: Bool?
}

public struct TeamInvite: Decodable, Sendable, Equatable {
    public let code: String
    public let expiresAt: Date
    public let maxUses: Int
    public var spoken: String { code.count == 8 ? String(code.prefix(4)) + " " + String(code.suffix(4)) : code }
}

/// A friend: somebody who gave you their code, or took yours. Display name only.
public struct Friend: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: UUID
    public let displayName: String
    public let since: Date
    public var id: UUID { accountId }
    public init(accountId: UUID, displayName: String, since: Date) { self.accountId = accountId; self.displayName = displayName; self.since = since }
}

public struct FriendInvite: Decodable, Sendable, Equatable {
    public let code: String
    public let expiresAt: Date
    public init(code: String, expiresAt: Date) { self.code = code; self.expiresAt = expiresAt }
    /// "ABCD EFGH": how a code is read out.
    public var spoken: String { code.count == 8 ? String(code.prefix(4)) + " " + String(code.suffix(4)) : code }
}

/// A code for the other seat of a match this person sent (PD-043): seven days, one use, said across
/// the table or shared, and entered on the other player's own phone.
public struct MatchCode: Decodable, Sendable, Equatable {
    public let code: String
    public let seat: String
    public let expiresAt: Date
    public init(code: String, seat: String, expiresAt: Date) { self.code = code; self.seat = seat; self.expiresAt = expiresAt }
    /// "ABCD EFGH": how a code is read out.
    public var spoken: String { code.count == 8 ? String(code.prefix(4)) + " " + String(code.suffix(4)) : code }
}

/// A match on THRØ once it has been sent (PD-043), as the person reading it sits in it. All of it is
/// the server's reading of the log at the moment it was asked — the legs, the winner, the standing —
/// so the phone shows it and keeps none of it as truth.
public struct MatchOnRecord: Decodable, Sendable, Equatable, Identifiable {
    public struct SeatLine: Decodable, Sendable, Equatable {
        public let seat: String
        /// The seat the reader sits in.
        public let you: Bool
        /// Their name, only where THRØ may show it. Nil otherwise, and never guessed at.
        public let name: String?
        /// Nobody holds this seat yet, so the player who sent the match can give a code for it.
        public let claimable: Bool
        public init(seat: String, you: Bool, name: String?, claimable: Bool) {
            self.seat = seat; self.you = you; self.name = name; self.claimable = claimable
        }
    }

    public struct Format: Decodable, Sendable, Equatable {
        public let startingScore: Int
        public let inRule: String
        public let outRule: String
        public let legsMode: String
        public let legsTarget: Int
        /// Who threw first, which a replay of the match needs. Optional, so a server from before it
        /// was sent still decodes; a match that cannot be replayed is shown without its board.
        public let throwFirst: String?
        public init(startingScore: Int, inRule: String, outRule: String, legsMode: String, legsTarget: Int,
                    throwFirst: String? = nil) {
            self.startingScore = startingScore; self.inRule = inRule; self.outRule = outRule
            self.legsMode = legsMode; self.legsTarget = legsTarget; self.throwFirst = throwFirst
        }
    }

    public struct Legs: Decodable, Sendable, Equatable {
        public let home: Int
        public let away: Int
        public init(home: Int, away: Int) { self.home = home; self.away = away }
    }

    /// Each seat's latest answer where it still answers for the record: `confirmed`, `contested`, or nil.
    public struct Answers: Decodable, Sendable, Equatable {
        public let home: String?
        public let away: String?
        public init(home: String?, away: String?) { self.home = home; self.away = away }
    }

    public let matchId: UUID
    public let openedAt: Date
    public let format: Format
    public let selfReported: Bool
    public let seats: [SeatLine]
    public let legs: Legs
    public let visits: Int
    /// `retired` or `abandoned` when the match ended short; nil when it did not.
    public let ending: String?
    /// The seat that retired, when one did.
    public let retired: String?
    public let winner: String?
    /// The seat whose player sent it; nil for a match scored on THRØ as it was played.
    public let sentBy: String?
    public let answers: Answers
    /// `self-reported`, `confirmed`, `disputed`, or `recorded`.
    public let standing: String
    public var id: UUID { matchId }

    public init(matchId: UUID, openedAt: Date, format: Format, selfReported: Bool, seats: [SeatLine], legs: Legs,
                visits: Int, ending: String?, retired: String?, winner: String?, sentBy: String?, answers: Answers, standing: String) {
        self.matchId = matchId; self.openedAt = openedAt; self.format = format; self.selfReported = selfReported
        self.seats = seats; self.legs = legs; self.visits = visits; self.ending = ending; self.retired = retired
        self.winner = winner; self.sentBy = sentBy; self.answers = answers; self.standing = standing
    }

    public var yours: SeatLine? { seats.first { $0.you } }
    public var theirs: SeatLine? { seats.first { !$0.you } }
    /// The reader sent it: their word is the match, and the other seat is theirs to give a code for.
    public var youSent: Bool { sentBy != nil && yours?.seat == sentBy }
    public var canGiveCode: Bool { youSent && selfReported && theirs?.claimable == true }
    /// The reader is the other player, and there is a result for them to answer for.
    public var canAnswer: Bool { selfReported && !youSent && yours != nil && ending != "abandoned" }
    public var yourAnswer: String? { yours.flatMap { $0.seat == "home" ? answers.home : answers.away } }
    public var yourLegs: Int { yours?.seat == "away" ? legs.away : legs.home }
    public var theirLegs: Int { yours?.seat == "away" ? legs.home : legs.away }
    /// Nil when nobody won: the match is unfinished, or was abandoned.
    public var youWon: Bool? { winner.map { $0 == yours?.seat } }
}

public struct DiscoveryCard: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: UUID
    public let name: String
    public let tournament: String?
    public let venue: String?
    public let locality: String?
    public let startsAt: Date
    public let entriesCloseAt: Date?
    public let entrantKind: String
    public let access: String
    public let capacity: Int?
    public let spotsRemaining: Int?
    public let entered: Bool
    public let qualifies: Bool
    public let series: [String]
    /// Every card says why it is there; the screen shows these and invents nothing.
    public let reasons: [String]
    public var id: UUID { eventId }
}

public enum Provider: String, Sendable { case apple, google }

public enum APIError: Error, Equatable, Sendable {
    /// The server answered with a status this call does not accept, and what it said.
    case status(Int, String)
    /// No session, or a session the server no longer honours; the person signs in again.
    case signedOut
    /// The request never got an answer.
    case unreachable(String)
    /// An answer this build cannot read.
    case malformed(String)

    /// Words for the screen. Never a status code on its own.
    public var message: String {
        switch self {
        case .status(let code, let body):
            if let why = APIError.errorField(body) { return why }
            return code == 429 ? "Too many attempts. Wait a minute and try again." : "The server answered \(code)."
        case .signedOut: return "You are signed out. Sign in again to continue."
        case .unreachable(let why): return "THRØ could not be reached: \(why)"
        case .malformed(let why): return "THRØ answered in a way this build cannot read: \(why)"
        }
    }

    static func errorField(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["error"] as? String) ?? (obj["why"] as? String)
    }
}

/// How bytes reach the server. `URLSession` in the app; a scripted fake in tests.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable("not an HTTP response") }
        return (data, http)
    }
}

/// The result of a passkey registration ceremony, as the platform hands it back.
public struct PasskeyRegistration: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data
    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID; self.clientDataJSON = clientDataJSON; self.attestationObject = attestationObject
    }
}

public struct PasskeyAssertion: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data) {
        self.credentialID = credentialID; self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData; self.signature = signature
    }
}

/// What the server asks the platform to do before a passkey is created.
public struct PasskeyCreationOptions: Sendable, Equatable {
    public let challengeId: String
    public let challenge: Data
    public let relyingParty: String
    public let userID: Data
    public let userName: String
}

public struct PasskeyRequestOptions: Sendable, Equatable {
    public let challengeId: String
    public let challenge: Data
    public let relyingParty: String
}

/// The client. One per app; holds the session and refreshes it behind every authorised call.
public actor ThroAPI {
    public let configuration: ServerConfiguration
    public let deviceId: UUID
    private let store: SessionStore
    private let transport: Transport
    private let now: @Sendable () -> Date
    public private(set) var session: Session?

    public init(configuration: ServerConfiguration, deviceId: UUID, store: SessionStore,
                transport: Transport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.deviceId = deviceId
        self.store = store
        self.transport = transport
        self.now = now
        self.session = store.load()
    }

    public var isSignedIn: Bool { session != nil }

    // MARK: sign-in

    /// A provider's ID token becomes THRØ's session. With a session already held, an unheld
    /// subject is added to that account instead (PD-032: a second way in).
    ///
    /// **[nonce] is not optional in practice.** Both providers put the nonce the client gave them
    /// into the token they hand back — Apple the SHA-256 of it, Google the value — and the server
    /// refuses a token carrying a nonce it was given nothing to compare against, because a token
    /// replayed from somewhere else carries a nonce too. Omitting it here is what made every
    /// sign-in fail with *"the token carries a nonce and the request did not say which"*: the
    /// ceremony generated a nonce, handed it to the provider, and then threw it away.
    public func signIn(_ provider: Provider, idToken: String, nonce: String? = nil) async throws -> Session {
        var fields: [String: Any] = ["idToken": idToken, "deviceId": deviceId.uuidString.lowercased()]
        if let nonce { fields["nonce"] = nonce }
        let body = try JSONSerialization.data(withJSONObject: fields)
        let (data, http) = try await send("POST", "/v1/auth/\(provider.rawValue)", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    /// Revokes the session's family on the server and forgets it here whatever the server says:
    /// a sign-out that could fail would leave a person holding a token they asked to drop.
    /// What the server did with a match that was sent to it (PD-040).
    public struct Sent: Decodable, Sendable, Equatable {
        public let matchId: UUID
        public let opponentId: UUID
        public let visits: Int
        public let retractions: Int
        /// Rows THRØ already had: a resend, or the second half of one that stopped.
        public let alreadyHeld: Int
        public let opened: Bool
        public let selfReported: Bool
        /// How the match ended, when this send stored its ending: `retired` or `abandoned` (V034).
        /// Optional, so an answer from a server that predates endings still reads.
        public let ending: String?

        public init(matchId: UUID, opponentId: UUID, visits: Int, retractions: Int,
                    alreadyHeld: Int, opened: Bool, selfReported: Bool, ending: String? = nil) {
            self.matchId = matchId; self.opponentId = opponentId
            self.visits = visits; self.retractions = retractions
            self.alreadyHeld = alreadyHeld; self.opened = opened; self.selfReported = selfReported
            self.ending = ending
        }
    }

    /// One row of the device's journal, on the wire exactly as it is in the journal.
    public struct UploadRow: Encodable, Sendable, Equatable {
        public let deviceSeq: Int64
        public let kind: String
        public let seat: String
        public let visitTotal: Int?
        public let correctsSeq: Int64?
        public let occurredAt: String
        public let occurredTz: String

        public init(deviceSeq: Int64, kind: String, seat: String, visitTotal: Int?,
                    correctsSeq: Int64?, occurredAt: String, occurredTz: String) {
            self.deviceSeq = deviceSeq; self.kind = kind; self.seat = seat
            self.visitTotal = visitTotal; self.correctsSeq = correctsSeq
            self.occurredAt = occurredAt; self.occurredTz = occurredTz
        }
    }

    /// The format, in the words the server's contract uses.
    public struct UploadFormat: Encodable, Sendable, Equatable {
        public let startingScore: Int
        public let inRule: String
        public let outRule: String
        public let legsMode: String
        public let legsTarget: Int
        public let throwFirst: String

        public init(startingScore: Int, inRule: String, outRule: String,
                    legsMode: String, legsTarget: Int, throwFirst: String) {
            self.startingScore = startingScore; self.inRule = inRule; self.outRule = outRule
            self.legsMode = legsMode; self.legsTarget = legsTarget; self.throwFirst = throwFirst
        }
    }

    /// Send a match this phone scored (PD-040).
    ///
    /// Safe to call again with the same rows: the server is unique on (match, device, deviceSeq), so
    /// a resend after a dropped connection adds only what is missing. That is why this needs no
    /// bookkeeping on the phone about how far it got.
    public func sendMatch(matchId: UUID, deviceId: UUID, seat: String,
                          format: UploadFormat, rows: [UploadRow]) async throws -> Sent {
        struct Body: Encodable {
            let matchId: UUID, deviceId: UUID, seat: String
            let format: UploadFormat, rows: [UploadRow]
        }
        let encoder = JSONEncoder()
        let body = try encoder.encode(Body(matchId: matchId, deviceId: deviceId, seat: seat, format: format, rows: rows))
        return try decode(await authorised("POST", "/v1/matches", body: body))
    }

    /// What an erasure destroyed. Counts, because there is nothing else left to report.
    public struct Erasure: Decodable, Sendable, Equatable {
        public let credentials: Int
        public let sessions: Int
        public let devices: Int
        public let friendships: Int
        public let claims: Int
        public let consents: Int
    }

    /// Erase this account and everything that identifies its owner (V031).
    ///
    /// The session is dead on the server the instant this returns, so it is forgotten here too —
    /// including when the answer is an error, because the one outcome worse than a failed erasure
    /// is a phone that carries on acting signed in to an account that has gone.
    public func eraseAccount() async throws -> Erasure {
        do {
            // **`authorised`, like every other call on this account.** The first version reached
            // for `send` with the bearer directly, which skipped the one thing `authorised` is for:
            // a refresh when the access token has aged out. Access tokens are short, so erasing
            // worked immediately after signing in and answered 401 an hour later — and the 401 was
            // then read as "already gone", which signed the phone out and left the account standing.
            // That is the whole of "doesn't work every time".
            //
            // The body is `{}` rather than nothing: the server used to demand a Content-Length on
            // every non-GET and answered a bodyless DELETE with 411. That is fixed, but a phone in
            // somebody's pocket meets whatever is deployed, and two bytes cost nothing.
            let data = try await authorised("DELETE", "/v1/me", body: Data("{}".utf8))
            session = nil
            store.clear()
            return try Wire.decoder.decode(Erasure.self, from: data)
        } catch {
            // A 401 that survived `authorised` means the refresh failed too, so the session really
            // is dead; a 409 means the account is already gone. **Nothing else clears the session**:
            // doing that on, say, a 411 signed the phone out while the account was still there, so
            // the erasure looked like it had happened and had not.
            if case APIError.status(let code, _) = error, code == 401 || code == 409 {
                session = nil
                store.clear()
            }
            throw error
        }
    }

    public func signOut() async {
        if let s = session {
            _ = try? await send("POST", "/v1/auth/logout", body: Data("{}".utf8), bearer: s.accessToken)
        }
        session = nil
        store.clear()
    }

    // MARK: passkeys

    public func passkeyCreationOptions() async throws -> PasskeyCreationOptions {
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/passkey/register/options", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeId = obj["challengeId"] as? String,
              let pk = obj["publicKey"] as? [String: Any],
              let challenge = (pk["challenge"] as? String).flatMap(Base64URL.decode),
              let rp = (pk["rp"] as? [String: Any])?["id"] as? String,
              let user = pk["user"] as? [String: Any],
              let userID = (user["id"] as? String).flatMap(Base64URL.decode),
              let userName = user["name"] as? String
        else { throw APIError.malformed("passkey creation options") }
        return PasskeyCreationOptions(challengeId: challengeId, challenge: challenge, relyingParty: rp, userID: userID, userName: userName)
    }

    public func registerPasskey(_ options: PasskeyCreationOptions, _ result: PasskeyRegistration) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: [
            "challengeId": options.challengeId, "deviceId": deviceId.uuidString.lowercased(),
            "credentialId": Base64URL.encode(result.credentialID),
            "clientDataJSON": Base64URL.encode(result.clientDataJSON),
            "attestationObject": Base64URL.encode(result.attestationObject),
        ])
        let (data, http) = try await send("POST", "/v1/auth/passkey/register", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    public func passkeyRequestOptions() async throws -> PasskeyRequestOptions {
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/passkey/options", body: body, bearer: nil)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeId = obj["challengeId"] as? String,
              let pk = obj["publicKey"] as? [String: Any],
              let challenge = (pk["challenge"] as? String).flatMap(Base64URL.decode),
              let rp = pk["rpId"] as? String
        else { throw APIError.malformed("passkey request options") }
        return PasskeyRequestOptions(challengeId: challengeId, challenge: challenge, relyingParty: rp)
    }

    public func signInWithPasskey(_ options: PasskeyRequestOptions, _ result: PasskeyAssertion) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: [
            "challengeId": options.challengeId, "deviceId": deviceId.uuidString.lowercased(),
            "credentialId": Base64URL.encode(result.credentialID),
            "clientDataJSON": Base64URL.encode(result.clientDataJSON),
            "authenticatorData": Base64URL.encode(result.authenticatorData),
            "signature": Base64URL.encode(result.signature),
        ])
        let (data, http) = try await send("POST", "/v1/auth/passkey", body: body, bearer: nil)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    // MARK: the signed-in person

    public func me() async throws -> Profile { try decode(await authorised("GET", "/v1/me")) }

    public func setDisplayName(_ name: String) async throws -> Profile {
        let body = try JSONSerialization.data(withJSONObject: ["displayName": name])
        return try decode(await authorised("PUT", "/v1/me/profile", body: body))
    }

    /// The account says its own age band (adult or minor, self-declared). Adult is what unlocks friends.
    public func declareAge(adult: Bool) async throws -> Profile {
        let body = try JSONSerialization.data(withJSONObject: ["ageBand": adult ? "adult" : "minor"])
        return try decode(await authorised("PUT", "/v1/me/profile", body: body))
    }

    public func friends() async throws -> [Friend] {
        struct Envelope: Decodable { let friends: [Friend] }
        return try (decode(await authorised("GET", "/v1/friends")) as Envelope).friends
    }

    /// A code to give somebody in person. A refusal (not an adult account) arrives as `.status(403, body)`.
    public func inviteFriend() async throws -> FriendInvite { try decode(await authorised("POST", "/v1/friends/invite")) }

    public func acceptFriend(code: String) async throws -> Friend {
        struct Envelope: Decodable { let friend: Friend }
        let body = try JSONSerialization.data(withJSONObject: ["code": code])
        return try (decode(await authorised("POST", "/v1/friends/accept", body: body)) as Envelope).friend
    }

    public func removeFriend(_ accountId: UUID) async throws {
        _ = try await authorised("POST", "/v1/friends/\(accountId.uuidString.lowercased())/remove")
    }

    /// The sentence inside a refusal's body, for the screen; the status text otherwise.
    public static func refusal(_ error: Error) -> String? {
        guard case APIError.status(_, let body) = error,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let why = object["error"] as? String else { return nil }
        return why
    }

    public func inbox() async throws -> [String: [InboxItem]] {
        struct Envelope: Decodable { let sections: [String: [InboxItem]] }
        return try (decode(await authorised("GET", "/v1/me/inbox")) as Envelope).sections
    }

    public func discovery(locality: String? = nil) async throws -> [String: [DiscoveryCard]] {
        struct Envelope: Decodable { let sections: [String: [DiscoveryCard]] }
        var path = "/v1/me/discovery"
        if let locality, let q = locality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "?locality=\(q)" }
        return try (decode(await authorised("GET", path)) as Envelope).sections
    }

    /// The leagues' public front (PD-033): no session needed, so a phone that has never signed in
    /// can still see who plays where. A locality narrows it to leagues in that town.
    public func leagues(locality: String? = nil) async throws -> [PublicLeague] {
        struct Envelope: Decodable { let leagues: [PublicLeague] }
        var path = "/v1/leagues"
        if let locality, let q = locality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "?locality=\(q)" }
        let (data, http) = try await send("GET", path, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try (decode(data) as Envelope).leagues
    }

    /// A league season's table (PD-054). No session needed: a league's published competition is public.
    ///
    /// Computed by the server on every read from the fixtures beneath it, so what arrives cannot disagree
    /// with the results — and the phone renders `position` as given rather than sorting again, or the two
    /// would eventually order a table differently in front of the same person.
    public func standings(season: UUID, division: UUID? = nil) async throws -> LeagueStandings {
        var path = "/v1/seasons/\(season.uuidString.lowercased())/standings"
        if let division { path += "?division=\(division.uuidString.lowercased())" }
        let (data, http) = try await send("GET", path, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try decode(data)
    }

    /// Open-entry events that have not started (the notice on the pub door). No session needed.
    public func events() async throws -> [PublicEvent] {
        struct Envelope: Decodable { let events: [PublicEvent] }
        let (data, http) = try await send("GET", "/v1/events", bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try (decode(data) as Envelope).events
    }

    // MARK: teams (plan §6)

    public func myTeams() async throws -> [TeamSummary] {
        struct Envelope: Decodable { let teams: [TeamSummary] }
        return try (decode(await authorised("GET", "/v1/me/teams")) as Envelope).teams
    }

    public func createTeam(name: String, locality: String?) async throws -> TeamSummary {
        var object: [String: Any] = ["name": name]
        if let locality { object["locality"] = locality }
        let body = try JSONSerialization.data(withJSONObject: object)
        return try decode(await authorised("POST", "/v1/teams", body: body))
    }

    /// A team's public front. Sends the bearer when there is one, so `yourRole` can be answered.
    public func teamFront(_ teamId: UUID) async throws -> TeamFront {
        let (data, http) = try await send("GET", "/v1/teams/\(teamId.uuidString.lowercased())", bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try decode(data)
    }

    public func inviteToTeam(_ teamId: UUID) async throws -> TeamInvite {
        try decode(await authorised("POST", "/v1/teams/\(teamId.uuidString.lowercased())/invite"))
    }

    /// Public venues whose name contains the query. No session needed.
    public func venues(matching query: String, locality: String? = nil) async throws -> [PublicLeague.Venue] {
        struct Envelope: Decodable { let venues: [PublicLeague.Venue] }
        var path = "/v1/venues?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        if let locality, let l = locality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "&locality=\(l)" }
        let (data, http) = try await send("GET", path, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try (decode(data) as Envelope).venues
    }

    /// Sets a team's home: a venue by id, or a new one by name and town. Answers the team's front.
    public func setTeamHome(_ teamId: UUID, venueId: UUID?, name: String?, locality: String?) async throws -> TeamFront {
        var object: [String: Any] = [:]
        if let venueId { object["venueId"] = venueId.uuidString.lowercased() }
        if let name { object["name"] = name }
        if let locality { object["locality"] = locality }
        let body = try JSONSerialization.data(withJSONObject: object)
        return try decode(await authorised("POST", "/v1/teams/\(teamId.uuidString.lowercased())/home", body: body))
    }

    /// Takes on a listed league team nobody runs (PD-047): the caller becomes its admin, by their own
    /// say. A refusal arrives as `.status(403 or 409, body)` — adults only, only a team read from a
    /// league's pages, and only one nobody else runs.
    public func adoptTeam(_ teamId: UUID) async throws -> TeamSummary {
        try decode(await authorised("POST", "/v1/teams/\(teamId.uuidString.lowercased())/adopt", body: Data("{}".utf8)))
    }

    /// The team says which league it plays in (PD-049). Answers the team's front, carrying the say; a
    /// refusal arrives as `.status(403 or 404, body)` — only the admin or captain, only a league THRØ lists.
    public func sayLeague(_ teamId: UUID, leagueId: UUID) async throws -> TeamFront {
        let body = try JSONSerialization.data(withJSONObject: ["leagueId": leagueId.uuidString.lowercased()])
        return try decode(await authorised("POST", "/v1/teams/\(teamId.uuidString.lowercased())/league", body: body))
    }

    /// And stops saying it. The claim is kept on the server, marked withdrawn.
    public func stopSayingLeague(_ teamId: UUID, leagueId: UUID) async throws -> TeamFront {
        try decode(await authorised("DELETE", "/v1/teams/\(teamId.uuidString.lowercased())/league/\(leagueId.uuidString.lowercased())"))
    }

    /// What came back from raising a report (PD-050): when it is answered by, which is the promise the app
    /// makes on screen and the stores hold THRØ to.
    public struct ReportRaised: Decodable, Sendable, Equatable {
        public let reportId: UUID
        public let subjectKind: String
        public let subjectId: UUID
        public let urgent: Bool
        public let answerDueAt: Date
    }

    private struct BlockedAccounts: Decodable { let blocked: [UUID] }

    /// Reports something somebody wrote — a team, venue or league name, an account, or a match (PD-050).
    public func report(subjectKind: String, subjectId: UUID, reason: String) async throws -> ReportRaised {
        let body = try JSONSerialization.data(withJSONObject: ["subjectKind": subjectKind,
                                                               "subjectId": subjectId.uuidString.lowercased(),
                                                               "reason": reason])
        return try decode(await authorised("POST", "/v1/reports", body: body))
    }

    /// Asks not to be reached by an account. Answers the accounts you have blocked.
    public func block(_ accountId: UUID) async throws -> [UUID] {
        let body = try JSONSerialization.data(withJSONObject: ["accountId": accountId.uuidString.lowercased()])
        let answered: BlockedAccounts = try decode(await authorised("POST", "/v1/blocks", body: body))
        return answered.blocked
    }

    /// Lifts a block. The block is kept on the server, marked lifted.
    public func unblock(_ accountId: UUID) async throws -> [UUID] {
        let answered: BlockedAccounts = try decode(await authorised("DELETE", "/v1/blocks/\(accountId.uuidString.lowercased())"))
        return answered.blocked
    }

    public func blocks() async throws -> [UUID] {
        let answered: BlockedAccounts = try decode(await authorised("GET", "/v1/blocks"))
        return answered.blocked
    }

    /// Records that this account accepted a version of the terms, before it writes anything anyone reads.
    public func acceptTerms(_ version: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["version": version])
        _ = try await authorised("POST", "/v1/me/terms", body: body)
    }

    public func joinTeam(code: String) async throws -> TeamSummary {
        let body = try JSONSerialization.data(withJSONObject: ["code": code])
        return try decode(await authorised("POST", "/v1/teams/join", body: body))
    }

    /// The admin names a captain or vice-captain, or makes somebody a player again (PD-045). Answers
    /// the team's front as its admin reads it; a refusal arrives as `.status(403 or 422, body)`.
    public func assignRole(_ teamId: UUID, memberId: UUID, role: String) async throws -> TeamFront {
        let body = try JSONSerialization.data(withJSONObject: ["memberId": memberId.uuidString.lowercased(), "role": role])
        return try decode(await authorised("POST", "/v1/teams/\(teamId.uuidString.lowercased())/roles", body: body))
    }

    // MARK: a sent match, onward (PD-043)

    /// A code for the other seat of a match this person sent, to say across the table or share.
    /// Asking again while one is live hands back the same code.
    public func matchCode(_ matchId: UUID) async throws -> MatchCode {
        try decode(await authorised("POST", "/v1/matches/\(matchId.uuidString.lowercased())/code"))
    }

    /// Enter a code somebody gave you: the seat it was made for becomes yours. Answers the match as you
    /// now read it. A refusal — used, expired, your own — arrives as `.status(422, body)` with the sentence.
    public func claimMatch(code: String) async throws -> MatchOnRecord {
        let body = try JSONSerialization.data(withJSONObject: ["code": code])
        return try decode(await authorised("POST", "/v1/matches/claim", body: body))
    }

    /// One match this person played in, as the server reads its log now.
    public func match(_ matchId: UUID) async throws -> MatchOnRecord {
        try decode(await authorised("GET", "/v1/matches/\(matchId.uuidString.lowercased())"))
    }

    /// The matches this person played in — sent, or taken with a code — newest first.
    public func myMatches() async throws -> [MatchOnRecord] {
        struct Envelope: Decodable { let matches: [MatchOnRecord] }
        return try (decode(await authorised("GET", "/v1/me/matches")) as Envelope).matches
    }

    /// Confirm (`agree`) or contest a result somebody else sent. Answers the match with the answer counted.
    public func answerMatch(_ matchId: UUID, agree: Bool) async throws -> MatchOnRecord {
        let body = try JSONSerialization.data(withJSONObject: ["agree": agree])
        return try decode(await authorised("POST", "/v1/matches/\(matchId.uuidString.lowercased())/answer", body: body))
    }

    // MARK: plumbing

    /// An authorised call: bearer, one refresh on a 401, and a session that stops being honoured
    /// becomes `.signedOut` rather than a loop.
    private func authorised(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let current = session else { throw APIError.signedOut }
        var (data, http) = try await send(method, path, body: body, bearer: current.accessToken)
        if http.statusCode == 401 {
            try await refresh()
            guard let renewed = session else { throw APIError.signedOut }
            (data, http) = try await send(method, path, body: body, bearer: renewed.accessToken)
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// Rotates the refresh token. A refusal means the family is gone — reused, expired, or
    /// revoked — and the session is dropped so the person is told rather than retried.
    /// Internal rather than private: a match stream outlives an access token, and renews it here.
    func refresh() async throws {
        guard let current = session else { throw APIError.signedOut }
        let body = try JSONSerialization.data(withJSONObject: ["refreshToken": current.refreshToken, "deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/refresh", body: body, bearer: nil)
        guard http.statusCode == 200 else {
            session = nil
            store.clear()
            throw APIError.signedOut
        }
        _ = try adopt(data)
    }

    private func adopt(_ data: Data) throws -> Session {
        let s: Session = try decode(data)
        session = s
        store.save(s)
        return s
    }

    private func send(_ method: String, _ path: String, body: Data? = nil, bearer: String?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else { throw APIError.malformed("path \(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId.uuidString.lowercased(), forHTTPHeaderField: "X-Thro-Device")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        } else if method != "GET" {
            request.httpBody = Data()
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        do {
            return try await transport.send(request)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try Wire.decoder.decode(T.self, from: data) } catch { throw APIError.malformed(String(describing: error)) }
    }
}

/// The wire's conventions: base64url without padding, and ISO-8601 instants with or without fractions.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

public enum Wire {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO-8601 instant: \(s)"))
        }
        return d
    }()
}

/// PKCE for the Google flow: the verifier stays on the phone, its hash goes to the browser.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        self.init(verifierBytes: Data(bytes))
    }
    init(verifierBytes: Data) {
        verifier = Base64URL.encode(verifierBytes)
        challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Google's authorization-code flow for an iOS client, which has no secret: the code is exchanged
/// for an ID token straight from the phone, with the PKCE verifier proving it is the same phone.
public enum GoogleOAuth {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public static func redirectURI(for configuration: ServerConfiguration) -> String? {
        configuration.googleRedirectScheme.map { "\($0):/oauth2redirect" }
    }

    public static func authorizationURL(configuration: ServerConfiguration, pkce: PKCE, nonce: String) -> URL? {
        guard let clientID = configuration.googleClientID, let redirect = redirectURI(for: configuration) else { return nil }
        var c = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: pkce.challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "nonce", value: nonce),
        ]
        return c.url
    }

    /// The `code` from the callback URL, or nil when Google sent an error instead.
    public static func code(from callback: URL) -> String? {
        URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
    }

    public static func exchange(code: String, configuration: ServerConfiguration, pkce: PKCE, transport: Transport) async throws -> String {
        guard let clientID = configuration.googleClientID, let redirect = redirectURI(for: configuration) else { throw APIError.malformed("no Google client id") }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["code": code, "client_id": clientID, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": pkce.verifier]
        // Form encoding leaves the unreserved characters alone, so a base64url verifier travels as it is.
        var unreserved = CharacterSet.alphanumerics; unreserved.insert(charactersIn: "-._~")
        request.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }.joined(separator: "&").utf8)
        let (data, http) = try await transport.send(request)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = obj["id_token"] as? String else {
            throw APIError.malformed("Google's token answer carried no id_token")
        }
        return token
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
