# Tasks — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Spec**: `specs/017-workout-keyboard-redesign/spec.md`
**Plan**: `specs/017-workout-keyboard-redesign/plan.md`
**Version**: v1 (2026-07-27)
**Execution dir**: Multica daemon workdir 根（**禁 cd 用户主 checkout**）

---

## T017-01 — 现状截图诊断 + 归档 spec/plan/tasks

**Stage**: 1（`--status todo` 立即开工）
**Layer**: design assets + design docs
**Depends on**: —

### Files in scope

- `design/keyboard-current-shots/*.png` (≥6 张，新增)
- `design/keyboard-current-shots/diagnosis.md` (新增)
- `specs/017-workout-keyboard-redesign/spec.md` (新增，内容 = 本 v1 附件)
- `specs/017-workout-keyboard-redesign/plan.md` (新增，内容 = 本 v1 附件)
- `specs/017-workout-keyboard-redesign/tasks.md` (新增，内容 = 本 v1 附件)

### Files NOT to touch

- `VitalStride/Sources/WorkoutNumericKeyboard.swift`（生产键盘，Stage 4）
- `VitalStride/Sources/NumericKeypad.swift`（生产键盘，Stage 4）
- `design/north-star.md`（Stage 2 追加 §11）
- `design/keyboard-redesign-audit.md`（历史 audit，不动）
- `Prototype/**`（Stage 2）
- `design/prototype-shots/keyboard-*.png`（Stage 2）
- `design/keyboard-review.md`（Stage 3）

### Public signatures / API

none — 纯 design assets + docs 产出，无代码 API 面变化

### Functional acceptance criteria

- 在 iOS Simulator（iPhone 16 + iPad Pro 11" 各一）以浅/深两种 appearance 打开当前生产键盘，覆盖 (working set + weight field) 和 (warmup + reps field) 两种上下文，共 ≥6 张截图落到 `design/keyboard-current-shots/`
- `diagnosis.md` 逐图列出视觉问题，至少 3 项**新增**观察（不重复 `design/keyboard-redesign-audit.md` 已覆盖的 P0/P1）；引用 audit 编号（如 "P1-a"、"P2-b"）建立对应
- `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md` 三文件按 handoff comment 附件内容落地
- 提交时 commit message 引用 MY-1342

### Verification command

在 workdir 根：
```
[ "$(ls design/keyboard-current-shots/*.png 2>/dev/null | wc -l | tr -d ' ')" -ge "6" ] \
  && [ -s design/keyboard-current-shots/diagnosis.md ] \
  && grep -qE 'P[0-3]' design/keyboard-current-shots/diagnosis.md \
  && [ -f specs/017-workout-keyboard-redesign/spec.md ] \
  && [ -f specs/017-workout-keyboard-redesign/plan.md ] \
  && [ -f specs/017-workout-keyboard-redesign/tasks.md ] \
  && echo OK
```

---

## T017-02 — north-star §11 + Prototype + prototype 截图

**Stage**: 2（初始 `--status backlog`；T017-01 完成后 TL 提升）
**Layer**: design docs + Prototype SPM package + design assets
**Depends on**: T017-01

### Files in scope

- `design/north-star.md`（**追加** §11 「Workout Numeric Keyboard」子章节；其他段不动）
- `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`（新增）
- `design/prototype-shots/keyboard-iphone-light.png`
- `design/prototype-shots/keyboard-iphone-dark.png`
- `design/prototype-shots/keyboard-ipad-light.png`
- `design/prototype-shots/keyboard-ipad-dark.png`
- （可选）`design/prototype-shots/keyboard-iphone-warmup-dark.png` 等 disabled 态截图

### Files NOT to touch

- `VitalStride/Sources/WorkoutNumericKeyboard.swift`（Stage 4）
- `VitalStride/Sources/NumericKeypad.swift`（Stage 4）
- `VitalStride/Sources/ActiveWorkout/**`（生产 wiring 不动）
- `design/keyboard-redesign-audit.md`（历史 audit）
- `design/keyboard-current-shots/**`（Stage 1 产出）
- `Prototype/Package.swift`（现有 `swift build --package-path Prototype` 已够用，不加依赖）
- `design/keyboard-review.md`（Stage 3）
- `Packages/DesignKit/**`（token 只读，禁改）

### Public signatures / API

`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`：

- 新增 `struct WorkoutKeyboardPrototype: View`——纯 view，构造参数与生产 `WorkoutNumericKeyboardContentView` 对齐但**用 mock 枚举**（在同文件顶部 `private enum PrototypeSetField / PrototypeLeftKeyAction / PrototypePresetBucket`）
- 至少 4 个 `#Preview("iPhone Light" / "iPhone Dark" / "iPad Light" / "iPad Dark")`；每个 preview 设 `.frame(width: 393/1024, height: 240/260)` 和 `.environment(\.colorScheme, .light/.dark)`
- **不 export、不桥 UIKit、不 import 生产模块**

