import Foundation

/// `GET /health` response. Grounded in `backend/app/routes/health.py`.
struct HealthResponse: Codable, Sendable, Equatable {
    var status: String

    var isHealthy: Bool { status == "ok" }
}
