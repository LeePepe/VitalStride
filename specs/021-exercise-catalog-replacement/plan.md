# Implementation Plan: 动作目录全量替换

**Spec**: [spec.md](./spec.md)

**Detailed execution plan**: `docs/superpowers/plans/2026-08-17-exercise-catalog-replacement.md`

## Technical Path

固定上游快照经 Python 生成器离线转换为 catalog v5；完整上游记录存在 bundled JSON，SwiftData 只保留训练/筛选所需索引字段。Seeder 按稳定 preset ID 原位更新 upstream-backed preset，不删除重建。

## Layer Decomposition

| Task | Layer | Deliverable | Depends on |
|---|---|---|---|
| T001 | VitalModels | 29-case `Equipment`（28 个上游区别 + legacy machine）与双语资源/测试 | None |
| T002 | tooling / app resources | pinned generator、provenance、license/notice、catalog v5、reconciliation、CI contract | T001 |
| T003 | app target | v5 catalog validation、原位 canonical migration、rollback/completeness tests | T002 |
| T004 | delivery | 全量验证、PR、CI/review-bot supervision、merge/issue closure | T001-T003 |

每个实现 task 单独 commit；禁止跨 task 回头扩 scope。见 Constitution §III 与 AGENTS.md §按 layer 收窄范围。

## Verified Interfaces

- 保留 `Equipment: String, Codable, CaseIterable, Sendable` 以及六个 legacy raw values。
- 保留 `ExerciseSeeder.seedIfNeeded(context:userDefaults:bundle:)`。
- 保留 `ExerciseSeeder.findByPresetId(_:context:)`。
- 保留 `ExerciseSeeder.backfillDefaults(context:dtos:)` 供 v1-v4 fixtures；v5 不执行 legacy default/name/media backfill。
- 扩展 internal `seed(context:userDefaults:catalogData:)` 以支持可注入 throwing save boundary。
- `Exercise` 现有字段足够；不改模型 schema。

## Error Handling

- checksum、schema、语言、来源、重复 ID、歧义或碰撞失败均在写文件/写 SwiftData 前停止。
- 运行时只进行一次最终 save；任何异常 rollback，版本号保持原值。
- same-version database 不完整时按 ID 集恢复缺项。

## Verification

```bash
python3 -m unittest discover -s scripts/tests -p 'test_import_mit_exercises.py'
python3 scripts/validate_exercise_muscles.py
python3 scripts/i18n_check_lproj_parity.py
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

## Files Not to Touch

- `Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift`
- `project.yml`
- `VitalStride.xcodeproj/**`
- `Prototype/Sources/Prototype/**`

## Constitution References

Constitution §II, §III, §IV, §VI, §Development Workflow。
