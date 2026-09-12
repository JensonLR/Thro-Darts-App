import XCTest
@testable import ThroApp
@testable import ThroNet

/// The phone's model of the caller's server teams (PD-036). Its front is one slot, and the first
/// version loaded that slot only while it was empty — so after one team had been opened, opening a
/// second showed the first. Scripted server, no device.
@MainActor
final class TeamsModelTests: XCTestCase {

    private let config = ServerConfiguration(baseURL: URL(string: "https://api.example")!, googleClientID: nil)

    private func front(_ id: UUID, _ name: String) -> String {
        #"{"teamId":"\#(id.uuidString.lowercased())","name":"\#(name)","locality":null,"venue":null,"seasons":[],"roster":[],"yourRole":null}"#
    }

    private func api(_ script: NetTests.Script) -> ThroAPI {
        ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(), transport: script)
    }

    func testOpeningASecondTeamShowsTheSecondTeamAndNotTheFirst() async {
        let feathers = UUID(), bell = UUID()
        let script = NetTests.Script([(200, front(feathers, "The Feathers A")), (200, front(bell, "The Bell B"))])
        let teams = TeamsModel(), server = api(script)

        await teams.show(feathers, server)
        guard case .loaded(let first) = teams.front(for: feathers) else { return XCTFail("\(teams.front)") }
        XCTAssertEqual(first.name, "The Feathers A")

        // The defect, in one line: while the Feathers are held, the Bell's page must not show them.
        XCTAssertEqual(teams.front(for: bell), .loading, "another team's front is never shown as this one's")
        await teams.show(bell, server)
        guard case .loaded(let second) = teams.front(for: bell) else { return XCTFail("\(teams.front)") }
        XCTAssertEqual(second.name, "The Bell B")
        XCTAssertEqual(teams.front(for: feathers), .loading, "and back to the first is a fresh load, not the second")
    }

    func testTheAdminNamesACaptainAndTheFrontComesBackAsTheAdminReadsIt() async throws {
        let bell = UUID(), ethan = UUID()
        let named = #"{"teamId":"\#(bell.uuidString.lowercased())","name":"The Bell B","locality":null,"venue":null,"seasons":[],"roster":[{"name":"Jenson R.","role":"admin","memberId":"\#(UUID().uuidString.lowercased())"},{"name":"Ethan T.","role":"captain","memberId":"\#(ethan.uuidString.lowercased())"}],"yourRole":"admin"}"#
        let script = NetTests.Script([(200, named)])
        let session = Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)
        let server = ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(session), transport: script)
        let teams = TeamsModel()
        await teams.assign(bell, memberId: ethan, role: "captain", server)
        XCTAssertEqual(script.seen.first?.url?.path, "/v1/teams/\(bell.uuidString.lowercased())/roles")
        let body = try XCTUnwrap(script.seen.first?.httpBody).flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(body?["role"], "captain")
        XCTAssertEqual(body?["memberId"], ethan.uuidString.lowercased())
        guard case .loaded(let front) = teams.front(for: bell) else { return XCTFail("\(teams.front)") }
        XCTAssertEqual(front.roster.map(\.role), ["admin", "captain"], "the front the server answered is the one shown")
        XCTAssertEqual(front.roster.last?.memberId, ethan)
        XCTAssertEqual(TeamFrontScreen.assignable, ["captain", "vice_captain", "player"], "the admin is never one of the roles on offer")
        XCTAssertEqual(TeamFrontScreen.assignable.map(TeamFrontScreen.roleLabel), ["Captain", "Vice-captain", "Player"])
    }

    func testShowingTheTeamAlreadyHeldAsksTheServerNothing() async {
        let feathers = UUID()
        let script = NetTests.Script([(200, front(feathers, "The Feathers A"))])
        let teams = TeamsModel(), server = api(script)
        await teams.show(feathers, server)
        await teams.show(feathers, server)
        XCTAssertEqual(script.seen.count, 1, "one team, one read")
    }
}
