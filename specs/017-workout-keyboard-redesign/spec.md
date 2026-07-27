# Feature Spec — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Parent issue**: MY-1342
**Sub-issues (stages)**: T017-01 现状截图诊断 → T017-02 north-star + Prototype 落地（隔离） → **T017-02b Stage 2 post-merge doc alignment (recovery)** → T017-03 客观 design review（获批） → T017-04 生产键盘迁移
**Constitution refs**: §II Swift 6 strict concurrency、§III SPM 优先（Prototype 隔离在 `Prototype/` SPM package）、§IV XcodeGen 真理之源、§VII 范围克制
**Related docs**: `design/keyboard-redesign-audit.md`（2026-07-14 已完成审计，此 spec 承接其 P0/P1 结论并追加"隔离 prototype + 客观 review"门禁）；`design/north-star.md` §11
**Version**: v2 (2026-07-27, incremental fix over v1) — retrofit Stage 2 scope after PR #362 merged with three out-of-scope but functionally-necessary changes (Prototype/Package.swift additive executable target, PrototypeShotExporter CLI, targeted .gitignore additions). v2 authorizes these as canonical; no revert. Adds T017-02b as the recovery/alignment sub-issue.

---

## 1. Background & Motivation

用户反馈「现在的自定义键盘太难看了」。MY-1342 的现状基线：

- `VitalStride/Sources/WorkoutNumericKeyboard.swift`（`WorkoutNumericKeyboardContentView` + `UIView`+`UIHostingController` 桥）
- `VitalStride/Sources/NumericKeypad.swift`（数字网格）
- 已通过 `resolveTheme(isDark:)` 显式把 `Theme(seed:.teal, neutral:.slate)` 注入 host，解决了 2026-07-14 审计里的「theme 孤儿」P0 根因。
- 但**观感层面**——三列信息密度不均、功能/预设/数字键视觉权重雷同、圆角/间距节奏不精致、深/浅色都不够 polished——仍未系统性打磨。

审计（`design/keyboard-redesign-audit.md`）已给出：P0 数字键对比度、P1 硬编码系统色替换 DesignKit token、P1 中英混排本地化、P1 窄屏三列挤压、P2 三类键视觉层级分档、P3 Done 键 `onPrimary` 自动对比。

**本 feature 的增量**：在审计成果之上，按 TL 门禁流程走完——截图诊断 → north-star + 隔离 prototype → 客观 design review → 获批后迁移到生产。

### v2 增量：Stage 2 post-merge 现实

PR #362 (MY-1350) 已合入 main（commit `25d95cd`, 2026-07-27T15:56:04Z）。除 v1 声明的 Files in scope 外，多出三项**功能必要**改动：

| 已合入文件 | v1 状态 | v2 决策 | 理由 |
|---|---|---|---|
| `Prototype/Package.swift` (+43) | 曾禁改 | **保留**（authorize） | v1 verification 要求 `swift build --package-path Prototype` + 4 张 PNG，但 v1 Prototype 只有 library target；导出 PNG 必须有 executable target。新增的 `PrototypeShotExporter` executable target 是**加法性**（library target 不动），不引入生产依赖 |
| `Prototype/Sources/PrototypeShotExporter/main.swift` (+85, new) | 未声明 | **保留** | macOS-only CLI，`import AppKit` + SwiftUI `ImageRenderer`；仅供 `swift run --package-path Prototype PrototypeShotExporter <dir>` 手动导出截图，不进任何 app target；封装了 v1 一直缺失的截图机制 |
| `.gitignore` (+7/-2) | 未声明 | **保留** | 只添加 `Prototype/.build/`、`Prototype/.swiftpm/` 之类的 SPM 产物忽略；不影响生产 |

**红线**（v2 加入）：`PrototypeShotExporter` 是**设计工具**，**不进任何 app target 依赖图**、**不能被 VitalStride/VitalStrideMac/VitalStrideWatch scheme 引用**、**不注册进 xcodegen**。

## 2. In Scope

1. `design/keyboard-current-shots/`——现状 iPhone / iPad × 浅色/深色 × {working set / warmup / reps 输入} 组合共 ≥6 张截图，附 `diagnosis.md` 逐图标注视觉问题
2. `design/north-star.md` 追加 §11「Workout Numeric Keyboard」子章节
3. `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`——隔离 SwiftUI prototype
4. **`Prototype/Package.swift` 追加 `PrototypeShotExporter` executable target + product**（v2 授权：additive only；library target 冻结）
5. **`Prototype/Sources/PrototypeShotExporter/main.swift`**——macOS-only CLI，SwiftUI → PNG（v2 授权）
6. **`.gitignore` 针对性追加**——仅忽略 `Prototype/.build/` 和 `Prototype/.swiftpm/`（v2 授权）
7. `design/prototype-shots/keyboard-*.png`——从 `swift run --package-path Prototype PrototypeShotExporter design/prototype-shots` 导出，iPhone / iPad × 浅色/深色 ≥4 张
8. `design/keyboard-review.md`——客观 design review 报告
9. 获批后（review report 结论 = PASS + Team Lead 显式回执确认）迁移到生产 `WorkoutNumericKeyboard.swift` + `NumericKeypad.swift`
10. **T017-02b（recovery）**：把本 v2 spec/plan/tasks 内容写回 main 的 `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md`，让 on-main 文档 = merged 现实

