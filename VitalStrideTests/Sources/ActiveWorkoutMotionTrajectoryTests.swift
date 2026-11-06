import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

@Suite("ActiveWorkout keyboard motion trajectory (TK1)")
struct ActiveWorkoutMotionTrajectoryTests {
    @Test("Keyboard-visible snackbar stays bottom-slotted and hides the FAB")
    @MainActor
    func keyboardVisibleSnackbarPolicyKeepsBottomSlot() {
        for slot in [BottomSnackbarSlot.rest, .undo] {
            let policy = ActiveWorkoutSnackbarLayout.policy(
                isKeyboardVisible: true,
                snackbarSlot: slot
            )
            #expect(policy.topSlot == .none)
            #expect(policy.bottomSlot == slot)
            #expect(policy.isFABVisible == false)
        }
    }

    #if canImport(UIKit) && !os(macOS)
    @Test("Keyboard-visible inactive bottom content measures zero height")
    @MainActor
    func keyboardVisibleInactiveContentMeasuresZeroHeight() {
        let view = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .none,
            isKeyboardVisible: true,
            undoContent: { Color.clear.frame(height: 56) },
            restContent: { Color.clear.frame(height: 56) },
            fab: { Color.clear.frame(width: 60, height: 60) }
        )
        let host = UIHostingController(rootView: view)
        #expect(host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.infinity)).height == 0)
    }
    #endif

    @Test("System keyboard spring has monotonic in-flight trajectory")
    func keyboardSpringTrajectoryIsMonotonic() {
        let spring = Spring(mass: 3, stiffness: 1000, damping: 500)
        let timestamps = [0.016, 0.05, 0.10, 0.15, 0.25]
        let values = timestamps.map {
            spring.value(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: $0)
        }
        let intermediate = values.filter { $0 > 0.02 && $0 < 0.98 }

        #expect(intermediate.count >= 3)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })

        let velocities = timestamps.map {
            spring.velocity(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: $0)
        }
        #expect(velocities.allSatisfy { $0 > 0 })
    }
}
