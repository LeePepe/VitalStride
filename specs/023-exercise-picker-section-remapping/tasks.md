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
| T002 | AppUI · `VitalStride/CONTEXT.md` | `VitalStrideTests/Sources/ExercisesJSONTests.swift`; `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift` | All app production views/grouping implementation; VitalModels; catalog/importer/Seeder; UI redesign; TelemetryKit; project config | No new interface; verifies existing `ExercisePickerSectionGrouping.groupedSections` through the reviewed mapping contract | (1) exact final order/counts = 12 sections and 1,558 total; (2) Bodyweight=376, Weighted=36, Other=96; (3) every output section nonempty; (4) search/muscle filters preserve per-exercise identity; (5) custom assisted/Other/weighted mapping follows T001; (6) existing index-order regression remains green | From repo root: `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ExercisesJSONTests -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests` | Semantic T001 snapshot `H0=cb78fe8c70071c11f91bf400b00ef14b7812e771` (satisfied); exact reviewed planning head `P` is the checkout base; final integration waits for MY-1491 merge |

## Dependencies and execution order

The semantic graph remains `T001 → T002`, but T001's exact reviewed implementation head `H0` already satisfies the content dependency. The fresh planning head `P` descends from `H0` and becomes T002's exact checkout base after planning PASS. T002 may therefore be implemented in parallel with MY-1491. Final PR #418 integration waits for both the T002 exact-revision PASS and MY-1491's merge to `main`.

After this revised planning revision passes, reconcile MY-1490 from Stage 2 to Stage 1 while leaving it in `backlog` and unassigned. Stage 1 then represents the active parallel barrier: MY-1489 retains the frozen T001 delivery and MY-1490 carries the dependent AppUI test descendant; Team Lead alone promotes/schedules MY-1490.

### T002 checkout and pull-request contract

- Semantic T001 base: `H0=cb78fe8c70071c11f91bf400b00ef14b7812e771`.
- Exact checkout base: fresh reviewed planning head `P`, pinned in MY-1490 after planning PASS; `H0` must be its ancestor and `H0...P` must contain only the reviewed planning artifacts.
- Frozen target before integration: PR #418 branch `agent/team-lead/0032588c7a6c`, which must still equal `H0`.
- Pull-request target: `agent/team-lead/0032588c7a6c`, never `main`.
- Implementation review range: `P...H1`; the range must contain only `VitalStrideTests/Sources/ExercisesJSONTests.swift` and `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift`.
- Stacked PR range: `H0...H1`; it contains only the independently reviewed planning artifacts plus the two T002 test files.
- Integration: after fresh implementation PASS and MY-1491 merge, Team Lead fast-forwards the PR #418 branch from `H0` to `H1`. No squash, rebase, cherry-pick, merge commit, or extra commit.
- Post-integration proof: local head, remote PR #418 branch, PR #418 `headRefOid`, and `H1` are byte-identical; both `H0` and `P` are ancestors; a fresh required PR #418 run evaluates that exact combined head.

If the frozen target moves or the reviewed commit is rewritten, the review is stale. Reprepare from the new authorized base, rerun verification, and obtain a new exact-revision PASS before integration.

### T002 delivery acceptance

- Team Lead records a fresh T002 delivery workspace whose `delivery_base_sha` is exactly the reviewed planning head `P`; its branch is distinct from MY-1489's workspace/branch.
- The T002 pull request's base ref is `agent/team-lead/0032588c7a6c`, its head ref is the dedicated T002 branch, and the target branch remains frozen at `H0` throughout review.
- `git diff --name-only P...H1` returns exactly the two declared AppUI test paths; `git diff --name-only H0...P` returns only the freshly reviewed planning artifacts.
- The exact `H1` receives AI Reviewer PASS after focused AppUI verification succeeds.
- Only after MY-1491 merges to `main`, Team Lead fast-forwards the PR #418 source branch to `H1` and proves all head/ancestry values before accepting the fresh required run.

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

T002 dispatch is blocked until AI Reviewer and Team Lead both approve the exact revised planning revision under ADR-0014. Planner/Reviewer do not assign implementation; Team Lead prepares the exact-base workspace and schedules it.
