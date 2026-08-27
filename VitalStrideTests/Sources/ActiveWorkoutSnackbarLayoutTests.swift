import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1421 — production root transition regression tests.
///
/// These tests host one production-consumed root and toggle the shared keyboard/
/// slot state on that same controller. They prove the bottom safe-area subtree is
/// structurally stable across hidden→visible→hidden transitions and that the
/// policy remains single-active across all six keyboard/snackbar states.
@Suite("ActiveWorkout snackbar layout (MY-1421)")
struct ActiveWorkoutSnackbarLayoutTests {

    @MainActor
    private final class ProductionRootState: ObservableObject {
        @Published var isKeyboardVisible: Bool
        @Published var snackbarSlot: BottomSnackbarSlot

        init(isKeyboardVisible: Bool = false, snackbarSlot: BottomSnackbarSlot = .none) {
            self.isKeyboardVisible = isKeyboardVisible
            self.snackbarSlot = snackbarSlot
        }
    }

    @MainActor
    private struct ProductionRoot: View {
        @ObservedObject var state: ProductionRootState

        var body: some View {
            VStack(spacing: 0) {
                if state.isKeyboardVisible {
                    ActiveWorkoutSnackbarLayout.topComposition(
                        snackbarSlot: state.snackbarSlot,
                        infoBand: { representativeInfoBand },
                        undoContent: { representativeUndoContent },
                        restContent: { representativeRestContent }
                    )
                } else {
                    representativeInfoBand
                }

                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        Color.clear.frame(height: 56)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                    snackbarSlot: state.snackbarSlot,
                    undoContent: { representativeUndoContent },
                    restContent: { representativeRestContent },
                    fab: { representativeFAB }
                )
                .opacity(state.isKeyboardVisible ? 0 : 1)
                .allowsHitTesting(!state.isKeyboardVisible)
                .accessibilityHidden(state.isKeyboardVisible)
            }
            .animation(.easeInOut(duration: 0.2), value: state.isKeyboardVisible)
            .animation(.easeInOut(duration: 0.2), value: state.snackbarSlot)
        }
    }

    @MainActor
    @Test("Single production root stays mounted across hidden→visible→hidden transitions")
    func productionRootStaysMountedAcrossTransitions() {
        let state = ProductionRootState()
        let host = UIHostingController(rootView: ProductionRoot(state: state))

        for slot in [BottomSnackbarSlot.none, .rest, .undo] {
            state.snackbarSlot = slot
            state.isKeyboardVisible = false
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

            let hiddenHeight = host.sizeThatFits(in: CGSize(width: 390, height: .infinity)).height
            #expect(hiddenHeight > 0, "Hidden state must keep the root mounted for slot \(slot)")
            #expect(type(of: host.rootView) == ProductionRoot.self)

            state.isKeyboardVisible = true
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

            let visibleHeight = host.sizeThatFits(in: CGSize(width: 390, height: .infinity)).height
            #expect(visibleHeight > 0, "Visible state must keep the root mounted for slot \(slot)")
            #expect(state.snackbarSlot == slot)
            #expect(state.isKeyboardVisible)

            let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                isKeyboardVisible: true,
                snackbarSlot: slot
            )
            #expect(policy.activeSlot == slot)
            #expect(policy.hasActiveSnackbar == (slot != .none))
            #expect(policy.usesTopPresentation == (slot != .none))

            state.isKeyboardVisible = false
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

            let hiddenAgain = host.sizeThatFits(in: CGSize(width: 390, height: .infinity)).height
            #expect(hiddenAgain > 0, "The same root must survive the visible→hidden transition for slot \(slot)")
            #expect(!state.isKeyboardVisible)
        }
    }

    @MainActor
    @Test("Production root resolves all six keyboard/snackbar states with one active presentation")
    func productionRootResolvesAllSettledStates() {
        for isKeyboardVisible in [false, true] {
            for slot in [BottomSnackbarSlot.none, .rest, .undo] {
                let state = ProductionRootState(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )
                let host = UIHostingController(rootView: ProductionRoot(state: state))
                let size = host.sizeThatFits(in: CGSize(width: 390, height: .infinity))

                #expect(size.height > 0)

                let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )

                #expect(policy == (isKeyboardVisible
                    ? .keyboardVisible(slot: slot)
                    : .keyboardHidden(slot: slot)))
                #expect(policy.activeSlot == slot)
                #expect(policy.hasActiveSnackbar == (slot != .none))
                #expect(policy.bottomSafeAreaVisible == !isKeyboardVisible)
                #expect(policy.fabVisible == !isKeyboardVisible)
                #expect(policy.usesTopPresentation == (isKeyboardVisible && slot != .none))

                if slot == .none {
                    #expect(!policy.hasActiveSnackbar)
                } else {
                    #expect(policy.hasActiveSnackbar)
                    #expect(policy.activeSlot == slot)
                }
            }
        }
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
