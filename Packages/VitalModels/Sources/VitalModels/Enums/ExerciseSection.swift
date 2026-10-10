import Foundation

public enum ExerciseSection: String, Codable, CaseIterable, Sendable {
    case assisted
    case band
    case barbell
    case bodyweight
    case cable
    case dumbbell
    case ezBarbell = "ez_barbell"
    case kettlebell
    case leverageMachine = "leverage_machine"
    case machine
    case medicineBall = "medicine_ball"
    case rope
    case sledMachine = "sled_machine"
    case smithMachine = "smith_machine"
    case stabilityBall = "stability_ball"
    case weighted
    case other

    public var localizedName: String {
        switch self {
        case .assisted: String(localized: "section.assisted", bundle: .module)
        case .band: String(localized: "section.band", bundle: .module)
        case .barbell: String(localized: "section.barbell", bundle: .module)
        case .bodyweight: String(localized: "section.bodyweight", bundle: .module)
        case .cable: String(localized: "section.cable", bundle: .module)
        case .dumbbell: String(localized: "section.dumbbell", bundle: .module)
        case .ezBarbell: String(localized: "section.ez_barbell", bundle: .module)
        case .kettlebell: String(localized: "section.kettlebell", bundle: .module)
        case .leverageMachine: String(localized: "section.leverage_machine", bundle: .module)
        case .machine: String(localized: "section.machine", bundle: .module)
        case .medicineBall: String(localized: "section.medicine_ball", bundle: .module)
        case .other: String(localized: "section.other", bundle: .module)
        case .rope: String(localized: "section.rope", bundle: .module)
        case .sledMachine: String(localized: "section.sled_machine", bundle: .module)
        case .smithMachine: String(localized: "section.smith_machine", bundle: .module)
        case .stabilityBall: String(localized: "section.stability_ball", bundle: .module)
        case .weighted: String(localized: "section.weighted", bundle: .module)
        }
    }

    public var sfSymbol: String {
        switch self {
        case .assisted: "figure.strengthtraining.traditional"
        case .band: "figure.martial.arts"
        case .barbell: "scalemass.fill"
        case .bodyweight: "figure.walk"
        case .cable: "cable.coaxial"
        case .dumbbell: "dumbbell"
        case .ezBarbell: "figure.archery"
        case .kettlebell: "figure.strengthtraining.functional"
        case .leverageMachine: "figure.indoor.cycle"
        case .machine: "figure.outdoor.cycle"
        case .medicineBall: "basketball.fill"
        case .other: "ellipsis.circle"
        case .rope: "rope"
        case .sledMachine: "figure.skiing"
        case .smithMachine: "figure.core.training"
        case .stabilityBall: "figure.pool.swim"
        case .weighted: "weight.3"
        }
    }
}
