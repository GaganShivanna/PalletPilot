import Foundation

/// One locally remembered pallet. The backend has no `GET /pallets` (G1),
/// so the app persists created pallets on-device for the recents list and
/// for linking job history back to inventories.
struct PalletHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    var palletId: String
    var jobId: String?
    var name: String
    var createdAt: Date

    var id: String { palletId }
}

/// An in-flight pallet creation: adopted by a fresh UploadViewModel when the
/// user leaves and returns mid-flow, so retrying never creates a duplicate
/// pallet (the backend has no pallet delete). Adopted only when the draft
/// form still matches, so edited drafts create their own pallet.
struct PendingUpload: Codable, Sendable, Equatable {
    var palletId: String
    var name: String
    var purchase: Double
    var additional: Double
}

/// UserDefaults-backed pallet recents. Lives in Services because it owns
/// side effects; view models observe it through `recents()`.
struct PalletHistoryStore: Sendable {
    private let defaults: UserDefaults
    private let key = "PalletPilotPalletHistory"
    private let pendingKey = "PalletPilotPendingUpload"
    private let limit = 50

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savePending(_ pending: PendingUpload) {
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    func pendingUpload() -> PendingUpload? {
        guard let data = defaults.data(forKey: pendingKey),
            let pending = try? JSONDecoder().decode(PendingUpload.self, from: data)
        else { return nil }
        return pending
    }

    func clearPending() {
        defaults.removeObject(forKey: pendingKey)
    }

    /// Insert or replace the entry for `palletId`, newest first.
    func save(palletId: String, jobId: String?, name: String) {
        var entries = recents()
        entries.removeAll { $0.palletId == palletId }
        entries.insert(
            PalletHistoryEntry(
                palletId: palletId, jobId: jobId, name: name, createdAt: Date()),
            at: 0)
        entries = Array(entries.prefix(limit))
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    func recents() -> [PalletHistoryEntry] {
        guard let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode(
                [PalletHistoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    func remove(palletId: String) {
        let entries = recents().filter { $0.palletId != palletId }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    /// Pallet linked to a job, if this device created or claimed it.
    func palletId(forJobId jobId: String) -> String? {
        recents().first { $0.jobId == jobId }?.palletId
    }
}
