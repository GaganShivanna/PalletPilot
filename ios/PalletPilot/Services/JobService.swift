import Foundation

/// Job endpoints used by the upload + processing flows:
/// `POST /jobs` (multipart), `GET /jobs/{id}` (poll), `GET /jobs` (history).
/// ViewModels depend on the protocol, never on URLSession.
protocol JobServiceProtocol: Sendable {
    func uploadVideo(_ video: UploadVideo, palletId: String?) async throws -> JobCreated
    func getJob(id: String) async throws -> Job
    func listJobs() async throws -> [Job]
}

/// A video selected for upload, with a verified backend-compatible extension.
struct UploadVideo: Sendable, Equatable {
    /// Extensions accepted by `POST /jobs` (`routes/jobs.py`).
    static let allowedExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "webm", "mkv"]

    var data: Data
    var filename: String
    var mimeType: String

    init(data: Data, fileExtension: String) throws {
        let ext = fileExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            throw APIError.invalidRequest("Unsupported video type: \(ext.isEmpty ? "none" : ext)")
        }
        self.data = data
        self.filename = "video.\(ext)"
        self.mimeType = Self.mimeType(for: ext)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "avi": return "video/x-msvideo"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        default: return "video/mp4"
        }
    }
}

struct JobService: JobServiceProtocol {
    let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func uploadVideo(_ video: UploadVideo, palletId: String?) async throws -> JobCreated {
        var fields: [String: String] = [:]
        if let palletId { fields["pallet_id"] = palletId }
        return try await client.upload(
            "/jobs", fileData: video.data, filename: video.filename,
            mimeType: video.mimeType, fields: fields, as: JobCreated.self
        )
    }

    func getJob(id: String) async throws -> Job {
        try await client.get("/jobs/\(id)", as: Job.self)
    }

    func listJobs() async throws -> [Job] {
        try await client.get("/jobs", as: [Job].self)
    }
}
