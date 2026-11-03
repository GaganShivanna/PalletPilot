import Foundation

/// Export screen state. Counts come from `GET /pallets/{id}/items`; the CSV
/// bytes come from `GET /pallets/{id}/export` (server-generated, always the
/// full list — there is no include-unreviewed query param, so the toggle
/// filters the downloaded copy client-side before sharing).
enum ExportLoadState: Equatable {
    case loading
    case loaded
    case failed(message: String)
}

@MainActor
final class ExportViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var state: ExportLoadState = .loading
    @Published var includeUnreviewed = false
    @Published private(set) var csvData: Data?
    @Published var shareError: String?

    let palletId: String
    private let palletService: PalletServiceProtocol

    init(palletId: String, palletService: PalletServiceProtocol) {
        self.palletId = palletId
        self.palletService = palletService
    }

    convenience init(palletId: String, container: AppContainer) {
        self.init(palletId: palletId, palletService: container.palletService)
    }

    var reviewedCount: Int { items.filter { !$0.needsReview }.count }
    var unreviewedCount: Int { items.filter(\.needsReview).count }
    /// Rows the Share sheet will contain under the current toggle.
    var exportedCount: Int { includeUnreviewed ? items.count : reviewedCount }
    /// Items without a price are donate/skip candidates (no delete endpoint).
    var donateCount: Int { items.filter { $0.suggestedPrice == nil }.count }

    var fileName: String { "pallet-export-\(palletId.prefix(8)).csv" }

    func load() async {
        state = .loading
        do {
            items = try await palletService.listItems(palletId: palletId)
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    func fetchCSV() async {
        shareError = nil
        csvData = nil
        do {
            let data = try await palletService.exportCSV(palletId: palletId)
            guard let filtered = Self.filteredCSV(data, includeUnreviewed: includeUnreviewed) else {
                shareError = "The export format changed — refusing to share rather than risk unreviewed rows."
                return
            }
            csvData = filtered
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Drops `needs_review` rows when the toggle is off. Record-aware: quoted
    /// newlines inside a cell never split a row, and kept rows keep their
    /// original bytes so server quoting/escaping is preserved. Returns nil
    /// when the header lacks `review_status`: sharing blindly would risk
    /// leaking unreviewed rows, so the caller must fail closed instead.
    nonisolated static func filteredCSV(_ data: Data, includeUnreviewed: Bool) -> Data? {
        guard !includeUnreviewed,
              let text = String(data: data, encoding: .utf8) else { return data }
        let records = Self.splitRecords(text)
        guard let header = records.first else { return data }
        guard let statusIndex = Self.splitFields(header).firstIndex(of: "review_status") else {
            return nil
        }
        var kept = [header]
        for record in records.dropFirst() {
            let fields = Self.splitFields(record)
            if fields.count > statusIndex, fields[statusIndex] == "needs_review" { continue }
            kept.append(record)
        }
        return Data((kept.joined(separator: "\n") + "\n").utf8)
    }

    private nonisolated static func splitRecords(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(text)
        var i = chars.startIndex
        while i < chars.endIndex {
            let character = chars[i]
            if character == "\"" {
                let next = chars.index(after: i)
                if inQuotes, next < chars.endIndex, chars[next] == "\"" {
                    current.append("\"\"")
                    i = chars.index(after: next)
                    continue
                }
                inQuotes.toggle()
                current.append(character)
            } else if character == "\n", !inQuotes {
                records.append(current)
                current = ""
            } else if character != "\r" {
                current.append(character)
            }
            i = chars.index(after: i)
        }
        if !current.isEmpty { records.append(current) }
        return records
    }

    private nonisolated static func splitFields(_ record: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = record.startIndex
        while index < record.endIndex {
            let character = record[index]
            if character == "\"" {
                let next = record.index(after: index)
                if inQuotes, next < record.endIndex, record[next] == "\"" {
                    current.append("\"")
                    index = record.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = record.index(after: index)
        }
        fields.append(current)
        return fields
    }
}
