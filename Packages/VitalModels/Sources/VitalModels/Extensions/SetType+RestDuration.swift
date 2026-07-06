import Foundation

public extension SetType {
    private enum DefaultRestSeconds {
        static let warmup: TimeInterval = 45
        static let working: TimeInterval = 120
        static let dropSet: TimeInterval = 15
        static let pyramid: TimeInterval = 75
    }

    var defaultRestDuration: TimeInterval {
        switch self {
        case .warmup: DefaultRestSeconds.warmup
        case .working: DefaultRestSeconds.working
        case .dropSet: DefaultRestSeconds.dropSet
        case .pyramid: DefaultRestSeconds.pyramid
        }
    }
}
