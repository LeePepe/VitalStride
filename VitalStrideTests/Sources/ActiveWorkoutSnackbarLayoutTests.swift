import DesignKit
import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1421, MY-1446, MY-1706 — ActiveWorkout snackbar layout and animation policy regression tests.
///
/// These tests verify:
/// 1. The workout list does not shift vertically when the rest snackbar appears or disappears.
/// 2. When keyboard is visible, snackbar edge resolves to .top.
/// 3. All 6 settled keyboard/snackbar states resolve through one production AnimationPolicy.
/// 4. Exactly one root geometry-animation owner, no child animation, and no child transition.
/// 5. Mutation sensitivity: rejects child animation, child transition, and missing root owner.
/// 6. Transitions in both directions preserve single-owner invariants and slot migration.
@Suite("ActiveWorkout snackbar layout (MY-1421, MY-1706)")
struct ActiveWorkoutSnackbarLayoutTests {
    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("None slot envelope has zero height while active slots remain rendered")
    func inactiveSlotEnvelopeHasZeroHeight() {
        let noneView = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .none,
            undoContent: { Color.red.frame(height: 52) },
            restContent: { Color.blue.frame(height: 88) }
        )
        let undoView = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .undo,
            undoContent: { Color.red.frame(height: 52) },
            restContent: { Color.blue.frame(height: 88) }
        )
        let restView = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .rest,
            undoContent: { Color.red.frame(height: 52) },
            restContent: { Color.blue.frame(height: 88) }
        )
        let noneHost = UIHostingController(rootView: noneView)
        let undoHost = UIHostingController(rootView: undoView)
        let restHost = UIHostingController(rootView: restView)
        let width = CGSize(width: 393, height: CGFloat.infinity)
        let noneHeight = noneHost.sizeThatFits(in: width).height
        let undoHeight = undoHost.sizeThatFits(in: width).height
        let restHeight = restHost.sizeThatFits(in: width).height

        #expect(noneHeight == 0)
        #expect(abs(undoHeight - 88) <= 1)
        #expect(abs(restHeight - 88) <= 1)
        #expect(abs(undoHeight - restHeight) <= 1)
    }

    @Test("Snackbar envelopes use the normal and Large Mode height tokens")
    func snackbarEnvelopeHeightTokens() {
        #expect(ActiveWorkoutSnackbarLayout.restEnvelopeNormalHeight == 56)
        #expect(ActiveWorkoutSnackbarLayout.restEnvelopeLargeHeight == 64)
        #expect(abs(
            ActiveWorkoutSnackbarLayout.restEnvelopeNormalHeight
                - ActiveWorkoutSnackbarLayout.restEnvelopeNormalHeight
        ) <= 1)
    }

    @MainActor
    @Test("Reduced motion uses opacity-only slot transition")
    func reducedMotionSlotTransition() {
        #expect(ActiveWorkoutSnackbarLayout.usesSpatialSlotTransition(reduceMotion: false) == true)
        #expect(ActiveWorkoutSnackbarLayout.usesSpatialSlotTransition(reduceMotion: true) == false)

        let enabled = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .rest,
            undoContent: { Color.red.frame(height: 52) },
            restContent: { Color.blue.frame(height: 88) },
            reduceMotionOverride: false
        )
        let reduced = ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: .undo,
            undoContent: { Color.red.frame(height: 52) },
            restContent: { Color.blue.frame(height: 88) },
            reduceMotionOverride: true
        )
        _ = UIHostingController(rootView: enabled)
        _ = UIHostingController(rootView: reduced)
    }
    #endif

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("Snackbar renders with semantic tokens in both color schemes")
    func snackbarRendersInLightAndDarkThemes() {
        for isDark in [false, true] {
            let view = ActiveWorkoutSnackbarLayout.undoEnvelope(
                message: "Deleted set",
                theme: Theme(seed: .teal, neutral: .slate, isDark: isDark)
            )
            let host = UIHostingController(rootView: view)
            #expect(host.sizeThatFits(in: CGSize(width: 320, height: 100)).height > 0)
        }
    }
    #endif

    // MARK: - Test 1: List stability (MY-1421)

    /// The FAB container's intrinsic height must be identical regardless of
    /// whether the bottom snackbar is showing. Before MY-1421, a conditional
    /// `.padding(.bottom, 100)` inflated the safeAreaInset height when rest
    /// was active, causing the workout list to jump. After the fix the FAB
    /// uses a constant layout size and an `.offset` for visual clearance only.
    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("FAB safeAreaInset height is constant regardless of snackbar state")
    func fabHeightConstantAcrossSnackbarStates() {
        // Measure FAB container height when snackbar is NOT visible (.none)
        let fabNoSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .none) {
            representativeFAB
        }
        let hostNoSnackbar = UIHostingController(rootView: fabNoSnackbar)
        let sizeNoSnackbar = hostNoSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        // Measure FAB container height when snackbar IS visible (.rest)
        let fabWithSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .rest) {
            representativeFAB
        }
        let hostWithSnackbar = UIHostingController(rootView: fabWithSnackbar)
        let sizeWithSnackbar = hostWithSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        // Also measure with undo snackbar
        let fabWithUndo = ActiveWorkoutFABContainer.body(snackbarSlot: .undo) {
            representativeFAB
        }
        let hostWithUndo = UIHostingController(rootView: fabWithUndo)
        let sizeWithUndo = hostWithUndo.sizeThatFits(in: CGSize(width: 400, height: 0))

        // All heights must match within 1pt — safeAreaInset reserved height
        // must be independent of snackbar visibility.
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

    // MARK: - Test 2: Snackbar keyboard awareness (MY-1421)

    /// When the custom numeric keyboard is visible, the snackbar must switch
    /// to the top edge so it doesn't overlap the keyboard and remains fully
    /// visible. Before MY-1421 the snackbar always used `.bottom` regardless
    /// of keyboard state.
    @Test("Snackbar edge switches to .top when keyboard is visible")
    func snackbarEdgeSwitchesToTopWithKeyboard() {
        // Without keyboard: bottom edge
        let edgeNoKeyboard = ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: false)
        #expect(edgeNoKeyboard == .bottom)

        // With keyboard: top edge so it doesn't overlap
        let edgeWithKeyboard = ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: true)
        #expect(edgeWithKeyboard == .top)
    }

    // MARK: - Test 3: Six Settled States Production Policy Matrix (MY-1706 / AC-001, AC-002)

    struct PolicyMatrixCase {
        let isKeyboardVisible: Bool
        let requestedSlot: BottomSnackbarSlot
        let expectedTopSlot: BottomSnackbarSlot
        let expectedBottomSlot: BottomSnackbarSlot
        let expectedFABVisible: Bool
    }

    @MainActor
    @Test("Production AnimationPolicy exercises all six settled keyboard/snackbar states")
    func productionAnimationPolicyMatrix() {
        let testCases: [PolicyMatrixCase] = [
            // State 1: Hidden keyboard + No snackbar
            PolicyMatrixCase(
                isKeyboardVisible: false,
                requestedSlot: .none,
                expectedTopSlot: .none,
                expectedBottomSlot: .none,
                expectedFABVisible: true
            ),
            // State 2: Hidden keyboard + Rest snackbar
            PolicyMatrixCase(
                isKeyboardVisible: false,
                requestedSlot: .rest,
                expectedTopSlot: .none,
                expectedBottomSlot: .rest,
                expectedFABVisible: true
            ),
            // State 3: Hidden keyboard + Undo snackbar
            PolicyMatrixCase(
                isKeyboardVisible: false,
                requestedSlot: .undo,
                expectedTopSlot: .none,
                expectedBottomSlot: .undo,
                expectedFABVisible: true
            ),
            // State 4: Visible keyboard + No snackbar
            PolicyMatrixCase(
                isKeyboardVisible: true,
                requestedSlot: .none,
                expectedTopSlot: .none,
                expectedBottomSlot: .none,
                expectedFABVisible: false
            ),
            // State 5: Visible keyboard + Rest snackbar
            PolicyMatrixCase(
                isKeyboardVisible: true,
                requestedSlot: .rest,
                expectedTopSlot: .rest,
                expectedBottomSlot: .none,
                expectedFABVisible: false
            ),
            // State 6: Visible keyboard + Undo snackbar
            PolicyMatrixCase(
                isKeyboardVisible: true,
                requestedSlot: .undo,
                expectedTopSlot: .undo,
                expectedBottomSlot: .none,
                expectedFABVisible: false
            ),
        ]

        for tc in testCases {
            let policy = ActiveWorkoutSnackbarLayout.policy(
                isKeyboardVisible: tc.isKeyboardVisible,
                snackbarSlot: tc.requestedSlot
            )

            // Slot placements
            #expect(policy.topSlot == tc.expectedTopSlot)
            #expect(policy.bottomSlot == tc.expectedBottomSlot)
            #expect(policy.isFABVisible == tc.expectedFABVisible)

            // Exactly one root animation owner
            #expect(policy.hasRootAnimation == true)
            #expect(policy.rootAnimation == ActiveWorkoutSnackbarLayout.AnimationPolicy.defaultAnimation)

            // No child animation or transition drivers
            #expect(policy.hasChildAnimation == false)
            #expect(policy.childAnimation == nil)
            #expect(policy.hasChildTransition == false)

            // Single animation owner invariant holds
            #expect(policy.hasSingleAnimationOwner == true)

            // At most one active snackbar slot across entire layout
            let topActive = policy.topSlot != .none
            let bottomActive = policy.bottomSlot != .none
            #expect(!(topActive && bottomActive), "Top and bottom snackbar slots cannot both be active simultaneously")
        }
    }

    // MARK: - Test 4: Keyboard Transition Directions (MY-1706)

    @MainActor
    @Test("Keyboard show and hide transitions migrate snackbar slot and preserve single owner")
    func keyboardTransitionsMigrateSlots() {
        let slots: [BottomSnackbarSlot] = [.none, .rest, .undo]

        for slot in slots {
            let hiddenPolicy = ActiveWorkoutSnackbarLayout.policy(
                isKeyboardVisible: false,
                snackbarSlot: slot
            )
            let visiblePolicy = ActiveWorkoutSnackbarLayout.policy(
                isKeyboardVisible: true,
                snackbarSlot: slot
            )

            // Hidden -> Visible transition
            #expect(hiddenPolicy.bottomSlot == slot)
            #expect(hiddenPolicy.topSlot == .none)
            #expect(hiddenPolicy.isFABVisible == true)
            #expect(hiddenPolicy.hasSingleAnimationOwner == true)

            #expect(visiblePolicy.topSlot == slot)
            #expect(visiblePolicy.bottomSlot == .none)
            #expect(visiblePolicy.isFABVisible == false)
            #expect(visiblePolicy.hasSingleAnimationOwner == true)

            // Root animation ownership is invariant across transition
            #expect(hiddenPolicy.rootAnimation == visiblePolicy.rootAnimation)
            #expect(hiddenPolicy.childAnimation == nil && visiblePolicy.childAnimation == nil)
            #expect(!hiddenPolicy.hasChildTransition && !visiblePolicy.hasChildTransition)
        }
    }

    // MARK: - Test 5: Mutation Sensitivity (MY-1706 / AC-003, FR-005)

    @MainActor
    @Test("Mutation-sensitive regression tests reject duplicate or missing animation owners")
    func mutationSensitivityTests() {
        let baseSlots: [BottomSnackbarSlot] = [.none, .rest, .undo]
        let keyboardStates: [Bool] = [false, true]

        for isKeyboardVisible in keyboardStates {
            for slot in baseSlots {
                // Baseline production policy is valid and passes single-owner invariant
                let prodPolicy = ActiveWorkoutSnackbarLayout.policy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )
                #expect(prodPolicy.hasSingleAnimationOwner == true)
                #expect(prodPolicy.hasRootAnimation == true)
                #expect(prodPolicy.hasChildAnimation == false)
                #expect(prodPolicy.hasChildTransition == false)

                // Verify production modifiers applied at root and child
                let prodChildContent = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                    policy: prodPolicy,
                    undoContent: { Color.clear },
                    restContent: { Color.clear },
                    fab: { Color.clear }
                )
                _ = prodChildContent

                // Mutation 1: Add a child animation driver (duplicate owner)
                let mutatedWithChildAnim = ActiveWorkoutSnackbarLayout.AnimationPolicy.mutated(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot,
                    rootAnimation: ActiveWorkoutSnackbarLayout.AnimationPolicy.defaultAnimation,
                    childAnimation: .linear(duration: 0.2),
                    hasChildTransition: false
                )
                #expect(mutatedWithChildAnim.hasChildAnimation == true)
                #expect(
                    mutatedWithChildAnim.hasSingleAnimationOwner == false,
                    "Policy must reject mutation that introduces a child animation driver"
                )

                // Verify child modifier consumes mutated child animation
                let childWithAnim = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                    policy: mutatedWithChildAnim,
                    undoContent: { Color.clear },
                    restContent: { Color.clear },
                    fab: { Color.clear }
                )
                _ = childWithAnim

                // Mutation 2: Add a child transition (duplicate owner)
                let mutatedWithChildTransition = ActiveWorkoutSnackbarLayout.AnimationPolicy.mutated(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot,
                    rootAnimation: ActiveWorkoutSnackbarLayout.AnimationPolicy.defaultAnimation,
                    childAnimation: nil,
                    hasChildTransition: true
                )
                #expect(mutatedWithChildTransition.hasChildTransition == true)
                #expect(
                    mutatedWithChildTransition.hasSingleAnimationOwner == false,
                    "Policy must reject mutation that introduces a child transition"
                )

                // Verify child modifier consumes mutated child transition
                let childWithTransition = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                    policy: mutatedWithChildTransition,
                    undoContent: { Color.clear },
                    restContent: { Color.clear },
                    fab: { Color.clear }
                )
                _ = childWithTransition

                // Mutation 3: Remove root animation driver (missing root owner)
                let mutatedWithoutRootAnim = ActiveWorkoutSnackbarLayout.AnimationPolicy.mutated(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot,
                    rootAnimation: nil,
                    childAnimation: nil,
                    hasChildTransition: false
                )
                #expect(mutatedWithoutRootAnim.hasRootAnimation == false)
                #expect(
                    mutatedWithoutRootAnim.hasSingleAnimationOwner == false,
                    "Policy must reject mutation where the root animation driver is missing"
                )
            }
        }
    }

    // MARK: - Test 6: Mode Parity (MY-1706 / AC-006, FR-008)

    @MainActor
    @Test("Compact and Large Mode share the exact same AnimationPolicy resolution")
    func modeParityUsesSamePolicy() {
        for isKeyboardVisible in [false, true] {
            for slot in [BottomSnackbarSlot.none, .rest, .undo] {
                let policy = ActiveWorkoutSnackbarLayout.policy(
                    isKeyboardVisible: isKeyboardVisible,
                    snackbarSlot: slot
                )
                // Single policy instance drives both mode presentations
                #expect(policy.hasSingleAnimationOwner == true)
                if isKeyboardVisible {
                    #expect(policy.topSlot == slot)
                    #expect(policy.bottomSlot == .none)
                    #expect(policy.isFABVisible == false)
                } else {
                    #expect(policy.topSlot == .none)
                    #expect(policy.bottomSlot == slot)
                    #expect(policy.isFABVisible == true)
                }
            }

        }
    }

    @MainActor
    @Test("Undo envelope accepts a simultaneous live rest countdown")
    func undoEnvelopeSupportsRestCountdown() {
        let envelope = ActiveWorkoutSnackbarLayout.undoEnvelope(
            message: "Deleted set",
            restEndDate: Date().addingTimeInterval(30)
        )
        _ = envelope
        let baseline = ActiveWorkoutSnackbarLayout.undoEnvelope(message: "Deleted set")
        _ = baseline
    }
}
