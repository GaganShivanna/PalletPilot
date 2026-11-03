import Foundation

/// One frame from `GET /jobs/{job_id}/events` (`backend/app/schemas/job_events.py`).
/// `Payloads stay small` per the contract — clients fetch full records from
/// the item endpoints — so the envelope decodes without `payload` (unknown
/// keys are skipped); `item_id` marks per-item `listing.ready` frames.
struct JobEvent: Codable, Sendable, Equatable {
    var id: Int
    var jobId: String
    var eventType: String
    var itemId: String?
    var createdAt: Date

    var isTerminal: Bool {
        eventType == "job.completed" || eventType == "job.failed"
    }

    var didComplete: Bool { eventType == "job.completed" }
}
