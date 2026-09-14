import Foundation

// The phone's side of ADR-007: server-sent events parsed frame by frame, ids kept so a reconnect
// resumes from the log, and staleness decided by the phone's own clock — a stream that has said
// nothing for 45 seconds is stale whatever the socket believes.

/// One frame of a match stream.
public struct StreamEvent: Sendable, Equatable {
    public let id: String
    public let type: String
    public let data: String
}

/// Bytes into lines as the wire has them — **empty lines included**.
///
/// The first version read `URLSession.AsyncBytes.lines`, and that sequence never yields an empty
/// line: fed `data: x`, an empty line and `: ping`, it hands over two lines, not three. An empty line
/// is what ends an event, so the parser under it could never complete one and no event would ever
/// have reached a screen. Nothing had tuned in yet, which is the only reason nobody saw it; it was
/// found by feeding that sequence a wire before building the screen that would have.
public struct SSELineSplitter: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// Feeds one byte. Returns the line it completes — without its newline, or a carriage return
    /// before one — or nil.
    public mutating func feed(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else { buffer.append(byte); return nil }
        if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// The wire format, one line at a time. `feed` returns the events completed by the line; a
/// comment line (`: ping`) completes nothing but is a sign of life the caller times.
public struct SSEParser: Sendable {
    private var id = ""
    private var type = ""
    private var data: [String] = []
    public private(set) var lastEventId: String?

    public init(lastEventId: String? = nil) { self.lastEventId = lastEventId }

    /// Feeds one line (without its newline). Returns a completed event, or nil.
    public mutating func feed(_ line: String) -> StreamEvent? {
        if line.isEmpty {
            guard !data.isEmpty else { id = ""; type = ""; return nil }
            let event = StreamEvent(id: id, type: type, data: data.joined(separator: "\n"))
            if !id.isEmpty { lastEventId = id }
            id = ""; type = ""; data = []
            return event
        }
        if line.hasPrefix(":") { return nil }
        let (field, value): (String, String) = {
            guard let colon = line.firstIndex(of: ":") else { return (line, "") }
            var v = String(line[line.index(after: colon)...])
            if v.hasPrefix(" ") { v.removeFirst() }
            return (String(line[..<colon]), v)
        }()
        switch field {
        case "id": id = value
        case "event": type = value
        case "data": data.append(value)
        default: break   // retry and unknown fields are the transport's business
        }
        return nil
    }
}

/// What the stream is doing, for a screen that must never say "live" about a frozen feed.
public enum StreamHealth: Sendable, Equatable { case connecting, live, stale, ended(String) }

/// What a match stream hands its reader: an event from the log, or a change in how the stream is.
public enum MatchStreamUpdate: Sendable, Equatable {
    case event(StreamEvent)
    case health(StreamHealth)
}

public extension ThroAPI {
    /// The staleness deadline ADR-007 fixes: three missed heartbeats.
    static var staleAfter: TimeInterval { 45 }

    /// Said when a stream ends because nobody is signed in to follow it.
    static var signedOutToFollow: String { "You are signed out. Sign in again to follow this match." }

    /// A match's evidence, live. Reconnects with `Last-Event-ID` until the task is cancelled, and says
    /// how it is as it goes: connecting, live, stale — nothing, not even a ping, for `staleAfter`, and
    /// reconnecting — or ended, with the sentence a person is shown. The transport is `URLSession`
    /// bytes here rather than [Transport], because a stream is not one answer.
    ///
    /// Besides the lines, the first version never said how the stream was, though its doc promised
    /// to, and a 401 ended it: an access token is short and a watch is not, so it renews once now.
    func matchStream(_ matchId: UUID, session urlSession: URLSession = .shared) -> AsyncStream<MatchStreamUpdate> {
        AsyncStream { continuation in
            let task = Task {
                var lastId: String? = nil
                var renewed = false
                reconnecting: while !Task.isCancelled {
                    guard let current = self.session else {
                        continuation.yield(.health(.ended(ThroAPI.signedOutToFollow)))
                        break
                    }
                    var request = URLRequest(url: self.configuration.baseURL.appendingPathComponent("v1/streams/match/\(matchId.uuidString.lowercased())"))
                    request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(self.deviceId.uuidString.lowercased(), forHTTPHeaderField: "X-Thro-Device")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let lastId { request.setValue(lastId, forHTTPHeaderField: "Last-Event-ID") }
                    // The idle timeout is the staleness deadline: the server pings every fifteen seconds,
                    // so forty-five with nothing at all means the stream is stale, and the request gives up.
                    request.timeoutInterval = ThroAPI.staleAfter
                    continuation.yield(.health(.connecting))
                    do {
                        let (bytes, response) = try await urlSession.bytes(for: request)
                        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
                        case 200:
                            renewed = false
                        case 401:
                            if !renewed {
                                renewed = true
                                if (try? await self.refresh()) != nil { continue reconnecting }
                            }
                            continuation.yield(.health(.ended(ThroAPI.signedOutToFollow)))
                            break reconnecting
                        case 403:
                            continuation.yield(.health(.ended("This match is not yours to follow.")))
                            break reconnecting
                        case 404:
                            continuation.yield(.health(.ended("THRØ does not have this match.")))
                            break reconnecting
                        default:
                            continuation.yield(.health(.stale))
                            try await Task.sleep(nanoseconds: 3_000_000_000)
                            continue reconnecting
                        }
                        continuation.yield(.health(.live))
                        var lines = SSELineSplitter()
                        var parser = SSEParser(lastEventId: lastId)
                        for try await byte in bytes {
                            guard let line = lines.feed(byte) else { continue }
                            if let event = parser.feed(line) { continuation.yield(.event(event)) }
                            // The parser's, not the event's: an event with no id must not wipe the place
                            // a reconnect resumes from.
                            lastId = parser.lastEventId
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.health(.stale))
                    }
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
