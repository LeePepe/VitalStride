import Foundation

struct TrendDataPoint: Codable, Sendable, Equatable, Identifiable {
    let date: String
    let value: Double
    var id: String { date }
}

struct ListItem: Codable, Sendable, Equatable, Identifiable {
    let label: String
    let value: String?
    var id: String { label }
}

struct SummaryEntry: Sendable, Equatable, Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

enum CardContentParser {
    static func parseTrendData(_ content: String) -> [TrendDataPoint] {
        guard let data = content.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TrendDataPoint].self, from: data)) ?? []
    }

    static func parseListItems(_ content: String) -> [ListItem] {
        guard let data = content.data(using: .utf8) else { return [] }
        if let items = try? JSONDecoder().decode([ListItem].self, from: data) {
            return items
        }
        if let strings = try? JSONDecoder().decode([String].self, from: data) {
            return strings.map { ListItem(label: $0, value: nil) }
        }
        return []
    }

    static func parseSummaryEntries(_ content: String) -> [SummaryEntry] {
        guard let data = content.data(using: .utf8) else { return [] }
        guard let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return []
        }
        return dict.sorted { $0.key < $1.key }
            .map { SummaryEntry(key: $0.key, value: $0.value) }
    }
}
