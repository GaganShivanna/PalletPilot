import SwiftUI

/// App-wide destinations. Grows per USER_FLOW.md
/// (inventory, item edit, profit, export).
enum AppRoute: Hashable {
    case home
    case upload
    case processing(jobId: String, palletId: String?)
}

/// Reusable NavigationStack router. Views navigate via the environment router,
/// never by owning their own NavigationPath.
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    @MainActor
    func navigate(to route: AppRoute) {
        path.append(route)
    }

    @MainActor
    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    @MainActor
    func popToRoot() {
        path = NavigationPath()
    }
}

private struct RouterKey: EnvironmentKey {
    static let defaultValue = AppRouter()
}

extension EnvironmentValues {
    var router: AppRouter {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}

private struct ContainerKey: EnvironmentKey {
    static let defaultValue = AppContainer.preview(client: PreviewStubClient())
}

extension EnvironmentValues {
    var container: AppContainer {
        get { self[ContainerKey.self] }
        set { self[ContainerKey.self] = newValue }
    }
}

/// Placeholder client so SwiftUI previews type-check without a backend.
private struct PreviewStubClient: APIClientProtocol {
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        throw APIError.invalidRequest("Preview stub: no backend (\(path))")
    }

    func getData(_ path: String) async throws -> Data {
        throw APIError.invalidRequest("Preview stub: no backend (\(path))")
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APIError.invalidRequest("Preview stub: no backend (\(path))")
    }

    func upload<T: Decodable>(
        _ path: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String],
        as type: T.Type
    ) async throws -> T {
        throw APIError.invalidRequest("Preview stub: no backend (\(path))")
    }
}
