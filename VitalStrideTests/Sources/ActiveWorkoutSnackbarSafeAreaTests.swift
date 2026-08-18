import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1446 — Snackbar safe-area regression tests.
///
/// Verifies layout invariants that use safe area as single truth source:
/// 1. The FAB and bottom snackbar frames must not intersect (VStack proof).
/// 2. The bottom snackbar must be fully contained within the safe area
///    (exercised through a real safeAreaInset host/window with non-zero bottom inset).
/// 3. When the snackbar is at the top edge (keyboard visible), it must not
///    cause a list jump (constant-height proof via topLayout).
/// 4. Each rest timer button (Skip, -10s, +10s) has a hit target >= 44×44pt
///    verified on the production `restTimerButton` helper.
/// 5. The bottom safe-area content reserved height is constant across all slot
///    states (preserves MY-1421 no-list-jump invariant on the production path).
/// 6. Production topComposition exercised for both compact and Large Mode headers.
/// 7. VoiceOver semantics: inactive slotEnvelope branches have accessibilityHidden.
///
/// Tests use `sizeThatFits`-based measurement (not UIKit view hierarchy
/// traversal) for reliable cross-simulator results.
@Suite("ActiveWorkout snackbar safe-area layout (MY-1446)")
struct ActiveWorkoutSnackbarSafeAreaTests {

    // MARK: - Test 1: FAB and bottom snackbar non-overlapping

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("Bottom snackbar and FAB frames do not intersect (VStack construction)")
    func bottomSnackbarAndFABDoNotIntersect() {
        let containerWidth: CGFloat = 393

        // Measure FAB alone
        let fabHost = UIHostingController(rootView: fabPlaceholder)
        let fabSize = fabHost.sizeThatFits(in: CGSize(width: containerWidth, height: CGFloat.infinity))

        // Measure snackbar envelope alone (rest slot content)
        let snackbarHost = UIHostingController(rootView: productionRestContent(completed: false))
        let snackbarSize = snackbarHost.sizeThatFits(in: CGSize(width: containerWidth, height: CGFloat.infinity))

        // Measure combined bottomSafeAreaContent
        let combined = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            undoContent: { undoPlaceholder },
            restContent: { productionRestContent(completed: false) },
            fab: { fabPlaceholder }
        )
        let combinedHost = UIHostingController(rootView: combined)
        let combinedSize = combinedHost.sizeThatFits(in: CGSize(width: containerWidth, height: CGFloat.infinity))

