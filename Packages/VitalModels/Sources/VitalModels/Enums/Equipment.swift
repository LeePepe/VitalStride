import Foundation

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case barbell
    case dumbbell
    case machine
    case bodyweight
    case cable

    public var localizedName: String {
        switch self {
        case .barbell: "杠铃"
        case .dumbbell: "哑铃"
        case .machine: "固定器械"
        case .bodyweight: "自重"
        case .cable: "绳索"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .barbell: "dumbbell.fill"
        case .dumbbell: "dumbbell"
        case .machine: "gearshape.fill"
        case .bodyweight: "figure.walk"
        case .cable: "cable.coaxial"
        }
    }
}
