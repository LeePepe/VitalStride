import Foundation

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case barbell
    case dumbbell
    case machine
    case bodyweight
    case cable
    case kettlebell

    public var localizedName: String {
        switch self {
        case .barbell: String(localized: "equipment.barbell", bundle: .module)
        case .dumbbell: String(localized: "equipment.dumbbell", bundle: .module)
        case .machine: String(localized: "equipment.machine", bundle: .module)
        case .bodyweight: String(localized: "equipment.bodyweight", bundle: .module)
        case .cable: String(localized: "equipment.cable", bundle: .module)
        case .kettlebell: String(localized: "equipment.kettlebell", bundle: .module)
        }
    }

    public var sfSymbol: String {
        switch self {
        case .barbell: "scalemass.fill"
        case .dumbbell: "dumbbell"
        case .machine: "figure.indoor.cycle"
        case .bodyweight: "figure.walk"
        case .cable: "cable.coaxial"
        case .kettlebell: "figure.strengthtraining.traditional"
        }
    }
}
