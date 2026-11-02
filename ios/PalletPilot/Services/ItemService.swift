import Foundation

/// Single-item endpoints (`GET /items/{id}`, `PATCH /items/{id}` — verified
/// contract §9–§10). ViewModels depend on the protocol, never on URLSession.
protocol ItemServiceProtocol: Sendable {
    func getItem(id: String) async throws -> Item
    func patchItem(id: String, patch: ItemPatch) async throws -> Item
}

struct ItemService: ItemServiceProtocol {
    let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func getItem(id: String) async throws -> Item {
        // `:` in item ids is URL-safe — sent verbatim per ios/README.md.
        try await client.get("/items/\(id)", as: Item.self)
    }

    func patchItem(id: String, patch: ItemPatch) async throws -> Item {
        try await client.patch("/items/\(id)", body: patch, as: Item.self)
    }
}
