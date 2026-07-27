# Tasks — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Spec**: `specs/017-workout-keyboard-redesign/spec.md`
**Plan**: `specs/017-workout-keyboard-redesign/plan.md`
**Version**: v2 (2026-07-27) — retrofit for PR #362 post-merge reality
**Execution dir**: Multica daemon workdir 根

---

## T017-01 — 现状截图诊断 + 归档 spec/plan/tasks

**Stage**: 1 · **Status**: **DONE** in commit `d8d526e` (PR #355)
**Sub-issue**: MY-1349
**Layer**: design assets + design docs

已交付：`design/keyboard-current-shots/*.png` ≥6、`diagnosis.md`、`specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md` v1（v1 内容将被 T017-02b 用 v2 替换）。

---

## T017-02a — north-star §11 + Prototype + PrototypeShotExporter + shots

**Stage**: 2 · **Status**: **DONE** in commit `25d95cd` (PR #362 merged 2026-07-27T15:56:04Z)
**Sub-issue**: MY-1350（in_review，待关闭）
**Layer**: design docs + Prototype SPM package + design assets

### Files delivered (all merged to main)

- `design/north-star.md` (+86, appended §11 只追加，其余段一字不动)
- `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` (+274, library target)
- **`Prototype/Package.swift` (+43)** — 追加 `PrototypeShotExporter` executable target；library `Prototype` target 依赖冻结在 `[DesignKit]`（**v2 追认为 in-scope**）
- **`Prototype/Sources/PrototypeShotExporter/main.swift` (+85, new)** — macOS-only CLI (`import AppKit`)；`swift run PrototypeShotExporter <output-dir>` 导出 4 PNG（**v2 追认为 in-scope**）
- **`.gitignore` (+7 -2)** — 追加 `Prototype/.build/`、`Prototype/.swiftpm/` 忽略（**v2 追认为 in-scope**）
- `design/prototype-shots/keyboard-{iphone,ipad}-{light,dark}.png` ×4

### v2 keep/revert 决策（每一改动逐项）

| File | 决策 | 理由 |
|---|---|---|
| `Prototype/Package.swift` | **KEEP** | 加法性改动；无 executable target 则 v1 verification 物理不可行；library target 依赖冻结 |
| `Prototype/Sources/PrototypeShotExporter/main.swift` | **KEEP** | 设计工具；封装 SwiftUI→PNG 机制；不进 app target |
| `.gitignore` (+7 -2) | **KEEP** | 只忽略 SPM 产物；生产零影响 |

---

## T017-02b — Stage 2 post-merge doc alignment (recovery, v2 新增)

**Stage**: 2 · **Status**: **TODO**（Fullstack 起手）
**Sub-issue**: MY-1354
**Layer**: design docs

### Files in scope

- `specs/017-workout-keyboard-redesign/spec.md` — 用 v2 版本**完整替换**
- `specs/017-workout-keyboard-redesign/plan.md` — 用 v2 版本**完整替换**
- `specs/017-workout-keyboard-redesign/tasks.md` — 用 v2 版本**完整替换**

### Files NOT to touch

- `Prototype/**` — Stage 2a 已定型，不动
- `.gitignore` — 已定型
- `design/north-star.md` — Stage 2a 已定型
- `design/prototype-shots/**` — Stage 2a 已定型
- `design/keyboard-current-shots/**` — Stage 1 已定型
- `design/keyboard-redesign-audit.md` — 历史 audit
- `VitalStride/Sources/WorkoutNumericKeyboard.swift` / `NumericKeypad.swift` — Stage 4
- `VitalStride/Sources/ActiveWorkout/**`
- `Packages/**`（含 DesignKit token）
- `project.yml` / `.xcodeproj`
- `design/keyboard-review.md` — Stage 3

### Public signatures / API

none — internal-only change (纯 spec/plan/tasks 文档更新)

### Functional acceptance criteria

- `specs/017-workout-keyboard-redesign/spec.md` 首部含 `**Version**: v2`
- `specs/017-workout-keyboard-redesign/plan.md` 首部含 `**Version**: v2`
- `specs/017-workout-keyboard-redesign/tasks.md` 首部含 `**Version**: v2`
- spec 显式声明 `PrototypeShotExporter` 是 v2 authorize 的 in-scope 文件（`grep -qE 'PrototypeShotExporter' spec.md`）
- spec 显式声明 `.gitignore` v2 处置（`grep -qE '\.gitignore' spec.md`）
- `PrototypeShotExporter` 未进 app target 依赖图（`grep` 反证）
- `PrototypeShotExporter/main.swift` 不 import 生产模块（`VitalStride`/`VitalModels`/`SwiftData`/`HealthKitService`/`AIService`/`VitalUI`）
- Prototype library target dependencies 恰为 `[DesignKit]`（`swift package dump-package | jq -e`）
- `swift build --package-path Prototype` 仍绿
- `swift run --package-path Prototype PrototypeShotExporter design/prototype-shots` 可复现 4 PNG（覆盖式；PNG 内容差异不影响本 stage 通过——只要能 run）

### Verification command

在 workdir 根：

```
# S1: v2 版本号
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/spec.md
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/plan.md
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/tasks.md

# S2: v2 显式声明已合入 out-of-scope 文件的处置
grep -qE 'PrototypeShotExporter' specs/017-workout-keyboard-redesign/spec.md
grep -qE '\.gitignore' specs/017-workout-keyboard-redesign/spec.md

# S3: PrototypeShotExporter 未进 app target 依赖图
! grep -rn 'PrototypeShotExporter' VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' project.yml 2>/dev/null

# S4: PrototypeShotExporter 不 import 生产模块
! grep -E '^import (VitalStride|VitalModels|SwiftData|HealthKitService|AIService|VitalUI)' \
     Prototype/Sources/PrototypeShotExporter/main.swift

# S5: Prototype library target dependencies 未污染
swift package dump-package --package-path Prototype \
  | jq -e '.targets[] | select(.name == "Prototype") | (.dependencies | length == 1) and (.dependencies[0].product[0] == "DesignKit")'

# S6: Prototype 仍可 build + PNG 导出可复现
swift build --package-path Prototype
swift run --package-path Prototype PrototypeShotExporter design/prototype-shots

echo OK
```

### 依赖

前置：T017-02a merged（`25d95cd`）。本 stage 不动任何 code，Fullstack 起手直接改文档。

### Branch

新 feature branch `docs/my1342-s2-alignment` (or 继承 parent branch)；PR 描述引用 T017-02a PR #362 + AI Reviewer FAIL findings 的 close-the-loop 关系。

### Test 策略

无代码变更；verification 六条 probe 全为文档 + `swift build`/`swift run` 复现。

---

## T017-03 — 客观 design review 报告

**Stage**: 3 · **Status**: **BACKLOG**（保持 gated；T017-02b 完成后 TL 提升）
**Sub-issue**: MY-1351

内容不变：`design/keyboard-review.md` 五段固定结构（vs north-star / vs audit / a11y / 高度实测 / 结论）；结论 = PASS 才允许交回请求提升 T017-04。

**门禁强化**：T017-02b **未 done** 前，MY-1351 严禁提升 backlog→todo（避免 review 报告引用 v1 结构再次错位）。

---

## T017-04 — 生产键盘迁移（TL 双门禁）

**Stage**: 4 · **Status**: **BACKLOG**（保持 gated；T017-03 结论 PASS + TL 显式回执才提升）
**Sub-issue**: MY-1352

内容不变（v1 版本沿用）。verification：`xcodebuild build` + 三个现有测试全 pass + grep 门禁清零（硬编码颜色/系统色/hex/并发规避）+ `git diff github/main...HEAD` 反证契约冻结（`enum LeftKeyAction`、全 case、`resolveTheme`、`preferredHeight`、`enableInputClicksWhenVisible`）+ `.isKeyboardKey` trait 数不减少。

---

## 汇总门禁

- Stage 1 → 2a：已达 (2026-07-27T13:xx merged)
- Stage 2a → 2b：已达 (2026-07-27T15:56 merged)
- **Stage 2b → 3：v2 spec/plan/tasks 落 main + T017-02b probe 全绿 + TL 验收**
- Stage 3 → 4：review 结论 PASS + TL 显式回执
- Stage 4 → done：build + 3 test + grep 门禁 + 真机双色截图 PR
