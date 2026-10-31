import Foundation

/// HTTP verbs used by the verified contract. Only GET/PATCH/POST exist server-side.
enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
}

/// Typed HTTP client over URLSession. All paths come from the verified contract
/// (docs/ios/API_CONTRACTS.md) and are sent verbatim — no trailing slash.
///
/// Success is any 2xx status (covers 200, 201, 202). Non-2xx responses throw
/// `APIError.http` with the body's `detail` message when present.
protocol APIClientProtocol: Sendable {
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T
    func getData(_ path: String) async throws -> Data
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func upload<T: Decodable>(
        _ path: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String],
        as type: T.Type
    ) async throws -> T
}

struct APIClient: APIClientProtocol {
    let configuration: APIConfiguration
    let session: URLSession
    let decoder: JSONDecoder

    init(configuration: APIConfiguration = .resolved(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601.fractionalDate(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO 8601 date: \(raw)")
        }
        self.decoder = decoder
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await getData(path)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func getData(_ path: String) async throws -> Data {
        guard let url = configuration.url(for: path) else {
            throw APIError.invalidRequest("Bad path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard let url = configuration.url(for: path) else {
            throw APIError.invalidRequest("Bad path: \(path)")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw APIError.invalidRequest("Unencodable body for \(path): \(error)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        return try await decode(perform(request), as: T.self)
    }

    func upload<T: Decodable>(
        _ path: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String],
        as type: T.Type
    ) async throws -> T {
        guard let url = configuration.url(for: path) else {
            throw APIError.invalidRequest("Bad path: \(path)")
        }
        let boundary = "PalletPilot-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary, fileData: fileData,
            filename: filename, mimeType: mimeType, fields: fields
        )
        return try await decode(perform(request), as: T.self)
    }

    /// Raw request execution with status handling. Success is any 2xx status
    /// (covers 200, 201, 202). Non-2xx responses throw `APIError.http`.
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(statusCode: http.statusCode, detail: Self.detail(from: data))
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Multipart encoding for `POST /jobs`: one `video` file part plus optional
    /// text fields (e.g. `pallet_id`). Field order matches the handoff's curl.
    static func multipartBody(
        boundary: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Best-effort `detail` extraction. 422 bodies are validation envelopes, not
    /// `{"detail": string}`, so decoding failure there yields nil and the
    /// caller falls back to the generic 422 message.
    private static func detail(from data: Data) -> String? {
        try? JSONDecoder().decode(ErrorDetailResponse.self, from: data).detail
    }
}

/// ISO 8601 with fractional seconds, as emitted by the backend
/// (`datetime.now(UTC).isoformat()`), falling back to whole seconds.
private enum ISO8601 {
    static func fractionalDate(from raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}
