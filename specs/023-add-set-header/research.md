# Research — 023 Add Set Header

## Decision Summary

| Question | Decision | Repository evidence |
|---|---|---|
| Where does the defect live? | AppUI, in `ActiveExerciseSection`. | `VitalStride/CONTEXT.md` owns `VitalStride/**` and `VitalStrideTests/**`; `git show origin/main:VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` shows the action after `ForEach` in `Section` content. |
| Can the historical add-set spec be edited? | No. Create feature 023. | `specs/017-add-set-button-redesign/spec.md` freezes the action as the section’s last row; MY-1474 requires the opposite. |
| Which existing behavior is frozen? | The private add-set mutation: one appended main set, defaults from the last main set, next continuous order. | The verified `addSet()` implementation in `origin/main` reads the last non-sub-set and inserts one `ExerciseSet`. |
| Does this need a package or model change? | No. | The behavior and UI are already in the app target; `Packages/**` and set/sub-set models are explicitly excluded by MY-1474. |
| Does this need localization work? | No. | The existing action already uses localized add-set label and hint strings. Reuse avoids Quality Bar G scope expansion. |
| What test style can prove the original symptom? | A source-structure regression followed by in-memory mutation coverage. | `ExercisePickerNestedLazyRegressionTests.swift` establishes the repository precedent for guarding a SwiftUI structural invariant; existing AppUI tests use in-memory `ModelContainerConfiguration.makeTestContainer()`. |
| Which executable gates apply? | Preserve MY-1474’s exact iPhone 16 command as task-local acceptance and also run the formal AppUI iPhone 17 gate. | MY-1474 and baseline SC-001 declare iPhone 16; `VitalStride/CONTEXT.md`, the current constitution, and CI declare iPhone 17. Both are explicit to avoid silently choosing one side of the repository drift. |
| What evidence covers visual/accessibility risk? | Simulator light/dark, accessibility Dynamic Type, VoiceOver, and 44-point hit-target evidence. | Constitution Quality Bars H and K and the issue acceptance criteria. |

## Verified Symbols and Paths

- `ActiveExerciseSection` exists in `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`.
- Its `Section` content currently renders `ForEach(...)` followed by the private `addSetButton`.
- Its header currently contains the exercise title, `Spacer`, and existing `Menu`.
- Private `addSet()` exists and owns the current append semantics.
- The private action currently carries full-width and `listRow*` modifiers that are specific to its historical content-row placement.
- The file already has four normal/large × light/dark previews whose comments describe the old row relationship; the matrix remains useful but its descriptions must follow the moved header placement.
- `ActiveWorkoutHitTarget.side` is covered by `VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift` as the 44-point AppUI token.
- `VitalStrideTests` is included as a directory source by `project.yml`; adding one test file requires no project-file edit.
- `VitalStride/CONTEXT.md` declares the full AppUI gate on iPhone 17 Simulator, while MY-1474 declares iPhone 16; the task graph keeps both.

## Alternatives Rejected

- **Keep the action as a content row and suppress move behavior**: still consumes a full row and does not satisfy the desired header placement.
- **Move the action to `ActiveWorkoutView`**: crosses the issue’s explicit boundary and couples an exercise-local action to the exercise-reorder owner.
- **Create a DesignKit component**: unnecessary cross-layer scope for a single private header action.
- **Validate only with screenshots**: cannot freeze append semantics or reliably prove the action left `Section` content.
- **Require a physical device**: violates Quality Bar K for a simulator-observable UI/layout change.

## Open Questions

None. Product placement, preserved behavior, file authority, verification command, and evidence surfaces are all pinned by MY-1474 and repository contracts.