## 3. Out of Scope (explicit)

- 交互契约任何改动（回调、`LeftKeyAction`、`SetField`、disabled 逻辑、`lastRepsByBucket` cycling **全部冻结**）
- 高度策略：iPad 260 / iPhone 240pt 本身不改
- 输入处理：`SelectAllTextField` / `NumericKeypadInputHandler` / 全选覆盖 bug（另 issue）
- `VitalStride/Sources/ActiveWorkout/SetRow.swift` / `ActiveWorkoutView.swift` 键盘 wiring
- watchOS / macOS 生产键盘（本组件 iOS-only；`PrototypeShotExporter` 是 macOS 但**不是 app target**）
- 全新 audit（保留 2026-07-14 audit）
- DesignKit token 新增或修改（只消费现有 `theme.primary.*` / `theme.neutrals.*`）
- **`PrototypeShotExporter` 进 app target 依赖图**（红线，禁）
- **Revert PR #362 的任何 hunk**（v2 明确不回退；只对齐文档）

## 4. Visual North-Star Boundary（本 feature 定义什么算"好看"）

north-star §11 必须给出的**可检查**条目：圆角三档（`Radius.card=14` / `Radius.inner=10` / 数字键自定 pt）、间距（列/行/padding/minHeight 均 `Space.*` scale）、三档配色（primary/primarySubtle/inner，token 路径完整）、字号（TypeScale 或 font，数字 `.monospacedDigit()`）、每键 `foregroundStyle` token（数字键**必须** `text1`——红线，禁 audit P0 复发）、深/浅色参考截图路径。

**红线（P0，写死意图）**：
- 数字键**必须有** `.foregroundStyle` token 指向 `text1`
- 深/浅色都不允许出现「文字与背景对比度 <4.5:1」的键
- 44pt hit target 覆盖所有键
- 键盘总高 iPad ≤280 / iPhone ≤260pt

## 5. Functional Requirements

- **FR-1**（T017-01，已 done in commit `d8d526e`）：≥6 张现状截图 + `diagnosis.md`
- **FR-2**（T017-02a，已 done in PR #362）：`design/north-star.md` 追加 §11
- **FR-3**（T017-02a，已 done in PR #362）：`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift`——独立 SwiftUI view，仅 DesignKit 依赖；≥4 个 `#Preview`
- **FR-3.1**（v2 新增，已 done in PR #362）：`Prototype/Package.swift` 追加 `PrototypeShotExporter` executable target；library `Prototype` target 冻结，dependencies **保持** `[.product(name: "DesignKit", ...)]`
- **FR-3.2**（v2 新增，已 done in PR #362）：`Prototype/Sources/PrototypeShotExporter/main.swift`——macOS-only（`import AppKit`）；纯设计工具；`swift run --package-path Prototype PrototypeShotExporter <output-dir>` 导出 4 PNG；**不 import** 除 SwiftUI/AppKit/DesignKit/Prototype 之外的任何模块；**不进 app target 依赖图**
- **FR-4**（T017-02a，已 done in PR #362）：`design/prototype-shots/keyboard-{iphone,ipad}-{light,dark}.png` ≥4 张
- **FR-5**（T017-02b，v2 新增，待做）：把 v2 spec/plan/tasks 内容写回 main 的 `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md`，取代 v1 版本
- **FR-6**（T017-03，待做，被 T017-02b 阻塞）：`design/keyboard-review.md` 客观 review 报告，结构五段固定
- **FR-7**（T017-04，待做，被 T017-03 PASS 门禁 + TL 回执双门禁）：生产键盘迁移
- **FR-8**：全流程零硬编码颜色/魔法数

## 6. Non-Functional Constraints

- Swift 6 strict concurrency；禁 `@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)`
- Prototype library target 独立性：`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` **不 import** `VitalStride` / `VitalModels` / `SwiftData` / `HealthKitService` / `AIService` / `VitalUI` / `UIKit`
- PrototypeShotExporter 隔离性：**不进任何 app target 依赖图**；`grep -rn 'PrototypeShotExporter' VitalStride*/Sources` 必须为空；`project.yml` 不引用它
- 训练/健康数值禁进日志
- 生产迁移零回归

