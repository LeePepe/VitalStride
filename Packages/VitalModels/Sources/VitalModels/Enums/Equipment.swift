import Foundation

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case assisted
    case band
    case barbell
    case dumbbell
    case machine
    case bodyweight
    case bosuBall = "bosu_ball"
    case cable
    case ellipticalMachine = "elliptical_machine"
    case ezBarbell = "ez_barbell"
    case hammer
    case kettlebell
    case leverageMachine = "leverage_machine"
    case medicineBall = "medicine_ball"
    case olympicBarbell = "olympic_barbell"
    case resistanceBand = "resistance_band"
    case roller
    case rope
    case skiergMachine = "skierg_machine"
    case sledMachine = "sled_machine"
    case smithMachine = "smith_machine"
    case stabilityBall = "stability_ball"
    case stationaryBike = "stationary_bike"
    case stepmillMachine = "stepmill_machine"
    case tire
    case trapBar = "trap_bar"
    case upperBodyErgometer = "upper_body_ergometer"
    case weighted
    case wheelRoller = "wheel_roller"

    public var localizedName: String {
        switch self {
        case .assisted: String(localized: "equipment.assisted", bundle: .module)
        case .band: String(localized: "equipment.band", bundle: .module)
        case .barbell: String(localized: "equipment.barbell", bundle: .module)
        case .dumbbell: String(localized: "equipment.dumbbell", bundle: .module)
        case .machine: String(localized: "equipment.machine", bundle: .module)
        case .bodyweight: String(localized: "equipment.bodyweight", bundle: .module)
        case .bosuBall: String(localized: "equipment.bosu_ball", bundle: .module)
        case .cable: String(localized: "equipment.cable", bundle: .module)
        case .ellipticalMachine: String(localized: "equipment.elliptical_machine", bundle: .module)
        case .ezBarbell: String(localized: "equipment.ez_barbell", bundle: .module)
        case .hammer: String(localized: "equipment.hammer", bundle: .module)
        case .kettlebell: String(localized: "equipment.kettlebell", bundle: .module)
        case .leverageMachine: String(localized: "equipment.leverage_machine", bundle: .module)
        case .medicineBall: String(localized: "equipment.medicine_ball", bundle: .module)
        case .olympicBarbell: String(localized: "equipment.olympic_barbell", bundle: .module)
        case .resistanceBand: String(localized: "equipment.resistance_band", bundle: .module)
        case .roller: String(localized: "equipment.roller", bundle: .module)
        case .rope: String(localized: "equipment.rope", bundle: .module)
        case .skiergMachine: String(localized: "equipment.skierg_machine", bundle: .module)
        case .sledMachine: String(localized: "equipment.sled_machine", bundle: .module)
        case .smithMachine: String(localized: "equipment.smith_machine", bundle: .module)
        case .stabilityBall: String(localized: "equipment.stability_ball", bundle: .module)
        case .stationaryBike: String(localized: "equipment.stationary_bike", bundle: .module)
        case .stepmillMachine: String(localized: "equipment.stepmill_machine", bundle: .module)
        case .tire: String(localized: "equipment.tire", bundle: .module)
        case .trapBar: String(localized: "equipment.trap_bar", bundle: .module)
        case .upperBodyErgometer: String(localized: "equipment.upper_body_ergometer", bundle: .module)
        case .weighted: String(localized: "equipment.weighted", bundle: .module)
        case .wheelRoller: String(localized: "equipment.wheel_roller", bundle: .module)
        }
    }

    public var sfSymbol: String {
        switch self {
        case .assisted: "figure.strengthtraining.traditional"
        case .band: "cable.coaxial"
        case .barbell: "scalemass.fill"
        case .dumbbell: "dumbbell"
        case .machine: "figure.indoor.cycle"
        case .bodyweight: "figure.walk"
        case .bosuBall: "figure.strengthtraining.traditional"
        case .cable: "cable.coaxial"
        case .ellipticalMachine: "figure.indoor.cycle"
        case .ezBarbell: "scalemass.fill"
        case .hammer: "dumbbell"
        case .kettlebell: "figure.strengthtraining.traditional"
        case .leverageMachine: "figure.indoor.cycle"
        case .medicineBall: "figure.strengthtraining.traditional"
        case .olympicBarbell: "scalemass.fill"
        case .resistanceBand: "cable.coaxial"
        case .roller: "figure.strengthtraining.traditional"
        case .rope: "cable.coaxial"
        case .skiergMachine: "figure.indoor.cycle"
        case .sledMachine: "figure.indoor.cycle"
        case .smithMachine: "figure.indoor.cycle"
        case .stabilityBall: "figure.strengthtraining.traditional"
        case .stationaryBike: "figure.indoor.cycle"
        case .stepmillMachine: "figure.indoor.cycle"
        case .tire: "figure.strengthtraining.traditional"
        case .trapBar: "scalemass.fill"
        case .upperBodyErgometer: "figure.indoor.cycle"
        case .weighted: "scalemass.fill"
        case .wheelRoller: "figure.strengthtraining.traditional"
        }
    }
}
