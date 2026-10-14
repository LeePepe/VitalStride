# Research: Active Workout Exercise Section Reorder Fix

## Decision 1 — Create a new feature package

**Decision**: Use `specs/023-active-workout-section-reorder-fix/` for MY-1473.

**Rationale**: `specs/017-active-workout-reorder-affordance/` records the completed MY-1344/MY-1353 delivery that added the existing edit entry. Its premise that only `EditButton` was missing is now historical and must not be rewritten.

**Alternative rejected**: Revising `017` in place would erase the distinction between the shipped affordance and the current functional defect.

## Decision 2 — Keep one AppUI vertical task

**Decision**: One AppUI task owns `ActiveWorkoutView.swift`, a DEBUG-only harness in `VitalStrideApp.swift`, `ExerciseManagementTests.swift`, and `ActiveWorkoutSectionReorderUITests.swift`.

**Rationale**: All four paths belong to AppUI. The harness and XCUITest form the true interaction RED; the source repair and unit invariant complete the same mergeable vertical slice. A test-only child would intentionally be non-mergeable.

**Alternative rejected**: A `Packages/**` helper would violate the issue boundary and move app-specific interaction behavior into a domain package.

## Decision 3 — Treat outer sections as explicit drag identities

**Decision**: The outer view must provide edit-mode drag/drop for `WorkoutExercise` identities rather than rely on native row `.onMove` to infer whole-section movement.

**Rationale**: The verified source has `ForEach(exercises)` producing `ActiveExerciseSection`, whose rendered root is a SwiftUI `Section`. The current `.onMove` and contiguous renumber method exist, yet whole-section controls remain unavailable. Native list movement is row-oriented, so the outer section identity needs an explicit interaction seam.

**Alternative rejected**: Changing `ActiveExerciseSection.swift` would expand the file allowlist into the component that owns the explicitly excluded set/sub-set UI.

## Decision 4 — Separate interaction RED from ordering invariant

**Decision**: Use the XCUITest for the actual pre-fix interaction RED. Separately extract or expose one app-internal reorder/renumber operation in `ActiveWorkoutView.swift` and invoke it from UI completion and the app unit invariant.

**Rationale**: The existing `ExerciseManagementTests.reorderExercises` copies already-correct movement and renumbering steps, so it passes while the production SwiftUI interaction is broken. It must become an invariant test, not be mislabeled as the behavioral RED.

**Alternative rejected**: Another test-local simulation would repeat the current false-positive pattern.

## Decision 5 — Prove persistence through a fresh context

**Decision**: After applying the production move, save and refetch through a new `ModelContext`.

**Rationale**: Sorting the same in-memory reference objects proves neither persistence nor re-entry behavior.

**Alternative rejected**: Asserting only the mutated in-memory array does not cover MY-1473's reopen criterion.

## Decision 6 — Preserve i18n scope through system accessibility semantics

**Decision**: Use the exercise's existing localized display text and system drag/move or adjustable semantics for VoiceOver.

**Rationale**: This meets the accessibility outcome without hard-coded copy or a new localization-key/resource-file dependency.

**Alternative rejected**: A custom literal label would violate Quality Bar G or require an unauthorized `Localizable.xcstrings` scope expansion.

## Decision 7 — Reconcile simulator commands by purpose

**Decision**: MY-1473's iPhone 16 command is the task-local automated and interactive acceptance surface; the repository's iPhone 17 AppUI job remains the required CI shipping gate.

**Rationale**: The issue explicitly names iPhone 16, while current `VitalStride/CONTEXT.md` declares iPhone 17 for the layer gate. Both contracts can be satisfied without treating either as stale.

## Decision 8 — Owner-approved Option A test surface

**Decision**: Apply owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa`: add one narrow XCUITest and a launch-argument-gated DEBUG fixture/entry in `VitalStrideApp.swift` that hosts the real `ActiveWorkoutView` with three deterministic exercises.

**Rationale**: This directly resolves AI Reviewer P1 `d15d5476-95de-480c-8358-5c96bbb36848`. The harness can be introduced before the production repair so the focused XCUITest fails on the whole-section interaction itself.

**Alternative rejected by owner decision**: Treating a missing seam or compile failure plus manual evidence as RED provides weaker automated coverage of the reported defect.

## Decision 9 — Reuse existing UI-test project configuration

**Decision**: Add only `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`; do not change `project.yml`.

**Rationale**: `VitalStrideUITests` already uses a directory-backed source path and is included in both the main and dedicated UI-test schemes. A new source file is discovered without XcodeGen configuration changes.

## Decision 10 — External serialization gates

**Decision**: Retire MY-1486 as a gate, treat completed successor MY-1706 as current compatibility baseline, and retain MY-1484 as the Team Lead pre-dispatch shared-lane gate rather than a product or cross-layer dependency. For this verified VitalStride issue, Team Lead supplies readiness while the sole Fullstack implementer owns first delivery-workspace classification and eligible initialization/registration.

**Rationale**: MY-1486 is cancelled and MY-1706 is complete at the verified current base. MY-1706 changed the same source file but not the reorder symbols; its policy-driven snackbar/FAB/animation behavior is now compatibility surface, not an unresolved branch. MY-1484 does not overlap this four-file allowlist but remains `in_review` and shares AppUI/Xcode simulator build state. Team Lead must make that lane quiescent and hand Fullstack the verified repository, approved exact reviewed ref, scope, acceptance, and dependency state. Fullstack must reuse and validate any existing delivery state, return partial or conflicting state for Team Lead recovery, and initialize/register a task-local workspace plus build artifacts only when the state is genuinely new.

## Decision 11 — Reconcile against current main without changing the solution

**Decision**: Publish the seven-artifact package from `main@7fc46752b36d1b2469209b96c50801419315987c`, retain Option A and the four implementation paths, and add an explicit within-file compatibility boundary for MY-1706.

**Rationale**: A diff from prior reference `f589a917f6f94c98588606fe9b273b5d4767faa4` shows only `ActiveWorkoutView.swift` changed among the allowlisted paths. Those changes are confined to policy-driven header/bottom safe-area and root animation composition; `EditButton`, `exerciseList`, `.onMove`, and `moveExercises(from:to:)` remain unchanged. The defect, behavioral RED, production-seam invariant, persistence proof, and accessibility acceptance have not drifted.

**Alternative rejected**: Replanning the interaction or reopening the Owner's A/B decision would ignore unchanged defect evidence and an already approved scope. Treating all of `ActiveWorkoutView.swift` as freely mutable would risk regressing MY-1706.