## 7. Executable Acceptance Probes（v2 权威列表）

### T017-01（Stage 1，已完成 in `d8d526e`）
```
[ "$(ls design/keyboard-current-shots/*.png | wc -l | tr -d ' ')" -ge "6" ]
[ -s design/keyboard-current-shots/diagnosis.md ]
grep -qE 'P[0-3]' design/keyboard-current-shots/diagnosis.md
```

### T017-02a（Stage 2 视觉产出，已完成 in `25d95cd` PR #362）
```
grep -qE '^## 11\. Workout Numeric Keyboard|^## 11\. 训练页.*键盘' design/north-star.md
grep -qE 'Radius|圆角' design/north-star.md
grep -qE 'primary|primarySubtle|inner' design/north-star.md
grep -qE 'foregroundStyle|text1' design/north-star.md
[ -f Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift ]
! grep -E '^import (VitalStride|VitalModels|SwiftData|HealthKitService|AIService|VitalUI)' \
     Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift
[ "$(grep -c '#Preview' Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift)" -ge "4" ]
swift build --package-path Prototype
[ "$(ls design/prototype-shots/keyboard-*.png | wc -l | tr -d ' ')" -ge "4" ]
```

### T017-02b（Stage 2 post-merge doc alignment，v2 新增）
```
# S1: v2 spec/plan/tasks 内容写回 main
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/spec.md
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/plan.md
grep -q '^\*\*Version\*\*: v2' specs/017-workout-keyboard-redesign/tasks.md

# S2: spec/plan/tasks 明列已合入 out-of-scope 文件的 v2 处置（保留 or revert）
grep -qE 'PrototypeShotExporter' specs/017-workout-keyboard-redesign/spec.md
grep -qE '\.gitignore' specs/017-workout-keyboard-redesign/spec.md

# S3: PrototypeShotExporter 未进 app target 依赖图
! grep -rn 'PrototypeShotExporter' VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' project.yml 2>/dev/null

# S4: PrototypeShotExporter 不 import 生产模块
! grep -E '^import (VitalStride|VitalModels|SwiftData|HealthKitService|AIService|VitalUI)' \
     Prototype/Sources/PrototypeShotExporter/main.swift

# S5: Prototype library target dependencies 未被污染
swift package dump-package --package-path Prototype \
  | jq -e '.targets[] | select(.name == "Prototype") | (.dependencies | length == 1) and (.dependencies[0].product[0] == "DesignKit")'

# S6: Prototype 仍可 build + PNG 导出可复现
swift build --package-path Prototype
swift run --package-path Prototype PrototypeShotExporter design/prototype-shots
```

### T017-03（Stage 3，待做，被 T017-02b 门禁）
```
[ -s design/keyboard-review.md ]
grep -qE '^## vs north-star' design/keyboard-review.md
grep -qE '^## vs audit' design/keyboard-review.md
grep -qE '^## a11y' design/keyboard-review.md
grep -qE '^## 高度实测' design/keyboard-review.md
grep -qE '^## 结论' design/keyboard-review.md
grep -qE '^## 结论.*PASS' design/keyboard-review.md   # 提升 T017-04 前必查
```

### T017-04（Stage 4，待做，被 T017-03 PASS + TL 回执双门禁）

见 v1，未变化。核心：`xcodebuild build`、三个现有测试全 pass、grep 门禁清零硬编码/并发规避、`git diff github/main...HEAD` 反证契约冻结、`.isKeyboardKey` trait 数不减少。

## 8. Rollout & Verification

- Stage 1 = T017-01（done 2026-07-27T13:xx）
- Stage 2a = T017-02a（done 2026-07-27T15:56 in PR #362，视觉产出真实到位；文档滞后）
- **Stage 2b = T017-02b（recovery，本 v2 新增；由 Fullstack 起手，恢复 on-main 文档 = merged 现实）**
- Stage 3 = T017-03（backlog，被 T017-02b 门禁）
- Stage 4 = T017-04（backlog，被 T017-03 PASS + TL 回执双门禁）

## 9. Source-of-truth pointers

- 现状代码：`VitalStride/Sources/WorkoutNumericKeyboard.swift`、`VitalStride/Sources/NumericKeypad.swift`（不动）
- 历史 audit：`design/keyboard-redesign-audit.md`（2026-07-14）
- north-star：`design/north-star.md` §11
- Prototype：`Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` + `Prototype/Sources/PrototypeShotExporter/main.swift`（v2 authorize）
- Prototype 截图：`design/prototype-shots/keyboard-*.png`
- 已 merged commit：`25d95cd` (PR #362)、`b278080` (PR #360)、`d8d526e` (PR #355)
- 仓库：https://github.com/LeePepe/VitalStride
