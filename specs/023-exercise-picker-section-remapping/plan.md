# Implementation Plan: 动作选择分区语义重映射

**Branch**: `023-exercise-picker-section-remapping` | **Date**: 2026-08-26 | **Spec**: [spec.md](./spec.md)

**Input**: MY-1475 产品决策 + catalog v5 真实枚举、映射、种子数据证据。

## Summary

保留 `Equipment` 作为原始 catalog taxonomy，继续以 VitalModels 的 `Equipment.section` 作为唯一分类 seam：把 `assisted` 改映射到 Bodyweight，把 Medicine Ball、Rope、Sled Machine、Stability Ball 改映射到 Other，保留 Weighted 与产品已确认的十个独立分区。AppUI 不新增二次分类逻辑，只更新 catalog-to-picker 集成合同并验证现有非空过滤行为，最终显示 12 个 section。

## Technical Context

**Language/Version**: Swift 6 strict concurrency

**Primary Dependencies**: VitalModels、SwiftUI、Swift Testing

**Storage**: 现有 SwiftData `Exercise.equipment`；无 schema 或数据迁移

**Testing**: Swift Package Manager package tests；Xcode app-target tests

**Target Platform**: iOS 18+ picker；共享模型由当前 app targets 消费

**Project Type**: XcodeGen mobile app + local SPM packages

**Constraints**: 不修改 catalog/importer/Seeder；不丢动作；过滤后只显示非空 section；Other 为显式映射

**Scale/Scope**: catalog v5 1,558 rows、29 Equipment values、12 visible sections

## Constitution Check

### Before research

- §III：分类规则已经位于 VitalModels；不得在 AppUI 新建重复映射。
- §II：只修改纯值映射与 tests，不引入并发绕过。
- §VI：本轮沿用现有 section 本地化名称，无新增硬编码 UI 文本。
- Quality Bar A/I：每个实现 task 单 layer；模型 public mapping 有 package tests，assembled catalog 行为有 AppUI tests。

**Gate result**: PASS。需要 VitalModels → AppUI 两个串行 layer task，不是 app-target-only。

### After design

- `ExerciseSection` cases/raw values 保持兼容；只改变 `Equipment.section` 的发射映射与 `allCases` 展示顺序，使 Other 位于最终可见顺序末尾。
- AppUI 继续调用既有纯 grouping module；无第二 adapter、无重复 seam。
- 无持久字段、catalog、Seeder、TelemetryKit 或 XcodeGen 改动。

**Gate result**: PASS。

## Research Findings

- `assisted=15`、`weighted=36` 全部来自固定上游 `sourceData.equipment`，各自与 catalog 顶层 Equipment 1:1，一致性 mismatch 为 0。
- 本地导入器只做 raw-value 规范化；产品 section 是后续 `Equipment.section` 的静态映射。
- Assisted 不是统一器械：8/15 名称为拉伸，代表样本使用徒手、毛巾、稳定球或普通单杠，适合合并 Bodyweight。
- Weighted 是跨器械的外加负重方式，36 条规模明显，且无法无损归入 Dumbbell、Barbell、Bodyweight 或 Other 的某个单一具体器械目标，因此保留独立 section。

完整证据见 [research.md](./research.md)。

## Domain and Interface Design

### Canonical terms

- Equipment：保留上游原始器械标签。
- Exercise Section：面向 picker 的稳定产品分组，由 Equipment 显式派生。
- Other Section：显式 fallback，不是运行时低频阈值。

这些术语同步记录于根 `CONTEXT.md`；完整映射见 [contracts/section-mapping.md](./contracts/section-mapping.md)。

### VitalModels seam

- 继续由现有 public `Equipment.section` 隐藏 29→section 的完整映射，所有 callers 与 tests 共用同一 seam。
- `Exercise.section` 继续只委托该映射；不进入 initializer 或持久化 schema。
- 既有 `ExerciseSection` public cases/raw values 保持可用，避免无必要的 Codable/source compatibility 删除；合并后的 legacy cases不再由任何 Equipment 产生。
- `ExerciseSection.allCases` 的声明顺序调整为最终可见顺序，Other 在最后；现有 grouping 的 non-empty compaction 会跳过不再产生的 legacy cases。

### AppUI integration

- `ExercisePickerSectionGrouping.groupedSections` 保持现有 interface 和 implementation：按 `exercise.section` 分桶、按 `ExerciseSection.allCases` 排序、通过 `compactMap` 移除空 section。
- 不修改 picker production view；AppUI task 只更新当前 catalog 的 assembled distribution contract，并用既有 grouping tests 锁定过滤后非空行为。

## Project Structure

### Documentation (this feature)

```text
specs/023-exercise-picker-section-remapping/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── section-mapping.md
└── tasks.md
```

### Source Code (implementation scope)

```text
Packages/VitalModels/
├── Sources/VitalModels/Enums/
│   ├── Equipment.swift
│   └── ExerciseSection.swift
└── Tests/VitalModelsTests/ExerciseSectionTests.swift

VitalStrideTests/Sources/
├── ExercisesJSONTests.swift
└── ExercisePickerSectionGroupingTests.swift
```

