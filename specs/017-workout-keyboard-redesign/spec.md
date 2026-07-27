# Feature Spec — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Parent issue**: MY-1342
**Sub-issues (stages)**: T017-01 现状截图诊断 → T017-02 north-star + Prototype 落地（隔离） → T017-03 客观 design review（获批） → T017-04 生产键盘迁移
**Constitution refs**: §II Swift 6 strict concurrency、§III SPM 优先（Prototype 隔离在 `Prototype/` SPM package）、§IV XcodeGen 真理之源、§VII 范围克制
**Related docs**: `design/keyboard-redesign-audit.md`（2026-07-14 已完成审计，此 spec 承接其 P0/P1 结论并追加"隔离 prototype + 客观 review"门禁）；`design/north-star.md`（app 级视觉北极星，本 feature 追加键盘子章节）
**Version**: v1 (2026-07-27)

---

## 1. Background & Motivation

用户反馈「现在的自定义键盘太难看了」。MY-1342 的现状基线：

- `VitalStride/Sources/WorkoutNumericKeyboard.swift`（`WorkoutNumericKeyboardContentView` + `UIView`+`UIHostingController` 桥）
- `VitalStride/Sources/NumericKeypad.swift`（数字网格）
- 已通过 `resolveTheme(isDark:)` 显式把 `Theme(seed:.teal, neutral:.slate)` 注入 host，解决了 2026-07-14 审计里的「theme 孤儿」P0 根因（audit §根因）。
- 但**观感层面**——三列信息密度不均、功能/预设/数字键视觉权重雷同、圆角/间距节奏不精致、深/浅色都不够 polished——仍未系统性打磨。

审计（`design/keyboard-redesign-audit.md`）已给出：
- P0 数字键对比度（`.foregroundStyle(text1)`）
- P1 硬编码系统色替换 DesignKit token
- P1 中英混排本地化
- P1 窄屏三列挤压
- P2 三类键视觉层级分档（primary / primarySubtle / inner）
- P3 Done 键 `onPrimary` 自动对比

**本 feature 的增量**：在审计成果之上，把「重设计」按 TL 指示的门禁流程走完——
1. 先以现状深/浅色截图做**具体**诊断（补齐视觉层的量化基线）；
2. 定义可检查的**视觉 north-star**（键盘子章节）；
3. 在**隔离 prototype**（不改生产键盘）里落地重设计，输出双色截图；
4. 通过客观 **design review**（对照 north-star + audit 全条目 + a11y）；
5. **获批后**才迁移到生产 `WorkoutNumericKeyboard.swift` / `NumericKeypad.swift`。

## 2. In Scope

1. `design/keyboard-current-shots/`——现状 iPhone / iPad × 浅色/深色 × {working set / warmup / reps 输入} 组合共 ≥6 张截图，附 `diagnosis.md` 逐图标注视觉问题
2. `design/north-star.md` 追加 §11「Workout Numeric Keyboard」子章节：布局节奏、圆角/间距、三档层级配色、字号、a11y 与高度约束，全部**可对照检查**（不写"精致""干净"这类无法验的形容词）
3. `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`——隔离 SwiftUI prototype，纯 view-only（**不桥 UIKit inputView**、**不触碰生产 SetRow/ActiveWorkoutView**、**不依赖 SwiftData/VitalModels**），双色 `#Preview`
4. `design/prototype-shots/keyboard-*.png`——prototype 输出 iPhone / iPad × 浅色/深色 组合共 ≥4 张
5. `design/keyboard-review.md`——客观 design review 报告：对照 north-star §11 逐条打钩、对照 audit 全条目回归、a11y 逐条（≥44pt、VoiceOver、Dynamic Type、Reduce Motion）、高度约束（iPad ≤280 / iPhone ≤260pt）实测数字
6. **获批后**（review report 结论 = PASS + Team Lead 显式回执确认）才启动 T017-04：把 prototype 里已定型的视觉决策迁移到生产 `VitalStride/Sources/WorkoutNumericKeyboard.swift` + `NumericKeypad.swift`，保持所有回调 / disabled / preset cycling / a11y 契约零回归

