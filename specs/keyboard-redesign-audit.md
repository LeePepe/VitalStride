# 训练页自定义数字键盘 — 设计审计 + 重设计 spec

**组件**: `WorkoutNumericKeyboard.swift` + `NumericKeypad.swift`（`SelectAllTextField` 作为 `UITextField.inputView` 安装）
**平台**: iOS SwiftUI + DesignKit 设计系统
**方法**: impeccable `audit`（native / iOS）+ 重设计 spec
**日期**: 2026-07-14

---

## 🔴 平台一致性判定（Platform Conformance Verdict）

**不通过。** 这块键盘读起来像"从别的地方移植来的控件"，不是 app 的一部分。三个致命信号：
1. 数字键**看不见**（对比度 bug）——用户截图里 9 个数字键几乎全白。
2. 键盘**不接 DesignKit 主题**——硬编码 `systemGroupedBackground` / `secondarySystemBackground`，与 app 的 teal/slate 深色主题割裂。
3. 中英混排（`+↑` `Uni/Total` `Copy` `Done`）出现在全中文界面里。

---

## Audit Health Score

| # | 维度 | 分 | 关键问题 |
|---|------|----|---------|
| 1 | Accessibility | 2 | 数字键对比度失败（不可见）；触达尺寸勉强；a11y label 齐全是亮点 |
| 2 | Performance | 4 | 无问题：LazyVGrid、hosting 复用、update 只重渲染 |
| 3 | Appearance & Theming | 1 | 键盘完全绕过 DesignKit theme，硬编码系统色；数字键无前景色 |
| 4 | Platform Conformance | 2 | inputView 未继承 SwiftUI 环境 → theme 断链；中英混排 |
| 5 | Adaptivity | 2 | 三列固定 84pt 侧栏，窄屏挤压中间数字区；Dynamic Type 上限截断 |
| **总分** | | **11/20** | **Acceptable — 需要显著返工** |

---

## 🎯 根因（一条链，全部代码验证）

**`UITextField.inputView` 的 `UIHostingController` 不继承 SwiftUI `.designTheme` 环境。**

1. `VitalStrideApp.swift:77` 在**根视图**注入 `.designTheme(seed: .teal, neutral: .slate)`——全 app 的 `@Environment(\.theme)` 靠它。
2. 但键盘走 `SelectAllTextField.swift:161` → `WorkoutNumericKeyboard(...)` → `UIHostingController(rootView:)`（`WorkoutNumericKeyboard.swift:314`），**imperatively 创建、挂到 `textField.inputView`**。
3. inputView 是独立 UIKit 视图层级，**不在 root SwiftUI 环境树里** → `@Environment(\.theme)` 拿到的是 `ThemeKey.defaultValue = Theme()`，即**默认 `seed:.blue, neutral:.slate, isDark:false`**（`Theme.swift:59`）——**永远浅色、永远蓝、不随系统深浅变、不随 app 的 teal 变**。
4. `NumericKeypad` 读 `theme.neutrals.card`（default = 白 `#FFFFFF`）当数字键背景；但 `NumericKeypad.swift:98` 的 `Text(key.label)` **完全没有 `.foregroundStyle`** → 数字文字用 SwiftUI 默认 `.primary`，它跟随**系统** colorScheme（深色下=白）。
5. 结果：**系统深色 + theme 强制浅色 card=白背景 + 文字默认=白** → **白底白字，数字消失**。这就是截图现象。

> 一句话：键盘的 theme 是"孤儿"，被钉死在 default 浅色，而文字色又跟随系统深色，两者打架 → 不可见。

---

## Detailed Findings（按严重度）

### [P0] 数字键不可见 — 对比度归零
- **位置**: `NumericKeypad.swift:98-99`（`Text(key.label)` 无 foregroundStyle）+ theme 断链（根因）
- **类别**: Accessibility / Theming
- **影响**: 用户**看不到数字键**，核心录入功能不可用（截图实证）
- **Guideline**: WCAG 1.4.3（正文≥4.5:1）；HIG「Dark Mode 一等公民」
- **修复**: ① 修 theme 断链（见下方架构修复）；② 数字键 `Text` 显式 `.foregroundStyle(theme.neutrals.text1)`。修复后：light `#1C2024`/白=**16.4:1**，dark `#EDEEF0`/`#18191B`=**15.2:1**，均远超 4.5。

