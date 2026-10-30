import Foundation

/// Pallet creation against the verified `POST /pallets` route.
/// ViewModels depend on the protocol, never on URLSession.
protocol PalletServiceProtocol: Sendable {
    func createPallet(_ create: PalletCreate) async throws -> Pallet
}

struct PalletService: PalletServiceProtocol {
    let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func createPallet(_ create: PalletCreate) async throws -> Pallet {
        try await client.post("/pallets", body: create, as: Pallet.self)
    }
}