## 3. Out of Scope (explicit)

- **交互契约任何改动**——`onKeyPress` / `onLeftAction` / `onPresetReps` / `onDone` 回调签名、`LeftKeyAction` 枚举、`SetField.isDecimalEnabled` 语义、`ExerciseDefaults.resolvePreset` 算法、`lastRepsByBucket` cycling **全部冻结**
- Disabled 逻辑：`setType != .working` 时金字塔/递减 disabled——语义**不动**
- 高度策略：iPad 260 / iPhone 240pt（`WorkoutNumericKeyboard.preferredHeight()`）本身不改；重设计只在此约束内布局
- 输入处理：`SelectAllTextField` / `NumericKeypadInputHandler` / 全选覆盖输入 bug（另 issue）
- `VitalStride/Sources/ActiveWorkout/SetRow.swift` 及 `ActiveWorkoutView.swift` 的键盘 wiring——生产迁移只改键盘本身两个文件
- watchOS / macOS——这块键盘只在 iOS/iPadOS 出现（`#if canImport(UIKit) && !os(macOS)`）
- 全新的 audit（已有 2026-07-14 audit，只追加视觉基线截图和补充诊断）
- DesignKit token 新增或修改——只**消费**现有 `theme.primary.*` / `theme.neutrals.*`

## 4. Visual North-Star Boundary（本 feature 定义什么算"好看"）

**判据必须机器可查或双人对照可查。** 反面例子：「更精致」「更协调」「更专业」——这些不写进 north-star §11。

north-star §11 必须给出的**可检查**条目（详见 T017-02 DoR）：

- 圆角：三档键分别用哪个 `Radius` 值（`Radius.card=14` / `Radius.inner=10` / 数字键自定 12 等），有 hex 化的 pt 值
- 间距：列间距、行间距、键盘四周 padding、每个键的 minHeight 明确 pt 值，落 `Space.gap` / `Space.cardPadding` scale
- 配色三档：primary（Done）/ primarySubtle（preset）/ inner（功能键 + 数字键背景）——每档明确 token 路径 `theme.xxx.yyy`，禁 hardcode hex
- 字号：数字键 / 功能键 / preset 键 / Done 键分别用哪个 `TypeScale` 或 `.font(...)`，均 `.monospacedDigit()` 若含数字
- 前景色：每个键的 `foregroundStyle` token（**这是 audit P0 的直接对应**）
- 深/浅色都要给出「参考截图」——review 时对齐

**红线（P0，写死意图）**：
- 数字键**必须有** `.foregroundStyle` token 指向 `text1`（audit P0 根因，禁复发）
- 深/浅色都不允许出现「文字与背景对比度 <4.5:1」的键
- 44pt hit target 覆盖所有 12+4+3+1=20 个键
- 键盘总高 iPad ≤280 / iPhone ≤260pt

## 5. Functional Requirements

