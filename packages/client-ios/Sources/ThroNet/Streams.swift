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

public extension ThroAPI {
    /// The staleness deadline ADR-007 fixes: three missed heartbeats.
    static var staleAfter: TimeInterval { 45 }

    /// A match's evidence, live. Reconnects with `Last-Event-ID` until the task is cancelled;
    /// yields events and health changes; a stream quiet for `staleAfter` is reported stale and
    /// reconnected. The transport is `URLSession` bytes here rather than [Transport], because a
    /// stream is not one answer.
    func matchStream(_ matchId: UUID, session urlSession: URLSession = .shared) -> AsyncStream<Result<StreamEvent, APIError>> {
        AsyncStream { continuation in
            let task = Task {
                var lastId: String? = nil
                while !Task.isCancelled {
                    guard let current = await self.session else { continuation.yield(.failure(.signedOut)); break }
                    var request = URLRequest(url: self.configuration.baseURL.appendingPathComponent("v1/streams/match/\(matchId.uuidString.lowercased())"))
                    request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(self.deviceId.uuidString.lowercased(), forHTTPHeaderField: "X-Thro-Device")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let lastId { request.setValue(lastId, forHTTPHeaderField: "Last-Event-ID") }
                    request.timeoutInterval = ThroAPI.staleAfter
                    do {
                        let (bytes, response) = try await urlSession.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                            continuation.yield(.failure(.status(code, "")))
                            if code == 401 || code == 403 || code == 404 { break }
                            try await Task.sleep(nanoseconds: 3_000_000_000); continue
                        }
                        var parser = SSEParser(lastEventId: lastId)
                        for try await line in bytes.lines {
                            if let event = parser.feed(line) { lastId = event.id; continuation.yield(.success(event)) }
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.failure(.unreachable(error.localizedDescription)))
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
