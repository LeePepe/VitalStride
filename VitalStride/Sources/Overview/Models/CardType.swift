import Foundation

public enum CardType: String, Codable, Sendable, CaseIterable {
    case metric
    case trend
    case insight
    case list
    case summary
    case action

    public var displayName: String {
        switch self {
        case .metric:
            String(localized: "card_type_metric", defaultValue: "Metric")
        case .trend:
            String(localized: "card_type_trend", defaultValue: "Trend")
        case .insight:
            String(localized: "card_type_insight", defaultValue: "Insight")
        case .list:
            String(localized: "card_type_list", defaultValue: "List")
        case .summary:
            String(localized: "card_type_summary", defaultValue: "Summary")
        case .action:
            String(localized: "card_type_action", defaultValue: "Action")
        }
    }
}
