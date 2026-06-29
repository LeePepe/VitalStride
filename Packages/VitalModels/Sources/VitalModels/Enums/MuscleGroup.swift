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
        case .chest: String(localized: "muscle.chest", bundle: .module)
        case .back: String(localized: "muscle.back", bundle: .module)
        case .shoulders: String(localized: "muscle.shoulders", bundle: .module)
        case .legs: String(localized: "muscle.legs", bundle: .module)
        case .arms: String(localized: "muscle.arms", bundle: .module)
        case .core: String(localized: "muscle.core", bundle: .module)
        case .fullBody: String(localized: "muscle.fullBody", bundle: .module)
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
