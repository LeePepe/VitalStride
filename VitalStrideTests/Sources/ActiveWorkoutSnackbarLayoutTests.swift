import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

@MainActor
private final class ActiveWorkoutFrameTracker {
    var frames: [String: CGRect] = [:]

    func set(_ frame: CGRect, for id: String) {
        frames[id] = frame
    }

    func frame(for id: String) -> CGRect? {
        frames[id]
    }
}

private struct ActiveWorkoutFrameValueKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ActiveWorkoutFrameCaptureModifier: ViewModifier {
    let id: String
    let tracker: ActiveWorkoutFrameTracker

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ActiveWorkoutFrameValueKey.self,
                        value: [id: proxy.frame(in: .global)]
                    )
                }
            )
            .onPreferenceChange(ActiveWorkoutFrameValueKey.self) { frames in
                if let frame = frames[id] {
                    tracker.set(frame, for: id)
                }
            }
    }
}

private extension View {
    func captureActiveWorkoutFrame(id: String, tracker: ActiveWorkoutFrameTracker) -> some View {
        modifier(ActiveWorkoutFrameCaptureModifier(id: id, tracker: tracker))
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
        let tracker: ActiveWorkoutFrameTracker

        var body: some View {
            ActiveWorkoutView.productionRoot(
                isKeyboardVisible: state.isKeyboardVisible,
                snackbarSlot: state.snackbarSlot,
                topFrameProbe: { tracker.set($0, for: "topPresentation") },
                bottomFrameProbe: { tracker.set($0, for: "bottomPresentation") },
                mainContentFrameProbe: { tracker.set($0, for: "mainContent") },
                infoBand: {
                    representativeInfoBand
                        .captureActiveWorkoutFrame(id: "infoBand", tracker: tracker)
                },
                mainContent: {
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 48)
                                .captureActiveWorkoutFrame(id: "focusedRow", tracker: tracker)
                            ForEach(0..<10, id: \.self) { index in
                                HStack {
                                    Text("Exercise \(index + 1)")
                                    Spacer()
                                    Text("3 sets")
                                }
                                .frame(height: 52)
                            }
                            Color.clear.frame(height: 80)
                                .captureActiveWorkoutFrame(id: "finalRow", tracker: tracker)
                        }
                    }
                    .captureActiveWorkoutFrame(id: "scrollViewport", tracker: tracker)
                },
                undoContent: {
                    representativeUndoContent
                        .captureActiveWorkoutFrame(id: "undoContent", tracker: tracker)
                },
                restContent: {
                    representativeRestContent
                        .captureActiveWorkoutFrame(id: "restContent", tracker: tracker)
                },
                fab: {
                    if !state.isKeyboardVisible {
                        representativeFAB
                            .captureActiveWorkoutFrame(id: "fab", tracker: tracker)
                    }
                }
            )
        }
    }

    @MainActor
    @Test("Single production root stays mounted across hidden→visible→hidden transitions")
    func productionRootStaysMountedAcrossTransitions() {
        let state = ProductionRootState()
        let tracker = ActiveWorkoutFrameTracker()
        let host = UIHostingController(rootView: ProductionRoot(state: state, tracker: tracker))

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
                let tracker = ActiveWorkoutFrameTracker()
                let host = UIHostingController(rootView: ProductionRoot(state: state, tracker: tracker))
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
    @Test("Production root keeps the active snackbar above the real keyboard-safe content boundary")
    func productionRootKeepsContentClearAcrossStateMatrix() {
        for isKeyboardVisible in [false, true] {
            for slot in [BottomSnackbarSlot.none, .rest, .undo] {
                let tracker = ActiveWorkoutFrameTracker()
                let state = ProductionRootState(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )
                let host = UIHostingController(rootView: ProductionRoot(state: state, tracker: tracker))

                host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 852)
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

                let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )

                let topPresentation = tracker.frame(for: "topPresentation") ?? .zero
                let bottomPresentation = tracker.frame(for: "bottomPresentation") ?? .zero
                let mainContent = tracker.frame(for: "mainContent") ?? .zero
                let focusedRow = tracker.frame(for: "focusedRow") ?? .zero
                let finalRow = tracker.frame(for: "finalRow") ?? .zero
                let fab = tracker.frame(for: "fab") ?? .zero

                if isKeyboardVisible && slot != .none {
                    #expect(policy.usesTopPresentation)
                    #expect(topPresentation.width > 0)
                    #expect(mainContent.minY >= topPresentation.maxY - 2)
                    #expect(focusedRow.minY >= topPresentation.maxY - 2)
                    #expect(finalRow.minY >= topPresentation.maxY - 2)
                    #expect(fab.width == 0 || fab.height == 0 || !policy.fabVisible)
                } else if !isKeyboardVisible && slot != .none {
                    #expect(!policy.usesTopPresentation)
                    #expect(bottomPresentation.width > 0)
                    #expect(fab.width > 0)
                    #expect(fab.maxY <= bottomPresentation.minY + 2)
                    #expect(focusedRow.maxY <= bottomPresentation.minY + 2)
                    #expect(finalRow.maxY <= bottomPresentation.minY + 2)
                } else {
                    #expect(!policy.hasActiveSnackbar)
                    #expect(!policy.usesTopPresentation)
                    #expect(fab.width == 0 || fab.height == 0 || !policy.fabVisible)
                    #expect(mainContent.minY >= topPresentation.maxY - 2)
                    #expect(focusedRow.minY >= topPresentation.maxY - 2)
                    #expect(finalRow.minY >= topPresentation.maxY - 2)
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