### [P0] 键盘绕过 DesignKit 主题（架构）
- **位置**: `WorkoutNumericKeyboard.swift:314`（host 创建）+ `SelectAllTextField.swift:161`
- **类别**: Theming / Conformance
- **影响**: 键盘不随 app 的 teal 主题、不随系统深浅色变——永远错误的浅蓝默认态
- **修复**: **inputView host 必须显式注入 theme + colorScheme**。见架构修复 A。

### [P1] 硬编码系统色，与 DesignKit 割裂
- **位置**: `WorkoutNumericKeyboard.swift:86`（`systemGroupedBackground`）、`131`（`secondarySystemBackground`）、`200`（`tertiarySystemBackground`）、`217`（`accentColor`）
- **类别**: Theming
- **影响**: 键盘背景/功能键/preset 键用 UIKit 系统色，与 DesignKit 的 `bg/card/inner/primary` 不是一套，seed 切换时键盘不变
- **修复**: 全部换 DesignKit token（见重设计 spec 配色表）

### [P1] 中英文混排
- **位置**: `WorkoutNumericKeyboard.swift:97`（`+↑`）、`102`（`+↓`）、`106`（`Uni/Total`）、`111`（`Copy`）、`212`（`Done`）
- **类别**: Conformance / i18n
- **影响**: 全中文界面里蹦出英文标签，不专业。`Uni/Total`/`Copy`/`Done` 的 defaultValue 是英文，中文本地化缺失
- **修复**: 补中文本地化 —— `Copy`→「复制」、`Done`→「完成」、`Uni/Total`→「单侧/合计」；`+↑`/`+↓`→用 SF Symbol `arrow.up.to.line`/`arrow.down.to.line` + 中文 a11y（图标跨语言，优于字母）

### [P1] 三列布局窄屏挤压
- **位置**: `WorkoutNumericKeyboard.swift:76-84`（左右各 `maxWidth: 84` 固定侧栏）
- **类别**: Adaptivity
- **影响**: iPhone 上左右各吃 84pt，中间数字键被压窄，数字键触达面积受损；SE 等窄屏更糟
- **修复**: 侧栏改 `maxWidth: 72` + 中间 `minWidth`保护；或窄屏下 preset 键并入数字区上方一行（见 spec 布局）

### [P2] 功能键 / preset 键层级不清
- **位置**: 左列 4 功能键 + 右列 3 preset + Done，视觉权重雷同
- **类别**: Hierarchy
- **影响**: preset reps（高频、正向操作）和功能键（低频、结构操作）长得一样，扫视找不到重点
- **修复**: preset 键用 `primarySubtle` 底 + `primaryText`（品牌色弱提示，表"推荐值"）；功能键用 `inner` 底 + `text2`（中性、次要）；Done 用实心 `primary` + `onPrimary`（主操作）

### [P2] Dynamic Type 被截断
- **位置**: `NumericKeypad.swift:78`（`.dynamicTypeSize(...xxxLarge)`）+ 功能键 `.subheadline` 固定
- **类别**: Accessibility
- **影响**: 超大字号用户被 cap；`Uni/Total` 这种长标签在大字号下会截断
- **修复**: 数字键可保留 cap（键盘布局约束合理），但功能键标签改用图标+短词，避免长文本截断

### [P3] Done 键浅色下对比偏低
- **位置**: `WorkoutNumericKeyboard.swift:215-217`（白字 on accentColor）
- **类别**: Contrast
- **影响**: teal `#12A594` + 白字 = 3.07:1，大字勉强过（≥3），非最佳
- **修复**: 用 `theme.primary.onPrimary`（DesignKit 已按对比度自动选黑/白，`contrastChoose`）替代硬编码 `.white`

---

## Positive Findings（保留）
- ✅ a11y label / trait 齐全（`.isKeyboardKey`、每键有 localized a11yLabel）
- ✅ 性能好：LazyVGrid、host 复用、`update()` 只重渲染
- ✅ 音频/触觉反馈（`playInputClick` + `UIImpactFeedbackGenerator`）
- ✅ 逻辑与视图分离（`NumericKeypadInputHandler` 纯函数、`onKeyPress` 回调）
- ✅ preset reps 的 cycling 状态设计（`lastRepsByBucket`）体验用心

---

## 🛠 重设计 spec（全部用 DesignKit token）

### 架构修复 A（P0，前置）— 给 inputView 注入 theme + colorScheme

`WorkoutNumericKeyboard`（UIView）在 `setUp()` 里为 host 的 rootView 注入 theme，且跟随系统 colorScheme：