- **FR-1**（T017-01）：产出 ≥6 张现状截图 + `design/keyboard-current-shots/diagnosis.md`——每张图逐点标注视觉问题（引用 audit 编号 P0/P1/P2/P3，或新增编号），不重复 audit 已覆盖内容
- **FR-2**（T017-02a）：`design/north-star.md` 追加 §11「Workout Numeric Keyboard」，含 §4 列出的**全部可检查条目**
- **FR-3**（T017-02b）：`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`——独立 SwiftUI view，依赖仅 `DesignKit`；至少 4 个 `#Preview`（iPhone 浅/深 + iPad 浅/深）；每个 preview 覆盖 working set + warmup（后者验证 disabled 视觉）
- **FR-4**（T017-02c）：`design/prototype-shots/keyboard-{iphone,ipad}-{light,dark}.png` ≥4 张，从 prototype `#Preview` 导出
- **FR-5**（T017-03）：`design/keyboard-review.md` 客观 review 报告，section 结构固定：`## vs north-star §11`（逐条打钩） / `## vs audit（2026-07-14）`（逐条回归） / `## a11y`（44pt / VoiceOver / Dynamic Type / Reduce Motion） / `## 高度实测` / `## 结论 PASS/FAIL + 决策`；FAIL 需列具体不达标项
- **FR-6**（T017-04，**被 T017-03 PASS 门禁**）：迁移到 `VitalStride/Sources/WorkoutNumericKeyboard.swift` + `NumericKeypad.swift`；契约验证：`WorkoutNumericKeyboardThemeTests` + `NumericKeypadTests` + `WorkoutCopyToNextTests` 全 pass；新增 view snapshot 或 preview validity 测试（如现有测试基础设施不支持，补一条 UIKit host 层构造烟测）
- **FR-7**：全流程零硬编码颜色/魔法数——`grep -rn 'Color\.[a-z]\|Color(hex\|#[0-9A-Fa-f]\{6\}' VitalStride/Sources/WorkoutNumericKeyboard.swift VitalStride/Sources/NumericKeypad.swift` 必须为空

## 6. Non-Functional Constraints

- Swift 6 strict concurrency：所有新 view `Sendable` 属性；`@MainActor` 边界与现状一致；禁 `@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)`
- Prototype 独立性：`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` **不 import VitalModels / SwiftData / VitalStride**——用 mock enum 复制 `SetField` / `LeftKeyAction` / `PresetRepBucket` 的最小 shape 即可；确保 prototype 可独立 `swift build --package-path Prototype`
- 训练/健康数值禁进日志（constitution §I 红线）
- 生产迁移零回归：交互契约、disabled 逻辑、preset cycling、a11y label/trait、高度约束、hit target 全保留
- watchOS/macOS 不受影响（本组件 iOS-only）

## 7. Executable Acceptance Probes（v1 权威列表 — 与 tasks.md 和四个 sub-issue DoR 逐字一致）

**执行位置**：Multica daemon 提供的 `<task-dir>/workdir/` — 仓库根；**禁 `cd` 到用户主 checkout**。

### T017-01（现状截图诊断）probes

```
# A-1 至少 6 张现状截图
[ "$(ls design/keyboard-current-shots/*.png 2>/dev/null | wc -l | tr -d ' ')" -ge "6" ]

# A-2 diagnosis 文件存在且非空
[ -s design/keyboard-current-shots/diagnosis.md ]

# A-3 diagnosis 引用 audit 编号（P0/P1/P2/P3 至少一次）
grep -qE 'P[0-3]' design/keyboard-current-shots/diagnosis.md
```

### T017-02（north-star §11 + Prototype + prototype 截图）probes

```
# B-1 north-star §11 存在
grep -qE '^## 11\. Workout Numeric Keyboard|^## 11\. 训练页.*键盘' design/north-star.md

# B-2 north-star §11 覆盖必检项（关键词至少各出现一次）
grep -qE 'Radius|圆角' design/north-star.md
grep -qE 'Space\.|padding|间距' design/north-star.md
grep -qE 'primary|primarySubtle|inner' design/north-star.md
grep -qE 'foregroundStyle|text1' design/north-star.md

# B-3 Prototype 文件存在
[ -f Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift ]

# B-4 Prototype 不 import 生产模块
! grep -E '^import (VitalStride|VitalModels|SwiftData|HealthKitService|AIService|VitalUI)' \
     Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift

# B-5 Prototype ≥4 个 #Preview
[ "$(grep -c '#Preview' Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift)" -ge "4" ]

# B-6 Prototype 可独立 build
swift build --package-path Prototype

# B-7 prototype 截图 ≥4 张（iPhone/iPad × light/dark）
[ "$(ls design/prototype-shots/keyboard-*.png 2>/dev/null | wc -l | tr -d ' ')" -ge "4" ]
```

