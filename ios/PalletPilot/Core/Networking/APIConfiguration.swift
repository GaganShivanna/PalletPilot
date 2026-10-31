import Foundation

/// Base-URL configuration for the PalletPilot FastAPI backend.
///
/// Simulator and Mac share localhost, so the default works for `xcodebuild`
/// simulator runs. A physical device cannot reach the Mac's loopback, so the
/// base URL must be overridden with the Mac's LAN IP (see `ios/README.md`).
/// Override precedence: explicit init > UserDefaults > environment > default.
///
/// Verified contract notes (docs/ios/API_CONTRACTS.md): no auth, no versioning
/// prefix, canonical paths have no trailing slash, media URLs are relative.
struct APIConfiguration: Sendable, Equatable {
    /// UserDefaults key for a persistent base-URL override (physical device).
    static let baseURLOverrideKey = "PalletPilotAPIBaseURL"

    /// Environment variable honored at launch (useful for UI tests).
    static let baseURLEnvironmentKey = "PALLET_PILOT_API_BASE_URL"

    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Default for simulator development: the backend on this Mac.
    static var simulatorDefault: APIConfiguration {
        APIConfiguration(baseURL: URL(string: "http://127.0.0.1:8000")!)
    }

    /// Resolve the effective configuration honoring documented overrides.
    static func resolved() -> APIConfiguration {
        if let saved = UserDefaults.standard.string(forKey: baseURLOverrideKey),
           let url = URL(string: saved), url.scheme != nil {
            return APIConfiguration(baseURL: url)
        }
        if let env = ProcessInfo.processInfo.environment[baseURLEnvironmentKey],
           let url = URL(string: env), url.scheme != nil {
            return APIConfiguration(baseURL: url)
        }
        return .simulatorDefault
    }

    /// Join a verified contract path (e.g. "/health") onto the base URL.
    /// Paths are used verbatim: no trailing slash is appended.
    func url(for path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}
