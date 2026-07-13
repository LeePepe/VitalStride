import Foundation

// watchOS also `canImport(UIKit)` but lacks UIImpactFeedbackGenerator /
// UINotificationFeedbackGenerator (those are WatchKit-side there), so the UIKit
// path must exclude watchOS as well as macOS.
#if canImport(UIKit) && !os(macOS) && !os(watchOS)
import UIKit
#endif

public enum HapticType: CaseIterable, Sendable {
    case setCompleted
    case restCompleted
    case exerciseAdded
    case workoutFinished
}

public enum HapticManager {
    #if canImport(UIKit) && !os(macOS) && !os(watchOS)
    @MainActor
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
    @MainActor
    public static func trigger(_ type: HapticType) {}
    #endif
}
