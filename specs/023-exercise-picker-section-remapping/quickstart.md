# Quickstart: implementation and verification

All commands run from the repository root.

## Stage 1 — VitalModels

Implement only T001's declared files, then run:

```bash
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels
```

Do not run `xcodebuild` for this package-only stage.

## Stage 2 — AppUI integration contracts

T001 is available as reviewed PR #418 head `H0=cb78fe8c70071c11f91bf400b00ef14b7812e771`. The fresh reviewed planning revision `P` must descend from `H0` and change only the declared planning artifacts. After planning PASS, Team Lead pins `P` in MY-1490 and prepares T002 from that exact SHA. PR #418 `headRefOid` plus remote branch `agent/team-lead/0032588c7a6c` must remain at `H0`. Do not base T002 on `main` and do not reuse MY-1489's delivery workspace.

After the revised planning PASS, MY-1490 belongs in tracker Stage 1 alongside MY-1489 but remains parked for Team Lead scheduling; the stage change removes the obsolete serial barrier without changing the semantic T001 snapshot dependency.

Implement only T002's declared test files, then run:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisesJSONTests \
  -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests \
  -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests
```

Expected assembled distribution: 12 nonempty sections, Bodyweight 376, Weighted 36, Other 96, total 1,558.

Open the T002 pull request against `agent/team-lead/0032588c7a6c`, not `main`. Its stacked PR range `H0...H1` contains the independently reviewed planning artifacts plus the two AppUI test files, while the implementation review range `P...H1` contains only those test files. Obtain an exact-revision AI Reviewer PASS for `P...H1`.

MY-1491 may run in parallel. After MY-1491 merges to `main`, and only while the PR #418 source branch still equals `H0`, Team Lead fast-forwards that branch to `H1`. Do not squash, rebase, cherry-pick, create a merge commit, or add another commit. After integration, the remote source branch and PR #418 `headRefOid` must equal `H1`, with both `H0` and `P` as ancestors, before a fresh required run is accepted.

If any SHA differs, stop and reprepare/review rather than transforming the reviewed patch.

## Scope guard

The implementation must not modify catalog resources, importer/provenance, Seeder, picker production views, TelemetryKit, XcodeGen configuration, or generated project files.

The T002 implementation diff boundary is measured from `P`; inherited VitalModels and planning files are base context and must not be edited by T002.
