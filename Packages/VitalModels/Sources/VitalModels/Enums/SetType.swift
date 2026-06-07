import Foundation

public enum SetType: String, Codable, CaseIterable, Sendable {
    case working
    case warmup

    public var displayName: String {
        switch self {
        case .working: "正式"
        case .warmup: "热身"
        }
    }
}
