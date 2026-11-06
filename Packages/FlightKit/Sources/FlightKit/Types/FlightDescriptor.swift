import Foundation

public struct FlightDescriptor: Identifiable, Hashable, Sendable {
    public let key: String
    public let title: String
    public let summary: String
    public let category: String
    public let defaultValue: Bool

    public var id: String { key }

    public init(
        key: String,
        title: String,
        summary: String,
        category: String,
        defaultValue: Bool
    ) {
        self.key = key
        self.title = title
        self.summary = summary
        self.category = category
        self.defaultValue = defaultValue
    }

    public static func grouped(_ descriptors: [FlightDescriptor]) -> [String: [FlightDescriptor]] {
        Dictionary(grouping: descriptors, by: \.category)
    }

    public static func filtered(
        _ descriptors: [FlightDescriptor],
        query: String
    ) -> [FlightDescriptor] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return descriptors }
        return descriptors.filter {
            [$0.key, $0.title, $0.summary, $0.category]
                .contains { $0.lowercased().contains(normalizedQuery) }
        }
    }
}

public typealias FlightFlag = FlightDescriptor
