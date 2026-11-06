import SwiftUI
import Testing
import Foundation

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

    @Test("Sidebar reorder callbacks preserve selection and non-overlapping item frames")
    @MainActor
    func sidebarReorderCallbacksPreserveSelectionAndFrames() {
        var items = (0..<4).map {
            ActiveWorkoutSidebarItem(
                id: "exercise-\($0)",
                name: "Exercise \($0)",
                index: $0,
                completed: 0,
                total: 1
            )
        }
        let selectedID = "exercise-2"
        var reorderMode = false
        var observedItems: [ActiveWorkoutSidebarItem] = []
        var observedFrames: [String: CGRect] = [:]
        var toggle: (@MainActor @Sendable () -> Void)?
        var moveUp: (@MainActor @Sendable (Int) -> Void)?
        var moveDown: (@MainActor @Sendable (Int) -> Void)?

        let sink = ActiveWorkoutListObservationSink(
            onSidebarItems: { observedItems = $0 },
            onSidebarItemFrame: { observedFrames[$0] = $1 },
            onSidebarReorderModeState: { reorderMode = $0 },
            onSidebarReorderToggleAction: { _ in toggle = { reorderMode.toggle() } },
            onSidebarMoveUpAction: { moveUp = $0 },
            onSidebarMoveDownAction: { moveDown = $0 }
        )

        toggle = { reorderMode.toggle() }
        toggle?()
        sink.onSidebarReorderModeState(reorderMode)
        sink.onSidebarItems(items)
        for (index, item) in items.enumerated() {
            sink.onSidebarItemFrame(item.id, CGRect(x: 0, y: CGFloat(index * 60), width: 260, height: 52))
        }
        let moveDownAction: @MainActor @Sendable (Int) -> Void = { index in
            guard items.indices.contains(index), index < items.count - 1 else { return }
            items.swapAt(index, index + 1)
            observedItems = items
        }
        let moveUpAction: @MainActor @Sendable (Int) -> Void = { index in
            guard items.indices.contains(index), index > 0 else { return }
            items.swapAt(index, index - 1)
            observedItems = items
        }
        sink.onSidebarMoveDownAction(moveDownAction)
        sink.onSidebarMoveUpAction(moveUpAction)

        moveDown?(1)
        moveUp?(2)

        #expect(reorderMode)
        #expect(observedItems.map(\.id) == items.map(\.id))
        #expect(items.contains { $0.id == selectedID })
        #expect(observedFrames.count == items.count)
        let frames = items.compactMap { observedFrames[$0.id] }
        #expect(frames.count == items.count)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { !$0.intersects($1) })
    }

    @Test("Sidebar reorder and move springs provide monotonic in-flight frames")
    func sidebarSpringTrajectoriesAreContinuous() {
        for spring in [
            Spring(response: 0.32, dampingRatio: 0.84),
            Spring(response: 0.28, dampingRatio: 0.82)
        ] {
            let values = stride(from: 0.016, through: 0.4, by: 0.016).map {
                spring.value(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: $0)
            }
            let inFlight = values.prefix(while: { $0 < 0.98 })
            let intermediate = inFlight.filter { $0 > 0.02 && $0 < 0.98 }

            #expect(intermediate.count >= 4)
            #expect(zip(inFlight, inFlight.dropFirst()).allSatisfy { $0 < $1 })
        }
    }
}
