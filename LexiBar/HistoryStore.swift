import Foundation

struct HistoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let input: String
    let result: String
    let provider: String
    let model: String

    init(id: UUID = UUID(), timestamp: Date = Date(), input: String, result: String, provider: String, model: String) {
        self.id = id
        self.timestamp = timestamp
        self.input = input
        self.result = result
        self.provider = provider
        self.model = model
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var records: [HistoryRecord] = []

    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LexiBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ record: HistoryRecord) {
        records.insert(record, at: 0)
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
