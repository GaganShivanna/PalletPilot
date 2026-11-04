import Foundation

/// Pallet endpoints against the verified routes (`docs/ios/API_CONTRACTS.md`
/// §2, §7, §8, §11). ViewModels depend on the protocol, never on URLSession.
protocol PalletServiceProtocol: Sendable {
    func createPallet(_ create: PalletCreate) async throws -> Pallet
    func getSummary(palletId: String) async throws -> PalletSummary
    func listItems(palletId: String) async throws -> [Item]
    func exportCSV(palletId: String) async throws -> Data
}

struct PalletService: PalletServiceProtocol {
    let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func createPallet(_ create: PalletCreate) async throws -> Pallet {
        try await client.post("/pallets", body: create, as: Pallet.self)
    }

    func getSummary(palletId: String) async throws -> PalletSummary {
        try await client.get("/pallets/\(palletId)", as: PalletSummary.self)
    }

    func listItems(palletId: String) async throws -> [Item] {
        try await client.get("/pallets/\(palletId)/items", as: [Item].self)
    }

    func exportCSV(palletId: String) async throws -> Data {
        try await client.getData("/pallets/\(palletId)/export")
    }
}
