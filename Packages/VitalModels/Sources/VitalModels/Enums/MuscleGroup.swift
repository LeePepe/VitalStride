import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest
    case back
    case shoulders
    case legs
    case arms
    case core
    case fullBody

    public var localizedName: String {
        switch self {
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .legs: "腿"
        case .arms: "臂"
        case .core: "核心"
        case .fullBody: "全身"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.strengthtraining.functional"
        case .shoulders: "figure.boxing"
        case .legs: "figure.run"
        case .arms: "figure.martial.arts"
        case .core: "figure.core.training"
        case .fullBody: "figure.cross.training"
        }
    }
}