**Structure Decision**: Classification remains in dependency-free VitalModels. AppUI owns only assembled picker behavior and its tests. The fresh planning revision is published as a planning-files-only descendant of the exact reviewed T001 head; T002 uses that reviewed planning head as its exact checkout base so its implementation diff remains AppUI-test-only. Delivery uses the stacked contract below instead of waiting for T001 to merge to `main`.

## Layer Decomposition

| Tracker stage | Task | Layer | Deliverable | Depends on |
|---|---|---|---|---|
| 1 | T001 | VitalModels | Final explicit Equipment→ExerciseSection mapping, visible order, package contracts | None |
| 1 after revised planning PASS | T002 | AppUI | 12-section catalog distribution and filtered non-empty integration contracts | Semantic T001 snapshot `cb78fe8c70071c11f91bf400b00ef14b7812e771` plus exact reviewed planning descendant `P` as checkout base |

## Stacked Delivery Contract for T002

T002 has a semantic dependency on T001's mapping but no remaining scheduling dependency: the reviewed T001 head already exists. Let `H0` be `cb78fe8c70071c11f91bf400b00ef14b7812e771`, `P` be the fresh reviewed planning head, and `H1` be the later reviewed T002 implementation head. The following delivery topology preserves each task's one-layer diff while keeping PR #418 frozen until integration is authorized.

1. `P` is based on `H0`, changes only the revised `specs/023-exercise-picker-section-remapping/` planning artifacts, and receives fresh exact-revision planning PASS. The concrete SHA for `P` is then pinned in MY-1490's task body and delivery metadata.
2. After that PASS, tracker reconciliation moves MY-1490 from Stage 2 to Stage 1 so it can share the active barrier with MY-1489; it remains parked until Team Lead schedules it.
3. Team Lead prepares T002 from exact checkout base `P`, after verifying `H0` is an ancestor of `P` and both PR #418 `headRefOid` and remote branch `agent/team-lead/0032588c7a6c` still equal `H0`.
4. Fullstack Engineer changes only T002's two AppUI test files. Its implementation review diff is the exact range `P...H1`; inherited VitalModels and reviewed planning commits are base context, not T002 changes.
5. The T002 pull request targets `agent/team-lead/0032588c7a6c`, not `main`. Its total stacked PR surface `H0...H1` contains the independently reviewed planning artifacts plus the two T002 AppUI test files; targeting `main` would additionally expose unrelated unmerged history as T002 delivery scope.
6. AI Reviewer reviews the exact implementation range `P...H1`. `H1` is acceptable only when that range contains the two declared AppUI test files and no other path.
7. MY-1491 may implement in parallel, but it must merge to `main` before Team Lead integrates T002 and requests the fresh PR #418 required run. This ensures the fresh run uses the corrected RepoInfra gate.
8. After T002 review passes and the PR #418 source branch is still at `H0`, Team Lead advances `agent/team-lead/0032588c7a6c` by fast-forward only to `H1`. Squash, rebase, cherry-pick, merge commits, or any extra commit are forbidden because they produce an unreviewed combined head.
9. The fast-forward makes PR #418's new `headRefOid` byte-for-byte equal to `H1` and triggers a fresh required run. This is a new descendant delivery event, not a retry of run `33089199269`.

### Reviewed-descendant rule

A combined PR #418 head is valid only when all of the following are true:

- `cee0a1a8b3ef6fd13e6c1a84ffc553fe71e0c72f...H0` remains the previously reviewed T001 range.
- `H0...P` has the fresh planning PASS and contains only the declared planning artifacts.
- `P...H1` has a fresh implementation PASS and contains only the two T002 AppUI test files.
- PR #418 `headRefOid`, the remote source branch, and `H1` match byte-for-byte after fast-forward; `H0` and `P` remain ancestors of that exact head.
- The final PR #418 required checks, including `App target`, run against that exact combined head and current `main` base.

If PR #418's source branch moves before integration, or any integration step rewrites `P` or `H1`, stop. Recreate the descendant chain from the new authorized base, rerun verification, and obtain fresh exact-revision review; do not rebase or cherry-pick an already reviewed patch and call it equivalent.

## Error and Compatibility Strategy

- No persisted values are rewritten; existing Exercise rows automatically derive the new section from their unchanged Equipment.
- No `ExerciseSection` raw value is removed. Historical telemetry identifiers remain valid; future jumps emit the final target section raw value.
- Future catalog drift fails explicit distribution assertions; production never changes grouping based on count.
- Empty search/filter results continue through the existing graceful empty state.

## Verification Strategy

From repository root:

```bash
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisesJSONTests \
  -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests \
  -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests
```

完整 App target required check 由 delivery pipeline 在 MY-1491 合入 `main`、`H1` fast-forward 进入 PR #418 后执行。该 fresh run 是 MY-1489 的最终 unblock evidence。

## Files Not to Touch

- `VitalStride/Resources/exercises.json`
- `scripts/import_mit_exercises.py` 与 provenance/reconciliation 文件
- `VitalStride/Sources/ExerciseSeeder.swift`
- `VitalStride/Sources/ExercisePickerView.swift` 与其他 app production views
- `Packages/TelemetryKit/**`
- `project.yml` 与 `VitalStride.xcodeproj/**`
- HealthKit、AIService、watchOS、widget、Prototype targets

## Complexity Tracking

无宪法例外或需要辩护的复杂度。
