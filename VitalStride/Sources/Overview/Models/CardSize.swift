import Foundation

public enum CardSize: String, Codable, Sendable, CaseIterable {
    case small
    case medium
    case wide
    case large

    public var displayName: String {
        switch self {
        case .small:
            String(localized: "card_size_small", defaultValue: "Small")
        case .medium:
            String(localized: "card_size_medium", defaultValue: "Medium")
        case .wide:
            String(localized: "card_size_wide", defaultValue: "Wide")
        case .large:
            String(localized: "card_size_large", defaultValue: "Large")
        }
    }
}