### Files NOT to introduce as dependencies

Prototype 不允许新增以下 import：`VitalStride`、`VitalModels`、`SwiftData`、`HealthKitService`、`AIService`、`VitalUI`、`UIKit`（保持 SwiftUI-only + DesignKit）

### Functional acceptance criteria

- `design/north-star.md` §11 覆盖 spec §4 全部可检查条目：圆角（三档 pt 值）、间距（scale + pt）、三档配色（token 路径）、字号（TypeScale 或 font）、每键 foregroundStyle token、深/浅色参考截图路径
- north-star §11 明确写出「数字键必须 `.foregroundStyle(theme.neutrals.text1)`」（红线，禁 audit P0 复发）
- `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` 至少 4 个 `#Preview`，视觉上覆盖三档层级（Done 实心 / preset subtle / 功能键 inner / 数字键 card）
- `swift build --package-path Prototype` 通过（Prototype 自包含）
- `design/prototype-shots/keyboard-*.png` ≥4 张，文件名遵循 `keyboard-{iphone|ipad}-{light|dark}[.-suffix].png`

### Verification command

在 workdir 根：
```
swift build --package-path Prototype \
  && [ "$(ls design/prototype-shots/keyboard-*.png 2>/dev/null | wc -l | tr -d ' ')" -ge "4" ] \
  && grep -qE '^## 11\. Workout Numeric Keyboard|^## 11\. 训练页.*键盘' design/north-star.md \
  && grep -qE 'Radius|圆角' design/north-star.md \
  && grep -qE 'primary|primarySubtle|inner' design/north-star.md \
  && grep -qE 'foregroundStyle|text1' design/north-star.md \
  && [ "$(grep -c '#Preview' Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift)" -ge "4" ] \
  && ! grep -E '^import (VitalStride|VitalModels|SwiftData|HealthKitService|AIService|VitalUI)' Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift \
  && echo OK
```

---

## T017-03 — 客观 design review 报告

**Stage**: 3（初始 `--status backlog`；T017-02 完成后 TL 提升）
**Layer**: design docs
**Depends on**: T017-02

### Files in scope

- `design/keyboard-review.md`（新增）

### Files NOT to touch

- 生产键盘代码（Stage 4）
- Prototype 代码（Stage 2 已定型；如 review 发现问题，回 Stage 2 补丁，不在本 stage 改）
- north-star / audit / current-shots / prototype-shots（本 stage 只对照，不修改）

### Public signatures / API

none — 纯 review 报告

### Functional acceptance criteria

- `design/keyboard-review.md` 结构固定五段（spec §7 C-2）：
  - `## vs north-star §11`——逐条打钩，每条对照具体 prototype 截图
  - `## vs audit（2026-07-14）`——audit 每一条 P0/P1/P2/P3 回归验证，标注 fixed/pending/n-a
  - `## a11y`——44pt hit target（每键实测 pt）/ VoiceOver 逐键 label / Dynamic Type xxxLarge 截断检查 / Reduce Motion 影响
  - `## 高度实测`——iPhone/iPad 实际 preview 高度数字，vs ≤260/≤280 上限
  - `## 结论`——`PASS` 或 `FAIL`；FAIL 需列具体不达标项和回到 Stage 2 的补丁范围
- 结论 = PASS 才允许交回 TL 请求提升 T017-04；FAIL 需在同 comment 提出 Stage 2 补丁范围，TL 回退到 T017-02 补丁 loop

### Verification command

在 workdir 根：
```
[ -s design/keyboard-review.md ] \
  && grep -qE '^## vs north-star' design/keyboard-review.md \
  && grep -qE '^## vs audit' design/keyboard-review.md \
  && grep -qE '^## a11y' design/keyboard-review.md \
  && grep -qE '^## 高度实测' design/keyboard-review.md \
  && grep -qE '^## 结论' design/keyboard-review.md \
  && echo OK
```

---

## T017-04 — 生产键盘迁移（**被 TL 门禁**）

**Stage**: 4（初始 `--status backlog`；T017-03 结论 PASS **且** TL 显式回执确认后才提升）
**Layer**: app target
**Depends on**: T017-03（含 review 结论 PASS）

### Files in scope

- `VitalStride/Sources/WorkoutNumericKeyboard.swift`
- `VitalStride/Sources/NumericKeypad.swift`

### Files NOT to touch

