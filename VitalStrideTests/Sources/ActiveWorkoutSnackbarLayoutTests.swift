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
    private final class ScrollProxyHolder {
        var proxy: ScrollViewProxy?
    }

    @MainActor
    private final class ProductionRootState: ObservableObject {
        @Published var isKeyboardVisible: Bool
        @Published var snackbarSlot: BottomSnackbarSlot
        @Published var shouldScrollToFinalRow: Bool

        init(isKeyboardVisible: Bool = false, snackbarSlot: BottomSnackbarSlot = .none, shouldScrollToFinalRow: Bool = false) {
            self.isKeyboardVisible = isKeyboardVisible
            self.snackbarSlot = snackbarSlot
            self.shouldScrollToFinalRow = shouldScrollToFinalRow
        }
    }

    @MainActor
    private struct ProductionRoot: View {
        @ObservedObject var state: ProductionRootState
        let tracker: ActiveWorkoutFrameTracker
        let scrollProxyHolder: ScrollProxyHolder

        init(state: ProductionRootState, tracker: ActiveWorkoutFrameTracker, scrollProxyHolder: ScrollProxyHolder = ScrollProxyHolder()) {
            self.state = state
            self.tracker = tracker
            self.scrollProxyHolder = scrollProxyHolder
        }

        var body: some View {
            ActiveWorkoutView.productionRoot(
                isKeyboardVisible: state.isKeyboardVisible,
                snackbarSlot: state.snackbarSlot,
                topFrameProbe: { tracker.set($0, for: "topPresentation") },
                bottomFrameProbe: { tracker.set($0, for: "bottomPresentation") },
                rootFrameProbe: { tracker.set($0, for: "rootContainer") },
                fabFrameProbe: { tracker.set($0, for: "fab") },
                mainContentFrameProbe: { tracker.set($0, for: "mainContent") },
                infoBand: {
                    ActiveWorkoutSnackbarLayoutTests.representativeInfoBand
                        .captureActiveWorkoutFrame(id: "infoBand", tracker: tracker)
                },
                mainContent: {
                    ScrollViewReader { proxy in
                        let _ = {
                            scrollProxyHolder.proxy = proxy
                        }()
                        return ScrollView {
                            VStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { index in
                                    HStack {
                                        Text("Exercise \(index + 1)")
                                        Spacer()
                                        Text("3 sets")
                                    }
                                    .frame(height: 52)
                                }
                                Color.clear.frame(height: 48)
                                    .captureActiveWorkoutFrame(id: "focusedRow", tracker: tracker)
                                    .id("focusedRow")
                                ForEach(7..<10, id: \.self) { index in
                                    HStack {
                                        Text("Exercise \(index + 1)")
                                        Spacer()
                                        Text("3 sets")
                                    }
                                    .frame(height: 52)
                                }
                                Color.clear.frame(height: 80)
                                    .captureActiveWorkoutFrame(id: "finalRow", tracker: tracker)
                                    .id("finalRow")
                            }
                            .padding(.bottom, 88)
                        }
                        .onAppear {
                            guard state.shouldScrollToFinalRow else { return }
                            let scroll = {
                                proxy.scrollTo("finalRow", anchor: .bottom)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("finalRow", anchor: .bottom)
                                }
                            }
                            DispatchQueue.main.async(execute: scroll)
                        }
                        .onChange(of: state.shouldScrollToFinalRow) { _, shouldScroll in
                            guard shouldScroll else { return }
                            DispatchQueue.main.async {
                                proxy.scrollTo("finalRow", anchor: .bottom)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("finalRow", anchor: .bottom)
                                }
                            }
                        }
                        .captureActiveWorkoutFrame(id: "scrollViewport", tracker: tracker)
                    }
                },
                undoContent: {
                    ActiveWorkoutSnackbarLayoutTests.representativeUndoContent
                        .captureActiveWorkoutFrame(id: "undoContent", tracker: tracker)
                },
                restContent: {
                    ActiveWorkoutSnackbarLayoutTests.representativeRestContent
                        .captureActiveWorkoutFrame(id: "restContent", tracker: tracker)
                },
                fab: {
                    if !state.isKeyboardVisible {
                        ActiveWorkoutSnackbarLayoutTests.representativeFAB
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

            let hiddenHeight = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.infinity)).height
            #expect(hiddenHeight > 0, "Hidden state must keep the production root mounted for slot \(slot)")
            if slot != .none {
                let hiddenBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                let hiddenRoot = tracker.frame(for: "rootContainer") ?? .zero
                #expect(hiddenBottom.width > 0 || hiddenBottom.height > 0, "Hidden state must keep the bottom subtree mounted for slot \(slot)")
                #expect(hiddenRoot.width > 0 && hiddenRoot.height > 0, "Hidden root geometry must remain mounted for slot \(slot)")
            }

            state.isKeyboardVisible = true
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

            let visibleHeight = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.infinity)).height
            #expect(visibleHeight > 0, "Visible state must keep the root mounted for slot \(slot)")
            if slot != .none {
                let visibleBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                let visibleRoot = tracker.frame(for: "rootContainer") ?? .zero
                #expect(visibleBottom.width > 0 || visibleBottom.height > 0, "Visible state must keep the bottom subtree mounted for slot \(slot)")
                #expect(visibleRoot.width > 0 && visibleRoot.height > 0, "Visible root geometry must remain mounted for slot \(slot)")
            }
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

            let hiddenAgain = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.infinity)).height
            #expect(hiddenAgain > 0, "The same root must survive the visible→hidden transition for slot \(slot)")
            if slot != .none {
                let hiddenAgainBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                let hiddenAgainRoot = tracker.frame(for: "rootContainer") ?? .zero
                #expect(hiddenAgainBottom.width > 0 || hiddenAgainBottom.height > 0, "The hidden return must keep the bottom subtree mounted for slot \(slot)")
                #expect(hiddenAgainRoot.width > 0 && hiddenAgainRoot.height > 0, "The hidden return must keep root geometry mounted for slot \(slot)")
            }
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
                let size = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.infinity))

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
                    snackbarSlot: slot,
                    shouldScrollToFinalRow: true
                )
                let scrollProxyHolder = ScrollProxyHolder()
                let host = UIHostingController(rootView: ProductionRoot(state: state, tracker: tracker, scrollProxyHolder: scrollProxyHolder))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 852))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                for _ in 0..<10 {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                    scrollProxyHolder.proxy?.scrollTo("finalRow", anchor: .bottom)
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                for _ in 0..<10 {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                    scrollProxyHolder.proxy?.scrollTo("finalRow", anchor: .bottom)
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                }

                let policy = ActiveWorkoutSnackbarLayout.resolvePolicy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )

                let topPresentation = tracker.frame(for: "topPresentation") ?? .zero
                let bottomPresentation = tracker.frame(for: "bottomPresentation") ?? .zero
                let mainContent = tracker.frame(for: "mainContent") ?? .zero
                let scrollViewport = tracker.frame(for: "scrollViewport") ?? .zero
                let focusedRow = tracker.frame(for: "focusedRow") ?? .zero
                let finalRow = tracker.frame(for: "finalRow") ?? .zero
                let fab = tracker.frame(for: "fab") ?? .zero

                if isKeyboardVisible && slot != .none {
                    #expect(policy.usesTopPresentation)
                    #expect(topPresentation.width > 0)
                    #expect(mainContent.minY >= topPresentation.maxY - 2)
                    #expect(focusedRow.minY >= scrollViewport.minY - 2)
                    #expect(focusedRow.maxY <= scrollViewport.maxY + 2)
                    #expect(finalRow.minY >= scrollViewport.minY - 2)
                    #expect(finalRow.maxY <= scrollViewport.maxY + 2)
                    #expect(fab.width == 0 || fab.height == 0 || !policy.fabVisible)
                } else if !isKeyboardVisible && slot != .none {
                    #expect(!policy.usesTopPresentation)
                    #expect(bottomPresentation.width > 0)
                    #expect(fab.width > 0)
                    #expect(fab.maxY <= bottomPresentation.minY + 2)
                    #expect(focusedRow.maxY <= bottomPresentation.minY + 2)
                    #expect(finalRow.maxY <= bottomPresentation.minY + 2)
                } else if !isKeyboardVisible {
                    #expect(!policy.hasActiveSnackbar)
                    #expect(!policy.usesTopPresentation)
                    #expect(policy.fabVisible)
                    #expect(fab.width > 0)
                    #expect(fab.height > 0)
                    #expect(focusedRow.minY >= scrollViewport.minY - 2)
                    #expect(focusedRow.maxY <= fab.minY + 2)
                    #expect(finalRow.minY >= scrollViewport.minY - 2)
                    #expect(finalRow.maxY <= fab.minY + 2)
                    #expect(finalRow.maxY <= scrollViewport.maxY + 2)
                } else {
                    #expect(!policy.hasActiveSnackbar)
                    #expect(!policy.usesTopPresentation)
                    #expect(fab.width == 0 || fab.height == 0 || !policy.fabVisible)
                    #expect(focusedRow.minY >= scrollViewport.minY - 2)
                    #expect(focusedRow.maxY <= scrollViewport.maxY + 2)
                    #expect(finalRow.minY >= scrollViewport.minY - 2)
                    #expect(finalRow.maxY <= scrollViewport.maxY + 2)
                }
            }
        }
    }

    @MainActor
    @Test("Keyboard transitions are driven by a single root animation owner")
    func keyboardTransitionsHaveSingleRootAnimationOwner() {
        for slot in [BottomSnackbarSlot.none, .rest, .undo] {
            let state = ProductionRootState(
                isKeyboardVisible: false,
                snackbarSlot: slot,
                shouldScrollToFinalRow: true
            )
            let tracker = ActiveWorkoutFrameTracker()
            let scrollProxyHolder = ScrollProxyHolder()
            let host = UIHostingController(rootView: ProductionRoot(state: state, tracker: tracker, scrollProxyHolder: scrollProxyHolder))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 852))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let hiddenBefore = (tracker.frame(for: "rootContainer") ?? .zero).height
            #expect(hiddenBefore > 0, "Hidden root geometry must remain mounted for slot \(slot)")
            if slot != .none {
                let hiddenBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                #expect(hiddenBottom.width > 0 || hiddenBottom.height > 0, "Hidden bottom subtree must remain mounted for slot \(slot)")
            }

            state.isKeyboardVisible = true
            var visibleTransitionHeights: [CGFloat] = [hiddenBefore]
            for _ in 0..<6 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                visibleTransitionHeights.append((tracker.frame(for: "rootContainer") ?? .zero).height)
            }

            let visibleLast = visibleTransitionHeights.last ?? hiddenBefore
            let visibleBounces = visibleTransitionHeights.dropLast().filter { abs($0 - visibleLast) > 2 }
            #expect(visibleBounces.count <= 1, "Visible transition must settle through a single root-owned animation for slot \(slot)")
            #expect(visibleLast > 0)
            if slot != .none {
                let visibleBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                #expect(visibleBottom.width > 0 || visibleBottom.height > 0, "Visible bottom subtree must remain mounted for slot \(slot)")
            }

            state.isKeyboardVisible = false
            var hiddenTransitionHeights: [CGFloat] = [visibleLast]
            for _ in 0..<6 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                hiddenTransitionHeights.append((tracker.frame(for: "rootContainer") ?? .zero).height)
            }

            let hiddenLast = hiddenTransitionHeights.last ?? visibleLast
            let hiddenBounces = hiddenTransitionHeights.dropLast().filter { abs($0 - hiddenLast) > 2 }
            #expect(hiddenBounces.count <= 1, "Hidden transition must settle through a single root-owned animation for slot \(slot)")
            #expect(hiddenLast > 0)
            if slot != .none {
                let hiddenAfterBottom = tracker.frame(for: "bottomPresentation") ?? .zero
                #expect(hiddenAfterBottom.width > 0 || hiddenAfterBottom.height > 0, "Hidden return must keep the bottom subtree mounted for slot \(slot)")
            }
        }
    }

    @MainActor
    static var representativeMainContent: some View {
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
    static var representativeInfoBand: some View {
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
    static var representativeUndoContent: some View {
        HStack {
            Text("Undo")
            Spacer()
            Button("Undo") {}
        }
        .padding(12)
        .frame(height: 56)
    }

    @MainActor
    static var representativeRestContent: some View {
        HStack {
            Text("Rest")
            Spacer()
            Button("Skip") {}
        }
        .padding(12)
        .frame(height: 56)
    }

    @MainActor
    static var representativeFAB: some View {
        Color.clear
            .frame(width: 60, height: 60)
            .padding()
    }
}
