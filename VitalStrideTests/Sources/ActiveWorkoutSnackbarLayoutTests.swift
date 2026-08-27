import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1421 — Snackbar/FAB/keyboard layout regression tests.
///
/// These tests enforce the production 2×3 keyboard/snackbar policy and keep
/// the bottom composition structurally stable while the keyboard toggles.
@Suite("ActiveWorkout snackbar layout (MY-1421)")
struct ActiveWorkoutSnackbarLayoutTests {

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("FAB safeAreaInset height is constant regardless of snackbar state")
    func fabHeightConstantAcrossSnackbarStates() {
        let fabNoSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .none) {
            representativeFAB
        }
        let hostNoSnackbar = UIHostingController(rootView: fabNoSnackbar)
        let sizeNoSnackbar = hostNoSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        let fabWithSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .rest) {
            representativeFAB
        }
        let hostWithSnackbar = UIHostingController(rootView: fabWithSnackbar)
        let sizeWithSnackbar = hostWithSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        let fabWithUndo = ActiveWorkoutFABContainer.body(snackbarSlot: .undo) {
            representativeFAB
        }
        let hostWithUndo = UIHostingController(rootView: fabWithUndo)
        let sizeWithUndo = hostWithUndo.sizeThatFits(in: CGSize(width: 400, height: 0))

        let tolerance: CGFloat = 1
        #expect(
            abs(sizeNoSnackbar.height - sizeWithSnackbar.height) <= tolerance,
            "FAB height shifted by \(abs(sizeNoSnackbar.height - sizeWithSnackbar.height))pt when rest snackbar appeared; must be within \(tolerance)pt. Heights: noSnackbar=\(sizeNoSnackbar.height), withSnackbar=\(sizeWithSnackbar.height)"
        )
        #expect(
            abs(sizeNoSnackbar.height - sizeWithUndo.height) <= tolerance,
            "FAB height shifted by \(abs(sizeNoSnackbar.height - sizeWithUndo.height))pt when undo snackbar appeared; must be within \(tolerance)pt. Heights: noSnackbar=\(sizeNoSnackbar.height), withUndo=\(sizeWithUndo.height)"
        )
    }

    @MainActor
    private var representativeFAB: some View {
        Color.clear
            .frame(width: 60, height: 60)
            .padding()
    }
    #endif

    @MainActor
    @Test("Keyboard visibility and snackbar slot resolve to one production policy")
    func keyboardAndSnackbarMatrixResolvesSingleActivePresentation() {
        let keyboardStates = [false, true]
        let slots: [BottomSnackbarSlot] = [.none, .rest, .undo]

        for keyboardVisible in keyboardStates {
            let expectedEdge = keyboardVisible ? VerticalEdge.top : .bottom
            let edge = ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: keyboardVisible)
            #expect(edge == expectedEdge)

            for slot in slots {
                let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                    isKeyboardVisible: keyboardVisible,
                    snackbarSlot: slot
                )
                let expectedPolicy = keyboardVisible
                    ? ActiveWorkoutSnackbarLayout.PresentationPolicy.keyboardVisible(slot: slot)
                    : ActiveWorkoutSnackbarLayout.PresentationPolicy.keyboardHidden(slot: slot)

                #expect(policy == expectedPolicy)
                #expect(policy.activeSlot == slot)
                #expect(policy.hasActiveSnackbar == (slot != .none))
                #expect(policy.usesTopPresentation == (keyboardVisible && slot != .none))
                #expect(policy.bottomSafeAreaVisible == !keyboardVisible)
                #expect(policy.fabVisible == !keyboardVisible)

                let activeContent = ActiveWorkoutSnackbarLayout.activeSlotContent(
                    snackbarSlot: slot,
                    undoContent: {
                        Text("Undo").padding(8)
                    },
                    restContent: {
                        Text("Rest").padding(8)
                    }
                )
                let host = UIHostingController(rootView: activeContent)
                let size = host.sizeThatFits(in: CGSize(width: 320, height: .infinity))

                if slot == .none {
                    #expect(size.height == 0, "No snackbar should produce an empty presentation for state keyboard=\(keyboardVisible) slot=\(slot)")
                } else {
                    #expect(size.height > 0, "State keyboard=\(keyboardVisible) slot=\(slot) should retain one visible active snackbar")
                }
            }
        }
    }

    @MainActor
    @Test("Keyboard visible path keeps a single active top snackbar")
    func keyboardVisibleStateRespectsTopPlacement() {
        let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(isKeyboardVisible: true, snackbarSlot: .rest)
        #expect(policy.usesTopPresentation)
        #expect(policy.activeSlot == .rest)
        #expect(policy.isKeyboardVisible)
        #expect(ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: true) == .top)
    }
}