- `VitalStride/Sources/ActiveWorkout/SetRow.swift`（生产 wiring 不动——契约冻结）
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutView.swift`
- `VitalStride/Sources/SelectAllTextField.swift`（inputView 挂点不动）
- `VitalModels/**`（`SetField` / `SetType` / `LeftKeyAction` / `PresetRepBucket` / `Exercise` / `ExerciseDefaults` 冻结）
- `Packages/DesignKit/**`（token 只读，禁改）
- `VitalStrideTests/Sources/WorkoutCopyToNextTests.swift`（覆盖 Copy 行为，禁改）
- `VitalStrideTests/Sources/WorkoutNumericKeyboardThemeTests.swift`（如需补充测试，追加新文件）
- `VitalStrideTests/Sources/NumericKeypadTests.swift`
- `project.yml` / `.xcodeproj`（本 stage 无 xcodegen 变更）
- `Prototype/**` / `design/**`（前 3 stage 产出，本 stage 只消费）

### Public signatures / API

**全部冻结（红线）**：

- `WorkoutNumericKeyboardContentView` 构造签名（`field: SetField, setType: SetType, exercise: Exercise?, recentWeightKg: Double?, theme: Theme, onKeyPress: ..., onLeftAction: ..., onPresetReps: ..., onDone: ...`）
- `WorkoutNumericKeyboard` UIView 构造签名与 `update(field:setType:exercise:recentWeightKg:)` 方法
- `WorkoutNumericKeyboard.resolveTheme(isDark:) -> Theme` static
- `WorkoutNumericKeyboard.preferredHeight() -> CGFloat` static
- `WorkoutNumericKeyboard.enableInputClicksWhenVisible: Bool` (protocol 要求)
- `enum LeftKeyAction` 全 case
- `enum SetField` 全 case + `isDecimalEnabled` / `isWeightField`
- `NumericKeypad` public 面（不改 mode/onKeyPress/`NumericKeypadKey`/`NumericKeypadMode`）
- 内部实现（`leftColumn` / `centerColumn` / `rightColumn` / `functionKey` / `presetKey` / `doneKey` / `keypadMode`）可**改视觉细节**（padding/spacing/radius/foregroundStyle/background token），**不改行为**

### Functional acceptance criteria

- 视觉层严格按 `design/north-star.md` §11 落地——三档层级配色/圆角/间距/字号/foregroundStyle 全对齐 Stage 2 定型的 prototype
- 所有硬编码颜色 / 系统色 / hex 清零（spec §7 D-4 grep 空）
- 交互契约零回归：所有回调签名、`LeftKeyAction` 枚举、disabled 逻辑（`setType != .working` 时金字塔/递减 disabled）、preset cycling（`lastRepsByBucket`）、a11y label / `.isKeyboardKey` trait 保留
- 高度约束不变：`preferredHeight()` 仍返回 iPad 260 / iPhone 240（或按 spec 允许 iPad ≤280 / iPhone ≤260 上限内的微调，但值必须硬编码常量非魔法数）
- ≥44pt hit target 覆盖所有键（`.frame(..., minHeight: 44)` 或更大）
- 深/浅色都需人工过一次真机（iPhone `deploy-to-phone.sh 陪陪`）——不做自动化门禁，但 PR 描述需附深/浅色截图对比 before/after
- 三个现有测试全 pass（spec §7 D-2）
- 无 Swift 6 并发规避（spec §7 D-5）
- commit message 引用 MY-1342；PR 描述引用 spec/review 路径

### Verification command

在 workdir 根，按顺序：
```
# build
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

# 三个现有测试
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/WorkoutNumericKeyboardThemeTests \
  -only-testing:VitalStrideTests/NumericKeypadTests \
  -only-testing:VitalStrideTests/WorkoutCopyToNextTests

# grep 门禁（全部为空）
! grep -rnE 'Color\.(red|blue|green|orange|yellow|purple|pink|white|black|gray)|Color\(hex|#[0-9A-Fa-f]{6}|systemGroupedBackground|secondarySystemBackground|tertiarySystemBackground|accentColor' \
     VitalStride/Sources/WorkoutNumericKeyboard.swift VitalStride/Sources/NumericKeypad.swift

! grep -rnE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources/WorkoutNumericKeyboard.swift VitalStride/Sources/NumericKeypad.swift

# 契约冻结：拉 github/main 比 diff
git fetch github main
! git diff github/main...HEAD -- VitalStride/Sources/WorkoutNumericKeyboard.swift \
    | grep -E '^-.*(enum LeftKeyAction|case (addPyramid|addDropSet|toggleUnilateral|copyToNext)|static func resolveTheme|static func preferredHeight|enableInputClicksWhenVisible)'
```

---

## 汇总门禁

- Stage 1 → 2：spec/plan/tasks 归位 + ≥6 张现状截图 + diagnosis.md
- Stage 2 → 3：north-star §11 覆盖必检项 + Prototype 独立 build + ≥4 张 prototype 截图
- Stage 3 → 4：**review 结论 PASS + TL 显式回执**
- Stage 4 → done：build + 3 test + grep 门禁 + 真机双色截图对比 PR
