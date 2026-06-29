import Foundation

public enum SetType: String, Codable, CaseIterable, Sendable {
    case working
    case warmup
    case dropSet
    case pyramid

    public var displayName: String {
        switch self {
        case .working: String(localized: "set_type.working", bundle: .module)
        case .warmup: String(localized: "set_type.warmup", bundle: .module)
        case .dropSet: String(localized: "set_type.dropSet", bundle: .module)
        case .pyramid: String(localized: "set_type.pyramid", bundle: .module)
        }
    }

    public var isSubSet: Bool {
        switch self {
        case .dropSet, .pyramid: true
        case .working, .warmup: false
        }
    }
}
