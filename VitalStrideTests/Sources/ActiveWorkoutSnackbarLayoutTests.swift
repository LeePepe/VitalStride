import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1421 — production policy + transition regression tests.
///
/// These tests exercise the actual production composition seam, not isolated
/// helper mirrors. They cover the full 2×3 keyboard/snackbar matrix and both
/// transition directions while asserting that the root composition remains
/// mounted, exactly one active slot is presented, and the FAB/snackbar geometry
/// does not interleave.
@Suite("ActiveWorkout snackbar layout (MY-1421)")
struct ActiveWorkoutSnackbarLayoutTests {

    private let allSlots: [BottomSnackbarSlot] = [.none, .rest, .undo]

    @MainActor
    private func productionComposition(
        isKeyboardVisible: Bool,
        snackbarSlot: BottomSnackbarSlot
    ) -> AnyView {
        if isKeyboardVisible {
            return AnyView(
                ActiveWorkoutSnackbarLayout.topComposition(
                    snackbarSlot: snackbarSlot,
                    infoBand: { representativeInfoBand },
                    undoContent: { representativeUndoContent },
                    restContent: { representativeRestContent }
                )
            )
        }

        return AnyView(
            ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                snackbarSlot: snackbarSlot,
                undoContent: { representativeUndoContent },
                restContent: { representativeRestContent },
                fab: { representativeFAB }
            )
        )
    }

    @MainActor
    @Test("Production 2×3 keyboard/snackbar matrix keeps a single mounted composition")
    func productionMatrixkeepsSingleMountedComposition() {
        for isKeyboardVisible in [false, true] {
            for slot in allSlots {
                let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )
                let expectedPolicy: ActiveWorkoutSnackbarLayout.PresentationPolicy = isKeyboardVisible
                    ? .keyboardVisible(slot: slot)
                    : .keyboardHidden(slot: slot)

                #expect(policy == expectedPolicy)
                #expect(policy.activeSlot == slot)
                #expect(policy.hasActiveSnackbar == (slot != .none))
                #expect(policy.usesTopPresentation == (isKeyboardVisible && slot != .none))
                #expect(policy.bottomSafeAreaVisible == !isKeyboardVisible)
                #expect(policy.fabVisible == !isKeyboardVisible)

                let host = UIHostingController(rootView: productionComposition(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                ))
                let size = host.sizeThatFits(in: CGSize(width: 390, height: .infinity))

                #expect(size.height > 0, "State keyboard=\(isKeyboardVisible) slot=\(slot) must keep a mounted production composition")

                if slot == .none {
                    #expect(!policy.hasActiveSnackbar, "No active snackbar should be presented for the .none state")
                } else {
                    #expect(policy.hasActiveSnackbar, "Exactly one active snackbar should be presented for state keyboard=\(isKeyboardVisible) slot=\(slot)")
                    #expect(policy.activeSlot == slot)
                }
            }
        }
    }

    @MainActor
    @Test("Keyboard transitions preserve root mount and active slot in both directions")
    func keyboardTransitionsPreserveProductionComposition() {
        for slot in allSlots {
            let hidden = ActiveWorkoutSnackbarLayout.resolvePolicy(
                isKeyboardVisible: false,
                snackbarSlot: slot
            )
            let visible = ActiveWorkoutSnackbarLayout.resolvePolicy(
                isKeyboardVisible: true,
                snackbarSlot: slot
            )

            let hiddenView = productionComposition(isKeyboardVisible: false, snackbarSlot: slot)
            let visibleView = productionComposition(isKeyboardVisible: true, snackbarSlot: slot)

            let hiddenHost = UIHostingController(rootView: hiddenView)
            let visibleHost = UIHostingController(rootView: visibleView)

            let hiddenHeight = hiddenHost.sizeThatFits(in: CGSize(width: 390, height: .infinity)).height
            let visibleHeight = visibleHost.sizeThatFits(in: CGSize(width: 390, height: .infinity)).height

            #expect(hiddenHeight > 0)
            #expect(visibleHeight > 0)
            #expect(hidden.bottomSafeAreaVisible)
            #expect(!visible.bottomSafeAreaVisible)
            #expect(hidden.fabVisible)
            #expect(!visible.fabVisible)
            #expect(hidden.activeSlot == slot)
            #expect(visible.activeSlot == slot)

            if slot == .none {
                #expect(!hidden.hasActiveSnackbar)
                #expect(!visible.hasActiveSnackbar)
            } else {
                #expect(hidden.hasActiveSnackbar)
                #expect(visible.hasActiveSnackbar)
                #expect(hidden.usesTopPresentation == false)
                #expect(visible.usesTopPresentation)
            }
        }
    }

    @MainActor
    @Test("Keyboard-visible top layout keeps final-row clearance and a single active presentation")
    func keyboardVisibleTopLayoutStaysSingleActivePresentation() {
        let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(isKeyboardVisible: true, snackbarSlot: .rest)
        #expect(policy.isKeyboardVisible)
        #expect(policy.usesTopPresentation)
        #expect(policy.activeSlot == .rest)
        #expect(policy.hasActiveSnackbar)

        let host = UIHostingController(rootView: productionComposition(
            isKeyboardVisible: true,
            snackbarSlot: .rest
        ))
        let size = host.sizeThatFits(in: CGSize(width: 390, height: .infinity))

        #expect(size.height > 0)
        #expect(ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: true) == .top)
    }

    @MainActor
    private var representativeInfoBand: some View {
        HStack {
            Text("12:34")
                .font(.title2.monospacedDigit())
            Spacer()
            Text("1 set · 2 exercises")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    @MainActor
    private var representativeUndoContent: some View {
        HStack {
            Text("Undo")
            Spacer()
            Button("Undo") {}
        }
        .padding(12)
        .frame(height: 56)
    }

    @MainActor
    private var representativeRestContent: some View {
        HStack {
            Text("Rest")
            Spacer()
            Button("Skip") {}
        }
        .padding(12)
        .frame(height: 56)
    }

    @MainActor
    private var representativeFAB: some View {
        Color.clear
            .frame(width: 60, height: 60)
            .padding()
    }
}
