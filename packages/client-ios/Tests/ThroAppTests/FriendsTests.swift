import Foundation
import XCTest
@testable import ThroApp
@testable import ThroNet

/// Friends on the phone (PD-035): the store's calls, what it keeps, and that every refusal the
/// server sends arrives on the screen as the server's own sentence.
@MainActor
final class FriendsTests: XCTestCase {

    private let config = ServerConfiguration(baseURL: URL(string: "https://api.example")!, googleClientID: nil)
    private let session = Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)

    private func store(_ answers: [(Int, String)]) -> (AccountStore, NetTests.Script) {
        let script = NetTests.Script(answers)
        let api = ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(session), transport: script)
        return (AccountStore(api: api, configuration: config, services: AccountTests.Ceremonies(), transport: script), script)
    }

    func testACodeIsMadeSharedAndSpokenInTwoHalves() async throws {
        let (account, script) = store([(200, #"{"code":"ABCDEFGH","expiresAt":"2026-09-17T20:00:00Z"}"#)])
        await account.makeInvite()
        XCTAssertEqual(account.invite?.code, "ABCDEFGH")
        XCTAssertEqual(account.invite?.spoken, "ABCD EFGH")
        XCTAssertNil(account.friendsNote)
        XCTAssertEqual(script.seen.first?.url?.path, "/v1/friends/invite")
        XCTAssertEqual(script.seen.first?.httpMethod, "POST")
    }

    func testARefusalArrivesAsTheServersOwnSentence() async {
        let (account, _) = store([(403, #"{"error":"Say you are 18 or over under Account and profile first. THRØ does not guess ages."}"#)])
        await account.makeInvite()
        XCTAssertNil(account.invite)
        XCTAssertEqual(account.friendsNote, "Say you are 18 or over under Account and profile first. THRØ does not guess ages.")
    }

    func testEnteringACodeAddsTheFriendAtTheTopAndAUsedCodeSaysSo() async {
        let (account, script) = store([
            (200, #"{"friends":[{"accountId":"cccccccc-0000-0000-0000-000000000003","displayName":"Ethan T.","since":"2026-09-01T10:00:00Z"}]}"#),
            (200, #"{"friend":{"accountId":"dddddddd-0000-0000-0000-000000000004","displayName":"Jenson R.","since":"2026-09-10T20:00:00Z"}}"#),
            (409, #"{"error":"That code has been used already. Ask for a new one."}"#),
        ])
        await account.loadFriends()
        XCTAssertEqual(account.friends?.map(\.displayName), ["Ethan T."])
        let ok = await account.acceptCode("abcd efgh")
        XCTAssertTrue(ok)
        XCTAssertEqual(account.friends?.map(\.displayName), ["Jenson R.", "Ethan T."])
        let body = script.seen[1].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(body?["code"], "abcd efgh", "the server normalises; the phone sends what was typed")
        let again = await account.acceptCode("ABCDEFGH")
        XCTAssertFalse(again)
        XCTAssertEqual(account.friendsNote, "That code has been used already. Ask for a new one.")
        XCTAssertEqual(account.friends?.count, 2, "a refusal changes nothing")
    }

    func testRemovingAFriendTakesThemOffTheListAndTellsTheServer() async {
        let friend = Friend(accountId: UUID(), displayName: "Ethan T.", since: Date())
        let (account, script) = store([(200, #"{"friends":[]}"#), (200, #"{"removed":true}"#)])
        await account.loadFriends()
        await account.removeFriend(friend)
        XCTAssertEqual(account.friends, [])
        XCTAssertEqual(script.seen.last?.url?.path, "/v1/friends/\(friend.accountId.uuidString.lowercased())/remove")
    }

    func testDeclaringAdultUpdatesTheProfileAndSigningOutForgetsFriends() async {
        let (account, script) = store([
            (200, #"{"accountId":"aaaaaaaa-0000-0000-0000-000000000001","playerId":null,"displayName":"Player","named":false,"ageBand":"adult","credentials":1}"#),
            (200, #"{"friends":[]}"#), (200, "{}"),
        ])
        await account.declareAdult()
        XCTAssertEqual(account.profile?.ageBand, "adult")
        let body = script.seen[0].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(body?["ageBand"], "adult")
        await account.loadFriends()
        XCTAssertEqual(account.friends, [])
        await account.signOut()
        XCTAssertNil(account.friends); XCTAssertNil(account.invite)
    }

    func testACodeFieldIgnoresCaseSpacesAndDashes() {
        XCTAssertEqual(FriendsScreen.normalised(" abcd-efgh "), "ABCDEFGH")
        XCTAssertEqual(FriendsScreen.normalised("ABCD EFGH").count, 8)
    }

    func testTheYouSlateSaysWhoYouAreOrOffersTheDoor() {
        XCTAssertEqual(YouScreen.words(.signedOut).title, "Sign in to carry your darts with you")
        XCTAssertEqual(YouScreen.words(.signedIn(name: "Jenson R.", ageBand: "adult", friends: 1)).detail, "18 or over · 1 friend")
        XCTAssertEqual(YouScreen.words(.signedIn(name: nil, ageBand: "unknown", friends: nil)).title, "No name yet")
        XCTAssertEqual(YouScreen.words(.signedIn(name: nil, ageBand: "unknown", friends: nil)).detail, "Age not said yet · Friends")
        XCTAssertEqual(YouScreen.words(.none).detail, "This build names no server, so what you score stays here.")
    }
}
