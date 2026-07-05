import Foundation

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Spoken phrase that triggers the expansion, e.g. "assinatura de email".
    var trigger: String
    /// Expanded text.
    var expansion: String
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var appName: String
    var rawText: String
    var finalText: String
    var durationSeconds: Double

    var wordsPerMinute: Int {
        guard durationSeconds > 0.5 else { return 0 }
        let words = finalText.split(separator: " ").count
        return Int(Double(words) / (durationSeconds / 60))
    }
}

/// JSON-file-backed store for the personal dictionary, snippets and history.
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var dictionaryWords: [String] { didSet { save(dictionaryWords, to: "dictionary.json") } }
    @Published var snippets: [Snippet] { didSet { save(snippets, to: "snippets.json") } }
    @Published var history: [HistoryEntry] { didSet { save(history, to: "history.json") } }

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WhisperFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        dictionaryWords = Self.load([String].self, from: "dictionary.json") ?? []
        snippets = Self.load([Snippet].self, from: "snippets.json") ?? []
        history = Self.load([HistoryEntry].self, from: "history.json") ?? []
    }

    func addHistory(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }

    /// Replaces spoken snippet triggers found in the transcript with their expansions.
    func applySnippets(to text: String) -> String {
        var result = text
        for snippet in snippets where !snippet.trigger.isEmpty {
            if let range = result.range(of: snippet.trigger, options: [.caseInsensitive, .diacriticInsensitive]) {
                result.replaceSubrange(range, with: snippet.expansion)
            }
        }
        return result
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        let url = Self.dir.appendingPathComponent(file)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
