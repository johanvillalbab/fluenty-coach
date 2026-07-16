import Foundation
import Observation

struct TranslationRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let original: String
    let translated: String
    let targetLanguage: Language
    let date: Date
}

/// Persists the most recent translations so the user can revisit, copy, or
/// replay them. Stored as JSON in UserDefaults; capped to `maxRecords`.
@Observable
@MainActor
final class HistoryStore {
    private(set) var records: [TranslationRecord] = []

    private let key = "translationHistory"
    private let maxRecords = 50

    init() { load() }

    func add(original: String, translated: String, targetLanguage: Language) {
        let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty, !t.isEmpty else { return }

        // Skip if this is identical to the most recent entry (e.g. retranslate no-op).
        if let first = records.first, first.original == o, first.translated == t { return }

        records.insert(
            TranslationRecord(id: UUID(), original: o, translated: t, targetLanguage: targetLanguage, date: Date()),
            at: 0
        )
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func remove(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