### T017-03（design review 报告）probes

```
# C-1 review 文件存在
[ -s design/keyboard-review.md ]

# C-2 结构固定五段
grep -qE '^## vs north-star' design/keyboard-review.md
grep -qE '^## vs audit' design/keyboard-review.md
grep -qE '^## a11y' design/keyboard-review.md
grep -qE '^## 高度实测' design/keyboard-review.md
grep -qE '^## 结论' design/keyboard-review.md

# C-3 结论必须是 PASS 才允许 T017-04 起步（TL 门禁）
grep -qE '^## 结论.*PASS' design/keyboard-review.md
```

### T017-04（生产迁移）probes

```
# D-1 iOS build（键盘只在 iOS/iPadOS 生效）
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

# D-2 键盘相关测试全 pass
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/WorkoutNumericKeyboardThemeTests \
  -only-testing:VitalStrideTests/NumericKeypadTests \
  -only-testing:VitalStrideTests/WorkoutCopyToNextTests

# D-3 契约零变更（回调签名、LeftKeyAction、SetField 全冻结）
! git diff github/main...HEAD -- VitalStride/Sources/WorkoutNumericKeyboard.swift \
    | grep -E '^-.*func (onKeyPress|onLeftAction|onPresetReps|onDone)|^-.*enum LeftKeyAction|^-.*case (addPyramid|addDropSet|toggleUnilateral|copyToNext)'

# D-4 零硬编码颜色 / 系统色 / hex
! grep -rnE 'Color\.(red|blue|green|orange|yellow|purple|pink|white|black|gray)|Color\(hex|#[0-9A-Fa-f]{6}|systemGroupedBackground|secondarySystemBackground|tertiarySystemBackground|accentColor' \
     VitalStride/Sources/WorkoutNumericKeyboard.swift VitalStride/Sources/NumericKeypad.swift

# D-5 无并发规避
! grep -rnE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources/WorkoutNumericKeyboard.swift VitalStride/Sources/NumericKeypad.swift

# D-6 高度常量不变
grep -qE '(260|280)' VitalStride/Sources/WorkoutNumericKeyboard.swift  # iPad
grep -qE '(240|260)' VitalStride/Sources/WorkoutNumericKeyboard.swift  # iPhone

# D-7 a11y trait 全保留（.isKeyboardKey 数量不减少）
[ "$(grep -c '.isKeyboardKey' VitalStride/Sources/WorkoutNumericKeyboard.swift)" -ge "$(git show github/main:VitalStride/Sources/WorkoutNumericKeyboard.swift | grep -c '.isKeyboardKey')" ]
```

## 8. Rollout & Verification

- Stage 1 = T017-01 →Stage 2 = T017-02 →Stage 3 = T017-03 →Stage 4 = T017-04（强顺序、无并行）
- **T017-04 的解锁门禁 = T017-03 review 结论 PASS + Team Lead comment 显式确认**——TL 提升 T017-04 backlog→todo 之前必须验此门禁
- 每个 stage 完成后 `multica issue comment add` 附截图/文件路径，@mention Team Lead 交回

## 9. Source-of-truth pointers

- 现状代码：`VitalStride/Sources/WorkoutNumericKeyboard.swift`、`VitalStride/Sources/NumericKeypad.swift`、`VitalStride/Sources/ActiveWorkout/SetRow.swift`（不动，仅参考）
- 历史 audit：`design/keyboard-redesign-audit.md`（2026-07-14）
- app 视觉基线：`design/north-star.md`（本 feature §T017-02 追加 §11）
- 现有测试：`VitalStrideTests/Sources/WorkoutNumericKeyboardThemeTests.swift`、`NumericKeypadTests.swift`、`WorkoutCopyToNextTests.swift`
- Prototype package：`Prototype/Package.swift`（swift 6.2、依赖 DesignKit）
- 仓库：https://github.com/LeePepe/VitalStride
