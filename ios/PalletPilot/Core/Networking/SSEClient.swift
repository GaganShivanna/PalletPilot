import Foundation

/// One parsed Server-Sent Events frame. `data` is the raw JSON envelope
/// (`JobEvent`); comment/keepalive lines never surface here.
struct ServerSentEvent: Sendable, Equatable {
    var id: Int?
    var eventType: String?
    var data: String
}

/// Minimal SSE client for `GET /jobs/{job_id}/events`. Matches the backend
/// contract: `id:`/`event:`/`data:` frames, `: keepalive` comments, resume
/// via `Last-Event-ID`, server closes after the terminal event. Delivery is
/// at-least-once — callers dedupe by `JobEvent.id`.
protocol SSEClientProtocol: Sendable {
    func events(url: URL, lastEventID: Int?) -> AsyncThrowingStream<ServerSentEvent, Error>
    func decodeJobEvent(from data: Data) throws -> JobEvent
}

final class SSEClient: SSEClientProtocol, Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO 8601 date: \(raw)")
        }
        self.decoder = decoder
    }

    func decodeJobEvent(from data: Data) throws -> JobEvent {
        try decoder.decode(JobEvent.self, from: data)
    }

    func events(url: URL, lastEventID: Int?) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let lastEventID {
                        request.setValue(String(lastEventID), forHTTPHeaderField: "Last-Event-ID")
                    }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.network(URLError(.badServerResponse))
                    }
                    guard http.statusCode == 200 else {
                        throw APIError.http(statusCode: http.statusCode, detail: nil)
                    }
                    var id: Int?
                    var eventType: String?
                    var dataLines: [String] = []
                    func dispatch() {
                        defer { id = nil; eventType = nil; dataLines = [] }
                        guard !dataLines.isEmpty || eventType != nil || id != nil else { return }
                        continuation.yield(ServerSentEvent(
                            id: id, eventType: eventType, data: dataLines.joined(separator: "\n")))
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            dispatch()
                        } else if line.hasPrefix(":") {
                            continue // `: keepalive` and other comments
                        } else if line.hasPrefix("id:") {
                            id = Int(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                        } else if line.hasPrefix("event:") {
                            eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            var text = String(line.dropFirst(5))
                            if text.hasPrefix(" ") { text.removeFirst() }
                            dataLines.append(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
