# Tasks: 动作选择分区语义重映射

**Input**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [mapping contract](./contracts/section-mapping.md)

**Vertical slice**: US1 delivers the complete user outcome: all 1,558 actions remain available through 12 meaningful, stable, nonempty picker sections.

## Phase 1: User Story 1 — 12 个稳定非空分区 (Priority: P1)

**Goal**: Apply the reviewed Equipment mapping at the canonical model seam and prove the assembled picker distribution without duplicating classification in AppUI.

**Independent Test**: Load catalog v5, group all actions, verify the exact 12-section order/counts, then search/filter and verify only nonempty stable sections remain.

- [ ] T001 [US1] Update the canonical Equipment→ExerciseSection mapping and visible order in `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift`, `Packages/VitalModels/Sources/VitalModels/Enums/ExerciseSection.swift`, and `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSectionTests.swift`
- [ ] T002 [US1] Lock the 12-section catalog distribution and filtered nonempty behavior in `VitalStrideTests/Sources/ExercisesJSONTests.swift` and `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift`

### Task metadata

| Task | Layer / context | Files in scope | Explicit exclusions | Interface / contract | Acceptance | Exact verification | Blocked by |
|---|---|---|---|---|---|---|---|
| T001 | VitalModels · `Packages/VitalModels/CONTEXT.md` | `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift`; `Packages/VitalModels/Sources/VitalModels/Enums/ExerciseSection.swift`; `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSectionTests.swift` | All AppUI files; catalog/importer/Seeder; resources/localizations; persisted models; TelemetryKit; project config | Existing public `Equipment.section` changes mapping; `ExerciseSection` cases/raw values and `Exercise.section` interface remain; `allCases` order places Other last | (1) all 29 Equipment values covered exactly once; (2) assisted→bodyweight; medicine/rope/sled/stability→other; weighted→weighted; (3) retained categories unchanged; (4) merged legacy cases no longer emitted; (5) public raw values and Exercise schema/initializer unchanged; (6) package tests pass | From repo root: `swift build --package-path Packages/VitalModels && swift test --package-path Packages/VitalModels` | None |
| T002 | AppUI · `VitalStride/CONTEXT.md` | `VitalStrideTests/Sources/ExercisesJSONTests.swift`; `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift` | All app production views/grouping implementation; VitalModels; catalog/importer/Seeder; UI redesign; TelemetryKit; project config | No new interface; verifies existing `ExercisePickerSectionGrouping.groupedSections` through the reviewed mapping contract | (1) exact final order/counts = 12 sections and 1,558 total; (2) Bodyweight=376, Weighted=36, Other=96; (3) every output section nonempty; (4) search/muscle filters preserve per-exercise identity; (5) custom assisted/Other/weighted mapping follows T001; (6) existing index-order regression remains green | From repo root: `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ExercisesJSONTests -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests` | T001 |

## Dependencies and execution order

`T001 → T002`. No tasks are parallel: T002's expected distribution depends on T001's model mapping. Each task is one formal layer and one independently reviewable commit.

## Acceptance traceability

| Spec acceptance | Vertical slice | Tasks | Verification surface |
|---|---|---|---|
| FR-001/SC-001 final 12-section order/counts | US1 | T001, T002 | AppUI catalog distribution test |
| FR-002/FR-003 complete 17-section decisions | US1 | T001 | VitalModels exhaustive mapping test |
| FR-004 Other receives 17 Equipment / 96 rows | US1 | T001, T002 | Package mapping + catalog count tests |
| FR-005 Bodyweight 376 / Weighted 36 | US1 | T001, T002 | Package mapping + catalog count tests |
| FR-006/SC-003 filtered nonempty stability | US1 | T002 | Grouping filter/search tests |
| FR-007/FR-008 no catalog/schema/raw-value removal | US1 | T001 | Package compatibility tests + diff scope |
| FR-009 telemetry uses final section identity | US1 | T001, T002 | Existing index/telemetry construction regression |
| FR-010 interaction/accessibility regressions | US1 | T002 | Existing AppUI targeted tests; no production view changes |

## Files not to touch across the slice

- `VitalStride/Resources/exercises.json`
- `scripts/import_mit_exercises.py`, provenance, reconciliation, licenses
- `VitalStride/Sources/ExerciseSeeder.swift`
- `VitalStride/Sources/ExercisePickerView.swift` and other app production views
- `Packages/TelemetryKit/**`
- `project.yml`, `VitalStride.xcodeproj/**`, Prototype, HealthKit, AIService, watchOS, widget

Implementation dispatch is blocked until AI Reviewer and Team Lead both approve the exact planning revision under ADR-0014.
