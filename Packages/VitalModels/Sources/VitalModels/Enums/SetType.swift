import Foundation

public enum SetType: String, Codable, CaseIterable, Sendable {
    case working
    case warmup
    case dropSet
    case pyramid

    public var displayName: String {
        switch self {
        case .working: "正式"
        case .warmup: "热身"
        case .dropSet: "递减"
        case .pyramid: "递增"
        }
    }

    public var isSubSet: Bool {
        switch self {
        case .dropSet, .pyramid: true
        case .working, .warmup: false
        }
    }
}
