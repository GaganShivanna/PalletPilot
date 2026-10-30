import Foundation

/// Processing lifecycle (`backend/app/schemas/jobs.py: JobStatus`).
/// Order mirrors the pipeline: queued → … → completed/failed.
enum JobStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case queued
    case samplingFrames = "sampling_frames"
    case segmenting
    case identifying
    case generatingPhotos = "generating_photos"
    case generatingListings = "generating_listings"
    case completed
    case failed

    var isTerminal: Bool { self == .completed || self == .failed }
}

/// `GET /jobs` element and `GET /jobs/{job_id}` response.
/// `listings` is a completion-time snapshot: after any item edit it is stale
/// (see docs/ios/BACKEND_API_AUDIT.md D2). Current per-item truth comes from
/// the pallet-items endpoints.
struct Job: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var status: JobStatus
    var createdAt: Date
    var updatedAt: Date
    var videoFilename: String
    var frameCount: Int
    var listings: [Listing]
    var error: String?
}

/// `POST /jobs` response (`backend/app/schemas/jobs.py: JobCreated`).
struct JobCreated: Codable, Sendable, Equatable {
    var id: String
    var status: JobStatus
}
