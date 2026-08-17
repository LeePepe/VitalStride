# Tasks: 动作目录全量替换

**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)

Dependency order: T001 → T002 → T003 → T004.

## [T001] [VitalModels] 支持完整上游器械词表

**Files in scope**:

- `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift`
- `Packages/VitalModels/Sources/VitalModels/Resources/Localizable.xcstrings`
- `Packages/VitalModels/Tests/VitalModelsTests/EnumLocalizationTests.swift`
- `VitalStrideTests/Sources/EnumTests.swift`
- `VitalStrideTests/Sources/ExercisePickerIndexSyncTests.swift`

**Files NOT to touch**: `Exercise.swift`, app UI layout, `project.yml`, `.xcodeproj`。

**Public signatures**: 保持 `Equipment: String, Codable, CaseIterable, Sendable`；保持六个 legacy raw value；新增 case raw value 使用 canonical ASCII snake_case。

**Acceptance criteria**:

- [ ] `Equipment.allCases` 为 29，覆盖 28 个上游值且保留 legacy `.machine`。
- [ ] 六个旧 raw value 全部可解码；所有 case Codable round-trip。
- [ ] 所有 case 有非空英文/简中 label 与 SF Symbol。
- [ ] picker telemetry identifier 对全部 case 构造成功。

**Layer constraints**: `depends_on: []`；遵守 `Packages/VitalModels/CONTEXT.md` red_lines。

**Verification**:

`swift build --package-path Packages/VitalModels && swift test --package-path Packages/VitalModels`

## [T002] [Tooling/Data] 固定快照并生成完整 catalog v5

**Blocked by**: T001

**Files in scope**:

- `scripts/import_mit_exercises.py`
- `scripts/exercises_dataset_provenance.json`
- `scripts/tests/test_import_mit_exercises.py`
- `docs/data/exercise-catalog-reconciliation.json`
- `docs/licenses/hasaneyldrm-exercises-dataset-LICENSE`
- `docs/licenses/hasaneyldrm-exercises-dataset-NOTICE.md`
- `VitalStride/Resources/exercises.json`
- `VitalStrideTests/Sources/ExercisesJSONTests.swift`
- `.github/workflows/ci.yml`

**Files NOT to touch**: runtime Seeder、SwiftData models、media binaries、`project.yml`、`.xcodeproj`。

**Interfaces**: 保持 importer CLI 与 UUID namespace；catalog version=`5`；row 增 `source`，upstream row 增完整 `sourceData` mirror。

**Acceptance criteria**:

- [ ] 固定 commit/checksum 不匹配时失败且不写输出。
- [ ] 生成 1,558 rows；reconciliation 为 1,135/66/123/234，0 ambiguity/collision。
- [ ] 1,324 source IDs 唯一且全部存在；8 对同名 source rows 全保留。
- [ ] 十种语言及所有上游字段完整；Cable Pulldown 主次肌肉正确。
- [ ] 连续生成两次字节一致；无图片/GIF二进制。
- [ ] generator tests 与 muscle validator 纳入 required policy job。

**Verification**:

```bash
python3 -m unittest discover -s scripts/tests -p 'test_import_mit_exercises.py'
python3 scripts/validate_exercise_muscles.py
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisesJSONTests
```

## [T003] [App] v5 preset 原位迁移与失败恢复

**Blocked by**: T002

**Files in scope**:

- `VitalStride/Sources/ExerciseSeeder.swift`
- `VitalStrideTests/Sources/ExerciseSeederTests.swift`

**Files NOT to touch**: `Exercise.swift`、UI、catalog generator、`project.yml`、`.xcodeproj`。

**Public signatures**: 保留现有三个 caller-facing Seeder 接口；internal seed 增 throwing save injection boundary；v1-v4 DTO fixtures 继续兼容。

**Acceptance criteria**:

- [ ] v5 在 mutation 前拒绝重复/缺失/未知来源/语言不完整 catalog。
- [ ] upstream-backed canonical fields 原位更新；stable identity 与 workout/template relationships 不变。
- [ ] 中文名、weights、reps、`mediaKey` 精确保留，包括 nil。
- [ ] VitalStride-only/custom 不变；same-version 缺项可恢复；重复 seed 幂等。
- [ ] save 失败 rollback 且 `seedVersionKey` 不前进。

**Verification**:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExerciseSeederTests \
  -only-testing:VitalStrideTests/ExerciseSeederFindTests \
  -only-testing:VitalStrideTests/SubstituteRecommendationFilterTests
```

## [T004] [Delivery] 全量门禁、PR 与合并监督

**Blocked by**: T001, T002, T003

**Files in scope**: 仅修复前述 task 自己引入的失败；不扩大功能。

**Acceptance criteria**:

- [ ] Python 数据门、i18n、VitalModels build/test、完整 app `xcodebuild test` 全绿。
- [ ] diff 无 media binaries、无未声明文件、未触碰用户 Prototype 文件。
- [ ] PR required checks、`claude-review`、`codex-review` 全绿。
- [ ] PR merged 后 Multica issue 状态为 done。

**Verification**: 使用 AGENTS.md §Build & Test 与 §Git Workflow 的完整命令。
