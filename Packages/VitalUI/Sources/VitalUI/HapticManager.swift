import Foundation

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

public enum HapticType: CaseIterable, Sendable {
    case setCompleted
    case restCompleted
    case exerciseAdded
    case workoutFinished
}

public enum HapticManager {
    #if canImport(UIKit) && !os(macOS)
    public static func trigger(_ type: HapticType) {
        switch type {
        case .setCompleted:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .restCompleted:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .exerciseAdded:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .workoutFinished:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    #else
    public static func trigger(_ type: HapticType) {}
    #endif
}