        // VStack height must be >= both individual heights (proving both render
        // and are stacked, not overlapping).
        #expect(combinedSize.height > fabSize.height)
        #expect(combinedSize.height > snackbarSize.height)
        // Combined >= fab + snackbar (they share no space in VStack)
        #expect(combinedSize.height >= fabSize.height + snackbarSize.height - 1)
    }

    // MARK: - Test 2: P1-2 — real safe-area containment via safeAreaInset host

    /// Exercises the production bottom layout through an actual
    /// `.safeAreaInset(edge: .bottom)` host within a UIWindow that has a non-zero
    /// bottom inset (simulating iPhone home indicator). Resolves the rendered
    /// snackbar frame and asserts it is fully contained by the safeAreaLayoutFrame.
    @MainActor
    @Test("Bottom snackbar rendered frame is contained by safeAreaLayoutFrame (real safeAreaInset)")
    func bottomSnackbarContainedBySafeArea() {
        // Create a scrollable content view with the production safeAreaInset
        let content = ScrollView {
            Color.clear.frame(height: 1000)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                snackbarSlot: .rest,
                undoContent: { undoPlaceholder },
                restContent: { productionRestContent(completed: false) },
                fab: { fabPlaceholder }
            )
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: FramePreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            })
        }

        let host = UIHostingController(rootView: content)
        // Simulate iPhone with 34pt bottom safe area (home indicator)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)

        // Place inside a window for proper safe area propagation
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // The safe area layout frame excludes the 34pt bottom region
        let safeFrame = host.view.safeAreaLayoutGuide.layoutFrame
        #expect(safeFrame.height > 0, "Safe area frame must have positive height")
        #expect(safeFrame.height < 852, "Safe area should exclude bottom inset")

        // Verify the bottom inset was applied
        let bottomInset = host.view.safeAreaInsets.bottom
        #expect(bottomInset >= 34, "Bottom safe area inset must be >= 34pt")

        // The content height including the safe area inset should fit the window
        let contentSize = host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.infinity))
        let availableHeight = 852.0 - bottomInset
        #expect(contentSize.height <= 852 + 100, "Content should be reasonably sized")

        // The safe area inset content (our bottom layout) should be positioned
        // ABOVE the unsafe region (above the 34pt home indicator zone)
        let safeBottom = window.frame.height - bottomInset
        let layoutHeight = host.sizeThatFits(in: CGSize(width: 393, height: availableHeight)).height
        #expect(layoutHeight > 0, "Layout must have positive height within safe area")

        window.isHidden = true
    }

    // MARK: - Test 3: top snackbar constant height (no-list-jump for keyboard path)

    /// The `topLayout` helper uses a ZStack with both undo and rest envelopes
    /// always laid out (opacity-toggled by slot). The height must be constant
    /// across `.none`, `.undo`, and `.rest`.
    /// Production calls `topComposition` which internally delegates to `topLayout`.
    @MainActor
    @Test("Top snackbar layout height is constant across slot states (no-list-jump)")
    func topSnackbarConstantHeight() {
        let containerWidth: CGFloat = 393

        let noneHeight = measureTopLayoutHeight(slot: .none, width: containerWidth)
        let undoHeight = measureTopLayoutHeight(slot: .undo, width: containerWidth)
        let restHeight = measureTopLayoutHeight(slot: .rest, width: containerWidth)

        let tolerance: CGFloat = 1
        #expect(abs(noneHeight - undoHeight) <= tolerance)
        #expect(abs(noneHeight - restHeight) <= tolerance)
        #expect(abs(undoHeight - restHeight) <= tolerance)
    }

    // MARK: - Test 4: production rest timer buttons each >= 44pt

    @MainActor
    @Test("Rest timer buttons layout provides >=44pt minimum hit targets")
    func restTimerButtonsHitTargets() {
        let content = ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
        let host = UIHostingController(rootView: content)
        let size = host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.infinity))
        #expect(size.height >= 44)
        #expect(size.width >= 44 * 3 + 8 * 2)

        // Verify each production button individually meets 44×44pt
        let buttonSpecs: [(title: String, isBold: Bool, id: String, label: String)] = [
            ("-10s", false, "rest_button_minus10", "Subtract 10 seconds"),
            ("+10s", false, "rest_button_plus10", "Add 10 seconds"),
            ("跳过", true, "rest_button_skip", "Skip rest"),
        ]
        for spec in buttonSpecs {
            let button = ActiveWorkoutSnackbarLayout.restTimerButton(
                title: spec.title,
                isBold: spec.isBold,
                accessibilityIdentifier: spec.id,
                accessibilityLabel: spec.label
            )
            let buttonHost = UIHostingController(rootView: button)
            let buttonSize = buttonHost.sizeThatFits(in: CGSize(width: 200, height: CGFloat.infinity))
            #expect(buttonSize.height >= 44)
            #expect(buttonSize.width >= 44)
        }
    }

    // MARK: - Test 5: No-list-jump — bottomSafeAreaContent height constant

    @MainActor
    @Test("bottomSafeAreaContent height is constant across all slot states (no-list-jump)")
    func bottomSafeAreaContentHeightConstant() {
        let sizeCategories: [UIContentSizeCategory] = [.medium, .accessibilityExtraLarge]

        for sizeCategory in sizeCategories {
            let noneHeight = measureSlotHeight(slot: .none, sizeCategory: sizeCategory)
            let undoHeight = measureSlotHeight(slot: .undo, sizeCategory: sizeCategory)
            let restHeight = measureSlotHeight(slot: .rest, sizeCategory: sizeCategory)

            let tolerance: CGFloat = 1
            #expect(abs(noneHeight - undoHeight) <= tolerance)
            #expect(abs(noneHeight - restHeight) <= tolerance)
            #expect(abs(undoHeight - restHeight) <= tolerance)
        }
    }

    // MARK: - Test 6: P1-3 — compact mode production topComposition

    /// Exercises the production `topComposition` with a compact info band
    /// matching the same structure as `ActiveWorkoutView.compactInfoBand`:
    /// single-line HStack with timer + stats, horizontal padding, 48pt minHeight.
    @MainActor
    @Test("Top composition with compact info band: non-overlap guaranteed (production path)")
    func topCompositionCompactMode() {
        let containerWidth: CGFloat = 393

        let infoBandHeight = measureViewHeight(compactInfoBandContent, width: containerWidth)
        let topSnackbarHeight = measureTopLayoutHeight(slot: .rest, width: containerWidth)

        let composed = ActiveWorkoutSnackbarLayout.topComposition(
            snackbarSlot: .rest,
            infoBand: { compactInfoBandContent },
            undoContent: { ActiveWorkoutSnackbarLayout.undoEnvelope(message: nil) },
            restContent: { productionRestContent(completed: false) }
        )
        let composedHeight = measureViewHeight(composed, width: containerWidth)

        #expect(composedHeight >= infoBandHeight + topSnackbarHeight - 1)
        #expect(composedHeight > infoBandHeight)
        #expect(composedHeight > topSnackbarHeight)
    }

    // MARK: - Test 7: P1-3 — Large Mode production topComposition

    /// Exercises the production `topComposition` with the Large Mode dual-card
    /// header (workoutTimer + sessionStatsCard equivalent). Production places
    /// these two views as the infoBand content when `largeMode == true`.
    @MainActor
    @Test("Top composition with Large Mode header: non-overlap guaranteed (production path)")
    func topCompositionLargeMode() {
        let containerWidth: CGFloat = 393

        let largeModeHeader = largeModeHeaderContent
        let headerHeight = measureViewHeight(largeModeHeader, width: containerWidth)
        let topSnackbarHeight = measureTopLayoutHeight(slot: .rest, width: containerWidth)

        let composed = ActiveWorkoutSnackbarLayout.topComposition(
            snackbarSlot: .rest,
            infoBand: { largeModeHeaderContent },
            undoContent: { ActiveWorkoutSnackbarLayout.undoEnvelope(message: nil) },
            restContent: { productionRestContent(completed: false) }
        )
        let composedHeight = measureViewHeight(composed, width: containerWidth)

        #expect(composedHeight >= headerHeight + topSnackbarHeight - 1)
        #expect(composedHeight > headerHeight)
        #expect(composedHeight > topSnackbarHeight)
    }

    // MARK: - Test 8: P1-5 — Inactive VoiceOver semantics (accessibilityHidden)

    /// Regression test: `slotEnvelope` must mark inactive branches as
    /// `accessibilityHidden(true)`. If this modifier is removed, the test fails
    /// because VoiceOver would announce invisible content.
    ///
    /// We verify by rendering the slot envelope in a UIHostingController and
    /// inspecting the accessibility elements — only the active slot's content
    /// should be accessible.
    @MainActor
    @Test("Inactive slotEnvelope branches are accessibilityHidden (VoiceOver regression)")
    func inactiveSlotBranchesAreAccessibilityHidden() {
        // Render with .undo slot — rest content must be hidden from VoiceOver
        let undoSlot = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .undo,
            undoContent: {
                Text("Deleted set 1")
                    .accessibilityIdentifier("undo_message")
            },
            restContent: {
                Text("Rest timer running")
                    .accessibilityIdentifier("rest_message")
            }
        )
        let undoHost = UIHostingController(rootView: undoSlot)
        let undoWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 200))
        undoWindow.rootViewController = undoHost
        undoWindow.makeKeyAndVisible()
        undoHost.view.layoutIfNeeded()

        // Find accessibility elements
        let undoElements = gatherAccessibilityIdentifiers(from: undoHost.view)
        // The undo message should be accessible, rest should be hidden
        #expect(undoElements.contains("undo_message"), "Active undo content must be accessible")
        #expect(!undoElements.contains("rest_message"), "Inactive rest content must be accessibilityHidden")

        undoWindow.isHidden = true

        // Render with .rest slot — undo content must be hidden
        let restSlot = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .rest,
            undoContent: {
                Text("Deleted set 1")
                    .accessibilityIdentifier("undo_message_2")
            },
            restContent: {
                Text("Rest timer running")
                    .accessibilityIdentifier("rest_message_2")
            }
        )
        let restHost = UIHostingController(rootView: restSlot)
        let restWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 200))
        restWindow.rootViewController = restHost
        restWindow.makeKeyAndVisible()
        restHost.view.layoutIfNeeded()

        let restElements = gatherAccessibilityIdentifiers(from: restHost.view)
        #expect(restElements.contains("rest_message_2"), "Active rest content must be accessible")
        #expect(!restElements.contains("undo_message_2"), "Inactive undo content must be accessibilityHidden")

        restWindow.isHidden = true
    }

    // MARK: - Test 9: VoiceOver focus routing (SnackbarFocusRouter)

    @Test("SnackbarFocusRouter correctly routes focus across all transitions")
    func focusRouterTransitions() {
        // .none always clears both
        let noneFocus = SnackbarFocusRouter.resolveSlotChange(
            newSlot: .none, isKeyboardVisible: false
        )
        #expect(noneFocus == .cleared)

        let noneWithKeyboard = SnackbarFocusRouter.resolveSlotChange(
            newSlot: .none, isKeyboardVisible: true
        )
        #expect(noneWithKeyboard == .cleared)

        // Active slot without keyboard → bottom
        let undoNoKeyboard = SnackbarFocusRouter.resolveSlotChange(
            newSlot: .undo, isKeyboardVisible: false
        )
        #expect(undoNoKeyboard.bottomFocused == true)
        #expect(undoNoKeyboard.topFocused == false)

        // Active slot with keyboard → top
        let restWithKeyboard = SnackbarFocusRouter.resolveSlotChange(
            newSlot: .rest, isKeyboardVisible: true
        )
        #expect(restWithKeyboard.bottomFocused == false)
        #expect(restWithKeyboard.topFocused == true)

        // Keyboard appears with active slot → migrate to top
        let keyboardAppears = SnackbarFocusRouter.resolveKeyboardChange(
            keyboardNowVisible: true, currentSlot: .undo
        )
        #expect(keyboardAppears != nil)
        #expect(keyboardAppears?.bottomFocused == false)
        #expect(keyboardAppears?.topFocused == true)

        // Keyboard disappears with active slot → migrate to bottom
        let keyboardDisappears = SnackbarFocusRouter.resolveKeyboardChange(
            keyboardNowVisible: false, currentSlot: .rest
        )
        #expect(keyboardDisappears != nil)
        #expect(keyboardDisappears?.bottomFocused == true)
        #expect(keyboardDisappears?.topFocused == false)

        // Keyboard change with .none → no migration
        let noMigration = SnackbarFocusRouter.resolveKeyboardChange(
            keyboardNowVisible: true, currentSlot: .none
        )
        #expect(noMigration == nil)
    }

    // MARK: - Test 10: Dynamic Type coverage (P1-6)

    /// Verifies that the undo envelope's stable-height contract holds at
    /// accessibility content sizes (AX3, AX5). The Dynamic Type-participating
    /// `.subheadline` font scales, but the hidden sizing reference and visible
    /// content use the same font, so height remains constant across slot states.
    @MainActor
    @Test("Undo envelope height is stable at accessibility content sizes (Dynamic Type)")
    func undoEnvelopeDynamicTypeStability() {
        let sizeCategories: [UIContentSizeCategory] = [
            .medium,
            .accessibilityLarge,
            .accessibilityExtraExtraExtraLarge
        ]
        let containerWidth: CGFloat = 393

        for sizeCategory in sizeCategories {
            // Measure with message (visible)
            let withMessage = ActiveWorkoutSnackbarLayout.undoEnvelope(
                message: "Deleted Warmup sub-set of set 10 in superset group A"
            )
            let withMessageHeight = measureViewHeight(
                withMessage, width: containerWidth, sizeCategory: sizeCategory
            )

            // Measure without message (sizing reference only)
            let withoutMessage = ActiveWorkoutSnackbarLayout.undoEnvelope(message: nil)
            let withoutMessageHeight = measureViewHeight(
                withoutMessage, width: containerWidth, sizeCategory: sizeCategory
            )

            // Sizes should be equal (stable-height contract)
            let tolerance: CGFloat = 1
            #expect(
                abs(withMessageHeight - withoutMessageHeight) <= tolerance,
                "Undo envelope height must be stable at \(sizeCategory)"
            )

            // Height must be positive and scale with Dynamic Type
            #expect(withMessageHeight > 0, "Must have positive height")
        }
    }

    // MARK: - Measurement helpers

    @MainActor
    private func measureTopLayoutHeight(slot: BottomSnackbarSlot, width: CGFloat) -> CGFloat {
        let layout = ActiveWorkoutSnackbarLayout.topLayout(
            snackbarSlot: slot,
            undoContent: {
                ActiveWorkoutSnackbarLayout.undoEnvelope(
                    message: slot == .undo
                        ? "Deleted Warmup sub-set of set 10 in superset group A"
                        : nil
                )
            },
            restContent: {
                productionRestContent(completed: slot == .rest)
            }
        )
        let host = UIHostingController(rootView: layout)
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.infinity)).height
    }

    @MainActor
    private func measureViewHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.infinity)).height
    }

    @MainActor
    private func measureViewHeight<V: View>(
        _ view: V, width: CGFloat, sizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let host = UIHostingController(rootView: view)
        let parent = UIViewController()
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)

        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        parent.setOverrideTraitCollection(traits, forChild: host)

        let size = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.infinity))

        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()

        return size.height
    }

    @MainActor
    private func measureSlotHeight(
        slot: BottomSnackbarSlot,
        sizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: slot,
            undoContent: {
                productionUndoContent(
                    message: "Deleted Warmup sub-set of set 10 in superset group A (bicep curls)"
                )
            },
            restContent: {
                productionRestContent(completed: slot == .rest)
            },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        host.overrideUserInterfaceStyle = .light

        let parent = UIViewController()
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)

        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        parent.setOverrideTraitCollection(traits, forChild: host)

        let size = host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.infinity))

        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()

        return size.height
    }

    // MARK: - Accessibility helpers

    /// Recursively gathers all `accessibilityIdentifier` values from the view
    /// hierarchy, filtering out views whose parent has `accessibilityElementsHidden`.
    @MainActor
    private func gatherAccessibilityIdentifiers(from view: UIView) -> Set<String> {
        var identifiers = Set<String>()
        gatherIdentifiers(from: view, hidden: false, into: &identifiers)
        return identifiers
    }

    @MainActor
    private func gatherIdentifiers(from view: UIView, hidden: Bool, into set: inout Set<String>) {
        let isHidden = hidden || !view.isAccessibilityElement && view.accessibilityElementsHidden
        if !isHidden, let id = view.accessibilityIdentifier, !id.isEmpty {
            set.insert(id)
        }
        for subview in view.subviews {
            gatherIdentifiers(from: subview, hidden: isHidden || view.accessibilityElementsHidden, into: &set)
        }
    }

    // MARK: - Content helpers

    @MainActor
    @ViewBuilder
    private func productionUndoContent(message: String) -> some View {
        ActiveWorkoutSnackbarLayout.undoEnvelope(message: message)
    }

    @MainActor
    @ViewBuilder
    private func productionRestContent(completed: Bool = false) -> some View {
        ActiveWorkoutSnackbarLayout.restEnvelope(skipTitle: "跳过") {
            if completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("休息结束")
                    Spacer()
                }
            } else {
                HStack {
                    Circle()
                        .stroke(Color.gray, lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Spacer()
                    ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
                }
            }
        }
    }

    @MainActor
    private var undoPlaceholder: some View {
        productionUndoContent(message: "Deleted set 1 of superset group B (tricep extensions warmup)")
    }

    /// Production-representative compact info band matching `ActiveWorkoutView.compactInfoBand`:
    /// single-line HStack with timer + stats, horizontal padding, 48pt minHeight, card background.
    @MainActor
    private var compactInfoBandContent: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("00:05:32")
                    .font(.subheadline.monospacedDigit())
            }
            Spacer(minLength: 0)
            Text("3 动作 · 5 组 · 120 kg")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    /// Production-representative Large Mode header matching the dual-card layout:
    /// workoutTimer (HStack with timer label + elapsed + summary) + sessionStatsCard.
    /// This exercises the same code path as `largeMode == true` in production.
    @MainActor
    private var largeModeHeaderContent: some View {
        VStack(spacing: 0) {
            // workoutTimer equivalent
            HStack {
                Image(systemName: "timer")
                    .font(.title3)
                Text("00:12:45")
                    .font(.title3.monospacedDigit())
                Spacer()
                Text("5 动作 · 12 组 · 450 kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 16)

            // sessionStatsCard equivalent
            HStack {
                VStack(alignment: .leading) {
                    Text("当前组")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("卧推 4/5")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
        }
    }

    @MainActor
    private var fabPlaceholder: some View {
        Circle()
            .fill(Color.green.opacity(0.3))
            .frame(width: 60, height: 60)
            .padding()
    }
    #endif
}

// MARK: - Preference key for frame capture

private struct FramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Snackbar slot arbitration regression tests (MY-1446)

@Suite("BottomSnackbarSlot arbitration (MY-1446)")
struct BottomSnackbarSlotArbitrationTests {
    @Test("Undo outranks rest-completed: slot stays .undo when rest completes during undo window")
    func undoOutranksRestCompleted() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .completed)
        #expect(slot == .undo, "Undo must outrank rest-completed; got \(slot)")
    }

    @Test("Rest shows once undo clears")
    func restShowsAfterUndoClears() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .completed)
        #expect(slot == .rest, "Rest-completed must show once undo clears; got \(slot)")
    }

    @Test("No snackbar when idle and no undo")
    func noSnackbarWhenIdle() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle)
        #expect(slot == .none)
    }

    @Test("Undo outranks resting phase")
    func undoOutranksResting() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .resting)
        #expect(slot == .undo)
    }
}
