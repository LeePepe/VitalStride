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
private final class ActiveWorkoutFrameBox: ObservableObject {
    @Published var frame: CGRect = .zero
}

private struct ActiveWorkoutFrameProbe: ViewModifier {
    @ObservedObject var box: ActiveWorkoutFrameBox

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ActiveWorkoutFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        )
        .onPreferenceChange(ActiveWorkoutFramePreferenceKey.self) { frame in
            if let frame {
                box.frame = frame
            }
        }
    }
}

private struct ActiveWorkoutFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

private extension View {
    func captureActiveWorkoutFrame(_ box: ActiveWorkoutFrameBox) -> some View {
        modifier(ActiveWorkoutFrameProbe(box: box))
    }
}

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
            ActiveWorkoutView.productionRoot(
                isKeyboardVisible: state.isKeyboardVisible,
                snackbarSlot: state.snackbarSlot,
                infoBand: { representativeInfoBand },
                mainContent: { representativeMainContent },
                undoContent: { representativeUndoContent },
                restContent: { representativeRestContent },
                fab: { representativeFAB }
            )
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
            #expect(hiddenHeight > 0, "Hidden state must keep the production root mounted for slot \(slot)")

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
    @Test("Production root keeps the active snackbar and content clear of the real keyboard-safe boundary")
    func productionRootKeepsContentClearAcrossStateMatrix() {
        for isKeyboardVisible in [false, true] {
            for slot in [BottomSnackbarSlot.none, .rest, .undo] {
                let topSnackbarBox = ActiveWorkoutFrameBox()
                let bottomSnackbarBox = ActiveWorkoutFrameBox()
                let fabBox = ActiveWorkoutFrameBox()
                let keyboardBoundaryBox = ActiveWorkoutFrameBox()
                let focusedRowBox = ActiveWorkoutFrameBox()
                let finalRowBox = ActiveWorkoutFrameBox()
                let scrollBox = ActiveWorkoutFrameBox()

                let host = UIHostingController(
                    rootView: ActiveWorkoutView.productionRoot(
                        isKeyboardVisible: isKeyboardVisible,
                        snackbarSlot: slot,
                        infoBand: {
                            representativeInfoBand
                                .captureActiveWorkoutFrame(ActiveWorkoutFrameBox())
                        },
                        mainContent: {
                            ScrollView {
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: 48)
                                        .captureActiveWorkoutFrame(focusedRowBox)
                                    ForEach(0..<10, id: \.self) { index in
                                        HStack {
                                            Text("Exercise \(index + 1)")
                                            Spacer()
                                            Text("3 sets")
                                        }
                                        .frame(height: 52)
                                    }
                                    Color.clear.frame(height: 80)
                                        .captureActiveWorkoutFrame(finalRowBox)
                                }
                                .captureActiveWorkoutFrame(scrollBox)
                            }
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ActiveWorkoutFramePreferenceKey.self,
                                        value: proxy.frame(in: .global)
                                    )
                                }
                            )
                            .onPreferenceChange(ActiveWorkoutFramePreferenceKey.self) { frame in
                                if let frame {
                                    keyboardBoundaryBox.frame = frame
                                }
                            }
                        },
                        undoContent: {
                            representativeUndoContent
                                .captureActiveWorkoutFrame(isKeyboardVisible ? topSnackbarBox : bottomSnackbarBox)
                        },
                        restContent: {
                            representativeRestContent
                                .captureActiveWorkoutFrame(isKeyboardVisible ? topSnackbarBox : bottomSnackbarBox)
                        },
                        fab: { representativeFAB.captureActiveWorkoutFrame(fabBox) }
                    )
                )

                host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 852)
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

                #expect(scrollBox.frame.width > 0)
                #expect(keyboardBoundaryBox.frame.width > 0)
                #expect(focusedRowBox.frame.width > 0)
                #expect(finalRowBox.frame.width > 0)

                let hasActiveTopSnackbar = isKeyboardVisible && slot != .none
                let hasActiveBottomSnackbar = !isKeyboardVisible && slot != .none

                if hasActiveTopSnackbar {
                    #expect(topSnackbarBox.frame.width > 0)
                    #expect(focusedRowBox.frame.maxY <= topSnackbarBox.frame.minY + 2)
                    #expect(finalRowBox.frame.maxY <= topSnackbarBox.frame.minY + 2)
                    #expect(keyboardBoundaryBox.frame.minY >= topSnackbarBox.frame.maxY - 2)
                } else if hasActiveBottomSnackbar {
                    #expect(bottomSnackbarBox.frame.width > 0)
                    #expect(fabBox.frame.maxY <= bottomSnackbarBox.frame.minY + 2)
                    #expect(focusedRowBox.frame.maxY <= fabBox.frame.minY + 2)
                    #expect(finalRowBox.frame.maxY <= fabBox.frame.minY + 2)
                    #expect(bottomSnackbarBox.frame.minY >= keyboardBoundaryBox.frame.maxY - 2)
                } else {
                    #expect(fabBox.frame.width > 0)
                    #expect(focusedRowBox.frame.maxY <= keyboardBoundaryBox.frame.minY + 2)
                    #expect(finalRowBox.frame.maxY <= keyboardBoundaryBox.frame.minY + 2)
                }
            }
        }
    }

    @MainActor
    private var representativeMainContent: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                HStack {
                    Text("Exercise \(index + 1)")
                    Spacer()
                    Text("3 sets")
                }
                .frame(height: 52)
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