```swift
// WorkoutNumericKeyboard.init / update：构造 content 时用 traitCollection 的深浅色
private func resolvedTheme() -> Theme {
    let isDark = traitCollection.userInterfaceStyle == .dark
    return Theme(seed: .teal, neutral: .slate, isDark: isDark)   // 与 VitalStrideApp 根注入一致
}
```
content view 改为**显式接收 theme**（而非读 `@Environment`），或在 host.rootView 外层包 `.environment(\.theme, resolvedTheme())`。并重写 `traitCollectionDidChange` 在系统深浅色切换时刷新。

> 关键：inputView 脱离 SwiftUI 环境树，**必须手动搭桥**。这是 P0 根因，先修这个，数字键才能拿到正确 card 背景。

### 配色表（现状 → 重设计）

| 元素 | 现状（硬编码/缺失） | 重设计（DesignKit token） | 对比度 |
|---|---|---|---|
| 键盘整体背景 | `systemGroupedBackground` | `theme.neutrals.bg` | — |
| 数字键背景 | `theme.neutrals.card`（但 theme 是孤儿） | `theme.neutrals.card`（theme 修好后正确） | — |
| **数字键文字** | **无 foregroundStyle（BUG）** | **`theme.neutrals.text1`** | **16.4:1 / 15.2:1** ✅ |
| 数字键边框 | `theme.neutrals.border` | `theme.neutrals.border`（保留） | — |
| 删除键 ⌫ 背景 | `theme.neutrals.inner` | `theme.neutrals.inner`（保留）+ 文字 `text2` | — |
| 功能键（+↑/+↓/单侧/复制）背景 | `secondarySystemBackground` | `theme.neutrals.inner` | — |
| 功能键文字 | `Color.primary`（系统） | `theme.neutrals.text2` | ✅ |
| preset 键（15-20 等）背景 | `tertiarySystemBackground` | `theme.primary.primarySubtle` | — |
| preset 键文字 | 默认 | `theme.primary.primaryText` | ✅（token 保证） |
| Done 键背景 | `accentColor` | `theme.primary.primary` | — |
| Done 键文字 | 硬编码 `.white` | `theme.primary.onPrimary`（自动选黑/白） | ✅ contrastChoose |

### i18n 修复

| 现 | 改 | 备注 |
|---|---|---|
| `+↑` | SF Symbol `arrow.up.to.line` | 图标跨语言；a11y「递增子组」 |
| `+↓` | SF Symbol `arrow.down.to.line` | a11y「递减子组」 |
| `Uni/Total`（英文 defaultValue） | 中文本地化「单侧/合计」 | 补 zh-Hans 串 |
| `Copy` | 「复制」 | 补 zh-Hans 串 |
| `Done` | 「完成」 | 补 zh-Hans 串 |

### 层级修复（视觉三档）
- **主操作** Done：实心 `primary` + `onPrimary`，最重
- **推荐值** preset reps：`primarySubtle` 底 + `primaryText`，品牌色弱提示（暗示"点这个填默认值"）
- **结构操作** 功能键：`inner` 底 + `text2`，中性最轻

### 布局修复（窄屏）
- 侧栏 `maxWidth: 84 → 72`，给中间数字键让位
- 数字键 `minHeight: 48 → 52`（更接近拇指区，仍 ≤ 键盘总高约束 240/260pt）
- 保持三列（符合肌肉记忆），但中间列加 `layoutPriority(1)` 防压缩

### a11y / 触达
- 数字键 `minHeight 52` + 间距 8pt：满足 44pt + 呼吸间距
- Done/preset/功能键保持 `minHeight: 44`
- Reduce Motion：键盘无入场动画，无需处理（触觉反馈保留，不受 Reduce Motion 影响）

---

## 按 layer 拆分（VitalStride AGENTS.md layer map）

改动落 **app target**（`VitalStride/Sources/`，不属任何 SPM layer）——`WorkoutNumericKeyboard.swift`、`NumericKeypad.swift` 都在 app target。DesignKit token 只读、不改。门禁走 pre-push 全量 xcodebuild + 现有键盘测试。

**建议拆 3 个 task**（按依赖）：
- **T1（前置，P0）**: 架构修复 A —— inputView host 注入 theme + colorScheme 搭桥 + traitCollection 刷新
- **T2（P0，依赖 T1）**: NumericKeypad 数字键 `.foregroundStyle(text1)` + 全键盘配色换 DesignKit token（对比度修复）
- **T3（P1，可并行 T2）**: i18n（SF Symbol + 中文本地化串）+ 层级（三档视觉）+ 窄屏布局

**验证**: pre-push 全量 xcodebuild；真机 `deploy-to-phone.sh 陪陪` 目视深/浅色两态；VoiceOver 走查数字键可读。
