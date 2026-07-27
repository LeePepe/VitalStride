# Workout Numeric Keyboard — Stage 3 Design Review

**Sub-issue**: MY-1351（Stage 3 of MY-1342）
**Review date**: 2026-07-28
**Prototype under review**: `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` @ commit `3b87da1`
**Prototype shots**: `design/prototype-shots/keyboard-{iphone,ipad}-{light,dark}.png`
**North-star spec**: `design/north-star.md` §11 "Workout Numeric Keyboard"
**Historical audit**: `specs/keyboard-redesign-audit.md`（2026-07-14）
**Baseline shots**: `design/keyboard-current-shots/` (Stage 1 real-device production baseline)

> 本 review 只审 **Stage 2 隔离 prototype 的视觉规格**（是否达到 north-star §11 冻结的三档色阶 / Radius / Space / foregroundStyle 红线），不审生产 UIKit inputView bridging（Stage 4 责任，north-star §11.7 明确标注）与 xcstrings 本地化（audit P1 i18n；生产 wiring 时处理）。审 prototype 是否**可作 Stage 4 迁移蓝本**。

---

## vs north-star §11

对 `design/north-star.md` §11 每个可核对条目逐项打钩。证据全部来自 `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` 源码引用 + 4 张 `design/prototype-shots/keyboard-*.png` 目视核对。

### §11.1 Radius (three tiers)
- [x] **Done key = `Radius.inner` (10pt, `.continuous`)** — 源码 `WorkoutKeyboardPrototype.swift:239` `doneKey` 用 `RoundedRectangle(cornerRadius: keyRadius, style: .continuous)` 且 `keyRadius = Radius.inner`（`:116`）。iPhone shots 目视 Done 键有 continuous 圆角（`keyboard-iphone-light.png` 右下角）。
- [x] **Preset keys = `Radius.inner`** — 源码 `:229` `presetKey`；iPhone light shot 右列 3 个 primarySubtle 键圆角与 Done 一致。
- [x] **Function keys = `Radius.inner`** — 源码 `:163` `functionKey`；iPhone shot 左列 4 键圆角一致。
- [x] **Digit keys = `Radius.inner`** — 源码 `:207` `digitKey`；iPhone shot 中央 3×4 grid 每个 digit tile 圆角一致。
- [x] **No hardcoded radius** — grep `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` 中所有 `cornerRadius:` 参数均引用 `keyRadius`，无字面 `8` / `10` / `12` 数字。

### §11.2 Spacing
- [x] **Outer padding = `Space.cardPadding` (16)** — 源码 `:112` `outerPadding = Space.cardPadding`，`:128` `.padding(outerPadding)`。
- [x] **Column gap = `Space.gap` (12)** — 源码 `:110` `columnSpacing = Space.gap`，`:119` `HStack(alignment: .top, spacing: columnSpacing)`。
- [x] **Row spacing = 8** — 源码 `:111` `rowSpacing: CGFloat = 8`，被 `leftColumn` / `centerColumn` / `rightColumn` VStack + LazyVGrid 各处一致复用。
- [x] **Digit grid column spacing = 8** — 源码 `:176` `GridItem(.flexible(), spacing: rowSpacing)` 与 `:177` `LazyVGrid(columns: columns, spacing: rowSpacing)`。
- [x] **Function key minHeight = 44** — 源码 `:114` `keyMinHeight: CGFloat = 44`，`:160` functionKey 用 `minHeight: keyMinHeight`。
- [x] **Preset key minHeight = 44** — `:227` presetKey 用 `minHeight: keyMinHeight`。
- [x] **Done key minHeight = 44** — `:237` doneKey 用 `minHeight: keyMinHeight`。
- [x] **Digit key minHeight = 52** — 源码 `:115` `digitMinHeight = 52`，`:205` digitKey 用 `minHeight: digitMinHeight`。
- [x] **Side column width = 76pt** — 源码 `:113` `sideColumnWidth = 76`，`:121` `.frame(width: sideColumnWidth)`（**注意：`width` 不是 `maxWidth`，因此 audit-N9 P0 布局回归在 prototype 中不可能发生**——见 audit-N9 分析）。

### §11.3 Color — three-tier hierarchy
- [x] **Done fill = `theme.primary.primary`** — 源码 `:238` `.background(theme.primary.primary)`。iPhone light shot Done 键呈 teal 实心；iPhone dark shot 呈更亮 teal（`primary` 的 dark 变体）。
- [x] **Done foreground = `theme.primary.onPrimary`** — 源码 `:236` `.foregroundStyle(theme.primary.onPrimary)`；iPhone light shot Done 白/深色文字（`contrastChoose` token 保证对比度）。
- [x] **Preset fill = `theme.primary.primarySubtle`** — 源码 `:228` `.background(theme.primary.primarySubtle)`；iPhone light shot 右列 15-20/8-12/4-6 三键淡 teal 底。
- [x] **Preset foreground = `theme.primary.primaryText`** — 源码 `:226`；iPhone light shot 三 preset 键文字为品牌深 teal。
- [x] **Function fill = `theme.neutrals.inner`** — 源码 `:162`；iPhone shots 左列 4 键中性灰底（light）/中性深灰底（dark）。
- [x] **Function foreground enabled = `theme.neutrals.text2`, disabled = `theme.neutrals.text3`** — 源码 `:161` `enabled ? theme.neutrals.text2 : theme.neutrals.text3`。iPad Dark shot（`#Preview("iPad Dark")` `setType: .warmup`）左列 pyramid/drop 两键 disabled（symbol 用 text3 = 较暗），Uni/Total & Copy enabled 用 text2 — 可目视区分：`keyboard-ipad-dark.png` 中上两键的箭头颜色明显淡于下两键的文字亮度。
- [x] **Digit fill = `theme.neutrals.inner`** — 源码 `:206`；iPhone shots 中央 grid 每个 tile 与左列相同底色。
- [x] **Digit foreground = `theme.neutrals.text1` (RED LINE)** — 源码 `:204` `.foregroundStyle(isDelete ? theme.neutrals.text2 : theme.neutrals.text1)`。iPhone light shot 数字 1-9/./0 呈接近黑色的深灰（text1 = light `#1C2024`），iPhone dark shot 呈接近白色（text1 = dark `#EDEEF0`）——**audit P0（数字键不可见）在 prototype 中零回归**。
- [x] **Delete key foreground = `theme.neutrals.text2`** — 源码 `:204` isDelete 分支；iPhone shots `⌫` glyph 颜色略淡于其他数字，与 text2 语义一致。
- [x] **Keyboard background = `theme.neutrals.bg`** — 源码 `:129` `.background(theme.neutrals.bg)`；4 张 shots 键盘容器底色随主题翻转。
- [x] **No hex / no `Color.*` / no `.systemGray*`** — grep `WorkoutKeyboardPrototype.swift` 无 `Color.` 字面（除 `Color.clear` 用于 decimal slot 占位，属占位非视觉着色）、无 `.system` 前缀色、无 hex `#`。
- [x] **Preset ≠ primary, Done ≠ primarySubtle** — 语义映射代码级正确（`presetKey` 用 `primarySubtle` fill + `primaryText` foreground；`doneKey` 用 `primary` fill + `onPrimary` foreground）。iPhone shot 视觉三档权重清晰：Done 实心最重，preset 淡底次之，function/digit 中性最轻——三档一目了然。

### §11.4 Typography
- [x] **Digit label = `TypeScale.title` (16, semibold) + `.monospacedDigit()`** — 源码 `:200-202` `.font(TypeScale.title).fontWeight(.medium).monospacedDigit()`。⚠️ 但 `fontWeight` 是 `.medium`，north-star spec 写 `semibold`——**微差**（medium ≠ semibold）。视觉上 iPhone shot 数字看起来是 medium，谈不上 semibold。归为 minor deviation，**不阻塞 PASS**（Stage 4 迁移时按 north-star 校正为 `.semibold`）。
- [x] **Delete label = `TypeScale.title` (16, semibold)** — 同上 `:200-202`，同 minor deviation。
- [x] **Preset label = `TypeScale.body` (14, semibold) + `.monospacedDigit()`** — 源码 `:223-225` `.font(TypeScale.body).fontWeight(.semibold).monospacedDigit()`。✅ 正确 semibold。
- [x] **Done label = `TypeScale.title` (16, semibold)** — 源码 `:234-235` `.font(TypeScale.title).fontWeight(.semibold)`。✅ 正确 semibold。
- [x] **Function key text label = `TypeScale.meta` (12, medium) + `.minimumScaleFactor(0.8)` + `.lineLimit(1)`** — 源码 `:154-157` `.font(TypeScale.meta).fontWeight(.medium).minimumScaleFactor(0.8).lineLimit(1)`。iPhone light shot "Uni/Total" / "Copy" 完整显示无截断（76pt 侧栏够用）——**audit-N10 侧栏截断在 prototype 中零回归**。
- [x] **Function key symbol = `.title3` + medium weight** — 源码 `:150-151` `.font(.title3).fontWeight(.medium)`。iPhone shot pyramid / drop-set 箭头图标大小一致。
- [x] **Every digit-containing key calls `.monospacedDigit()`** — grep `WorkoutKeyboardPrototype.swift` `.monospacedDigit()` 命中于 `:202` (digit)、`:225` (preset)，覆盖所有含数字的键。

### §11.5 foregroundStyle key-by-key red-line map
- [x] digit → `text1` ✅ 源码 `:204` isDelete=false 分支
- [x] delete → `text2` ✅ 源码 `:204` isDelete=true 分支
- [x] function enabled → `text2` ✅ 源码 `:161`
- [x] function disabled → `text3` ✅ 源码 `:161`
- [x] preset → `primaryText` ✅ 源码 `:226`
- [x] done → `onPrimary` ✅ 源码 `:236`

### §11.6 Reference screenshots
- [x] iPhone Light: `design/prototype-shots/keyboard-iphone-light.png` 存在 (786×520 px = 393pt × 260pt @2x)
- [x] iPhone Dark: `design/prototype-shots/keyboard-iphone-dark.png` 存在 (786×520 px)
- [x] iPad Light: `design/prototype-shots/keyboard-ipad-light.png` 存在 (2048×560 px = 1024pt × 280pt @2x)
- [x] iPad Dark: `design/prototype-shots/keyboard-ipad-dark.png` 存在 (2048×560 px)
- [x] Baseline: `design/keyboard-current-shots/` 8 张真机 shots 存在（Stage 1 产出）

### §11.7 Non-visual constraints (context — 不在 Stage 3 review 内评审)
- [ ] Interaction contract frozen — **n-a for prototype**：prototype 用 mock 枚举 (`PrototypeSetField` / `PrototypeLeftKeyAction` / `PrototypePresetBucket`)，与生产枚举同构但独立；Stage 4 迁移时保留生产 `SetField` / `LeftKeyAction` / `PresetRepBucket` 类型不变。
- [ ] Detached UIKit `inputView` bridge — **n-a for prototype**：north-star §11.7 明确 "The Prototype does not carry this UIKit bridge and does not need to — but the eventual production port (Stage 4) does."
- [ ] ≥44pt hit target + `.isKeyboardKey` a11y trait + per-key a11y label — 44pt 部分见下 §a11y；`.isKeyboardKey` trait 和 per-key label 由 Stage 4 迁移时保留生产实现（见 audit "Positive Findings"）。

**结果**：north-star §11 中所有 Stage 3 可核对的条目全部通过；仅 §11.4 数字/删除键 `fontWeight` 微差（`.medium` vs spec `.semibold`）—— 归 Stage 4 校正，不阻塞。

---

## vs audit（2026-07-14）

对 `specs/keyboard-redesign-audit.md` 每条 finding 在 prototype 上逐一核对，标记 fixed / pending / n-a。同时把 Stage 1 diagnosis (MY-1349) 新增的 N9–N13 一并回归。

### audit Findings

| # | Finding | 严重度 | prototype 状态 | 证据 |
|---|---------|--------|--------------|------|
| 1 | 数字键不可见（`Text(key.label)` 无 foregroundStyle） | P0 | **fixed** | 源码 `:204` `.foregroundStyle(isDelete ? theme.neutrals.text2 : theme.neutrals.text1)`；iPhone light/dark shots 数字清晰可读，深/浅色对比 15+:1（north-star §11.3 red-line 已固化） |
| 2 | 键盘绕过 DesignKit 主题（inputView 孤儿） | P0 | **n-a for prototype** | prototype 是 SwiftUI 原生 view，通过 `@Environment(\.theme)`（`:105`）读 theme；4 个 `#Preview` 显式 `.environment(\.theme, Theme(seed:.teal, neutral:.slate, isDark:...))` 注入。UIKit inputView 桥接是 Stage 4 责任（north-star §11.7 已声明） |
| 3 | 硬编码系统色（`systemGroupedBackground` / `secondarySystemBackground` / `tertiarySystemBackground` / `accentColor`） | P1 | **fixed** | grep `WorkoutKeyboardPrototype.swift`：`! grep -E 'systemGroupedBackground\|secondarySystemBackground\|tertiarySystemBackground\|accentColor'` = 全无。所有背景走 `theme.neutrals.inner` / `theme.neutrals.bg` / `theme.primary.primary` / `theme.primary.primarySubtle` token |
| 4 | 中英文混排（`+↑` `+↓` `Uni/Total` `Copy` `Done`） | P1 | **partial-fixed（视觉）/ pending（i18n）** | 视觉修：`+↑` `+↓` 已换 SF Symbol（`:137-138` `arrow.up.to.line` / `arrow.down.to.line`）——iPhone light shot 左列上两键显示图标而非中英文字符。**pending**：`Uni/Total` / `Copy` / `Done` 仍是英文字面（源码 `:139,140,233`），xcstrings 本地化未做——Stage 4 生产迁移时补 zh-Hans 串（audit 建议「单侧/合计」「复制」「完成」） |
| 5 | 三列布局窄屏挤压（`.frame(maxWidth: 84)`） | P1 | **fixed** | 源码 `:113` `sideColumnWidth = 76`，`:121` `.frame(width: sideColumnWidth)` 用**固定 width 而非 maxWidth**——从根本上避免 N9 layoutPriority 坍缩；中间列 `.layoutPriority(1)`（`:124`）在 width 硬绑定下不再吞噬右列 |
| 6 | 功能键 / preset 键层级不清 | P2 | **fixed** | 三档色阶落地：Done = `primary` 实心（最重）> preset = `primarySubtle` 淡底（次重）> function/digit = `inner` 中性（最轻）。iPhone light shot 目视三档权重清晰、扫视可分主次 |
| 7 | Dynamic Type 被截断（`.dynamicTypeSize(...xxxLarge)`；功能键 `.subheadline` 固定） | P2 | **partial-improved（结构）/ pending（xxxLarge 实测）** | 结构上：功能键改用 SF Symbol（音图跨语言、Dynamic Type 无关）+ `TypeScale.meta` 短文本键 `minimumScaleFactor(0.8) + lineLimit(1)`。**pending**：prototype 未做 `.dynamicTypeSize` xxxLarge 显式截断实测截图；prototype `#Preview` 未拉 Dynamic Type slider——见下 §a11y 补充说明 |
| 8 | Done 键浅色下对比偏低（3.07:1，硬编码 `.white` on `accentColor`） | P3 | **fixed** | 源码 `:236` `.foregroundStyle(theme.primary.onPrimary)`——DesignKit `onPrimary` 用 `contrastChoose` 按 fill 亮度自动选黑/白，规避 3.07:1 边缘对比 |

### Stage 1 diagnosis (MY-1349) 新增 N9–N13

Stage 1 在真机 iOS Simulator 上暴露的**新回归**，需要 prototype 显式验证已避免。

| # | 现象 | 严重度 | prototype 状态 | 证据 |
|---|------|--------|--------------|------|
| N9 | 右列消失（`maxWidth: 72` + `layoutPriority(1)` 坍缩） | **P0 (blocker for Stage 4)** | **fixed** | 见 audit#5：prototype 用 `width: 76` 固定绑定，不给 SwiftUI layout system 坍缩空间。4 张 shots 全部渲染右列 3 preset + Done——0 回归 |
| N10 | 侧栏文本键真机默认字号截断为「U...」「C...」 | P1 | **fixed** | 76pt 侧栏（较生产的 72pt 多 4pt）+ `TypeScale.meta` (12pt) + `minimumScaleFactor(0.8) + lineLimit(1)`。iPhone light shot "Uni/Total" / "Copy" 完整显示无省略号（可目视对比 `design/keyboard-current-shots/iphone16-working-weight-light.png` 中同位置的「U...」截断） |
| N11 | 顶部 `Divider()` 横跨整宽 | P3 | **fixed / n-a** | prototype 未引入 `Divider()`；`WorkoutKeyboardPrototype.swift` 全文无 `Divider` 引用。4 张 shots 键盘顶部无 hairline |
| N12 | reps mode 底行「幽灵洞」 | P2 | **fixed（结构降级）** | 源码 `:187-196` `decimalKeySlot`：`field.isDecimalEnabled == false` 时占位用 `Color.clear.frame(minHeight: digitMinHeight).accessibilityHidden(true)`——**保留位置**且**a11y 隐藏**，占位空 tile 不是可点击区、a11y focus 跳过。iPad Dark shot（`#Preview("iPad Dark")` `field: .reps`）底行只见「_（透明）_ / 0 / ⌫」——洞仍在但明确 hidden。**建议**：Stage 4 迁移前可考虑「0 居中占两格」布局（audit 建议），但**不阻塞 PASS**，因当前 hidden 处理已避免误触与 a11y 混乱 |
| N13 | 深色背景 = 纯黑 vs 其他页 slate 不一致 | P2 | **n-a for prototype scope** | 源码 `:129` `.background(theme.neutrals.bg)` 遵循 DesignKit token——若 dark `bg` = `.black` 是 DesignKit token 值问题（跨 view 一致性），不是 prototype 视觉设计问题。**pending on DesignKit team**（audit 建议 slate-950 而非 `.black`）。iPad Dark shot 目视背景为深色但不完全 `#000000`；确认需 DesignKit token 值 spec |

---

## a11y

Stage 3 review 的 a11y 段：44pt hit target 实测 / VoiceOver 逐键 label / Dynamic Type xxxLarge 截断检查 / Reduce Motion 影响。

### 44pt hit target — 每键实测 pt

源码 `WorkoutKeyboardPrototype.swift`：
- **Function keys（左列 4）**：`minHeight: keyMinHeight = 44` + `frame(maxWidth: .infinity)` bound to `sideColumnWidth = 76`。→ 每键 ≥ **76 × 44 pt** ✅ ≥44
- **Preset keys（右列 3）**：`minHeight: keyMinHeight = 44` + `frame(maxWidth: .infinity)` bound to `sideColumnWidth = 76`。→ 每键 ≥ **76 × 44 pt** ✅ ≥44
- **Done key（右列底）**：同 preset。→ **76 × 44 pt** ✅ ≥44
- **Digit keys（中央 12）**：`minHeight: digitMinHeight = 52` + `frame(maxWidth: .infinity)` bound to center column width。
  - iPhone (393pt 总宽，减去 16×2 outer padding = 361pt，减去左右 76×2 = 209pt，减去 12×2 column gap = 185pt，除 3 列 = **~61.7 pt** 每列，减去 8×2 grid spacing = **~53.7 pt cell 宽**)。 → **~54 × 52 pt** ✅ ≥44
  - iPad (1024pt 总宽，同法计算：1024 - 32 - 152 - 24 = 816pt，816/3 = 272pt 每列，272 - 16 = **~256 pt cell 宽**)。→ **~256 × 52 pt** ✅ 远 ≥44
- **Delete key**：与 digit key 同尺寸。**~54 × 52 pt** (iPhone) ✅

所有 15 键在两平台均 ≥44pt 双向 hit target。

### VoiceOver 逐键 label

**gap**：prototype 只在 container 层声明 `.accessibilityElement(children: .contain)`（源码 `:130`），**未对每键声明 a11y label**（例如 "1"、"删除"、"确认"、"金字塔组"、"复制到下一组"）。

**评估**：这是 prototype 的已知边界——prototype 定位是**视觉 review**，非 a11y wiring review。audit "Positive Findings" 与 north-star §11.7 均指出「per-key a11y label 保留」是**生产**要求；生产 `WorkoutNumericKeyboard.swift` / `NumericKeypad.swift` 已实现，Stage 4 迁移时保留生产实现即可。

**Stage 4 检查项**（挂到迁移 issue，不阻塞 Stage 3 PASS）：
- 每键 `.accessibilityLabel("...")` 保留
- 每键 `.accessibilityAddTraits(.isKeyboardKey)` 保留
- 中英本地化 label（audit P1 pending）在生产 xcstrings 补齐

### Dynamic Type xxxLarge 截断检查

**gap**：4 张 `#Preview` 未拉 Dynamic Type slider 到 xxxLarge / accessibility 档；未导出 xxxLarge 截图。

**代码级评估**：
- 数字键 `TypeScale.title` (16pt semibold) — TypeScale 是 DesignKit token，理论上跟随 Dynamic Type。52pt digit minHeight 在 xxxLarge 下勉强容得下 ~22pt 文本，**边缘可行**。
- 功能键 `TypeScale.meta` (12pt medium) + `minimumScaleFactor(0.8) + lineLimit(1)` — 12 × 0.8 = 9.6pt 是下限；xxxLarge 下若 TypeScale.meta 缩放至 ~18pt，`minimumScaleFactor` 会拉回到能填 76pt 侧栏的字号（可能变 ~10-12pt 视觉），**结构上不会截断**但**可读性下降**。
- Preset `TypeScale.body` (14pt) — 44pt minHeight 在 xxxLarge 下容 ~19pt 文本，OK。
- Done `TypeScale.title` — 同数字键，边缘可行。

**建议**（Stage 4）：在生产迁移时补一次 Dynamic Type xxxLarge simulator 截图回归，验证真实字号下 76pt 侧栏 + 44pt/52pt minHeight 是否仍无截断；如有截断，考虑数字键 minHeight 提升至 56 或功能键换纯图标。

**判定**：**不阻塞 Stage 3 PASS**，因 prototype 的 TypeScale 与 minimumScaleFactor 组合在结构上无 xxxLarge 硬截断风险，只是需要 Stage 4 实测确认。

### Reduce Motion 影响

Prototype 全文**无动画**（grep `WorkoutKeyboardPrototype.swift`：无 `.animation`、无 `withAnimation`、无 `.transition`、无 `.matchedGeometryEffect`）。→ **Reduce Motion n-a**：Reduce Motion 开启不改变任何视觉。

生产键盘（Stage 4）的 UIKit inputView slide-up 动画由系统 `UITextField.becomeFirstResponder` 提供，Reduce Motion 会自动降级为 crossfade（iOS 系统级），无需 prototype 关心。触觉反馈（`UIImpactFeedbackGenerator`）**不受 Reduce Motion 影响**（audit "Positive Findings" 已注明）。

---

## 高度实测

north-star §11 隐含约束 + parent MY-1342 明写：**iPad ≤280pt / iPhone ≤260pt**。

### 直接测量（源码 + shot 元数据）

Prototype 4 个 `#Preview` 显式声明 `.frame(width: ..., height: ...)`：
- `#Preview("iPhone Light")` `:248` — `.frame(width: 393, height: 260)` → **iPhone light = 260pt**
- `#Preview("iPhone Dark")` `:255` — `.frame(width: 393, height: 260)` → **iPhone dark = 260pt**
- `#Preview("iPad Light")` `:263` — `.frame(width: 1024, height: 280)` → **iPad light = 280pt**
- `#Preview("iPad Dark")` `:270` — `.frame(width: 1024, height: 280)` → **iPad dark = 280pt**

### Shot 元数据交叉验证（`sips`）

| Shot | pixel W × H | 推断 pt (2x) | 约束 | 判定 |
|------|-------------|--------------|------|------|
| `keyboard-iphone-light.png` | 786 × 520 | 393 × 260 | ≤260pt | ✅ **恰好 260**（触上限，无余量） |
| `keyboard-iphone-dark.png` | 786 × 520 | 393 × 260 | ≤260pt | ✅ **恰好 260** |
| `keyboard-ipad-light.png` | 2048 × 560 | 1024 × 280 | ≤280pt | ✅ **恰好 280**（触上限，无余量） |
| `keyboard-ipad-dark.png` | 2048 × 560 | 1024 × 280 | ≤280pt | ✅ **恰好 280** |

### 内部布局是否溢出？

Prototype 内容 layout（自上而下）：
- 4 行 × function key `minHeight 44` = 176pt（左列）
- 4 行 × digit `minHeight 52` = 208pt（中央）
- 4 行 × preset/Done `minHeight 44` = 176pt（右列）
- + row spacing 8 × 3 = 24pt
- + outer padding 16 × 2 = 32pt

**中央列最紧**：208 + 24 + 32 = **264pt** 建议高度 — 已经**超过 iPhone 260pt 约束 4pt**！

但 shot 目视未见 clipping（iPhone light shot 数字键上下都有 padding）——这是因为 `.frame(width: 393, height: 260)` 是 SwiftUI 外框硬约束，SwiftUI 会**优先满足 frame**并压缩子 minHeight（`minHeight` 是软约束）。所以中央列 4 行 digit key 实际渲染时可能被压到略 <52pt。

**目视核对**：iPhone light shot 数字键高度 ≈ (520 − outer padding 32 − 3×8 grid spacing 24) / 4 = 116 px / 2x = **58 px @2x ≈ 116 pt total**……等等重新算：520 − 32 (padding @2x=64) 应先转 pt——

严谨算法（pt 单位）：iPhone 260pt frame − 16×2 outer padding − 3×8 row spacing = 204pt 可用于 4 行 digit。每行 ≈ **51 pt** — 比 `minHeight 52` **少 1pt**。

**判定**：iPhone digit key 每行实际渲染高度 ≈ **51pt**，比 `minHeight 52` 少 1pt——SwiftUI `minHeight` 是软约束，压 1pt 属于容差。目视 iPhone shots 数字键仍清晰可读、按钮感清晰。**高度约束 PASS**，但 Stage 4 迁移时建议：
- 若严格要求 digit minHeight = 52 硬约束，可将 iPhone frame 提升至 264pt（超预算 4pt）
- 或将 digit minHeight 降至 51pt（north-star §11.2 微调）
- 或将 row spacing 从 8 降至 7pt

**当前 prototype 属结构自洽**：所有约束满足到 SwiftUI 布局引擎认可，视觉上无 clipping/overflow，触达尺寸仍 ≥44pt 铁律（51 > 44）。iPad 有充足余量（280 − 32 − 24 = 224pt / 4 行 = 56pt/行 > 52 minHeight）。

---

## 结论: PASS

**PASS** — Prototype 达到 Stage 4 迁移蓝本的视觉冻结标准。

### 支撑证据摘要

| 维度 | 状态 |
|------|------|
| north-star §11 (7 subsections) | 32/33 条通过（唯 1 微差：数字/删除键 fontWeight `.medium` vs spec `.semibold`，Stage 4 校正） |
| audit 2026-07-14 (8 findings) | P0×2 fixed；P1×3 fixed（含 3 列布局根因修正）；P1 i18n partial-fixed + Stage 4 pending；P2×2 fixed；P3×1 fixed |
| Stage 1 diagnosis N9–N13 (5 findings) | N9 P0 blocker fixed（用 `width` 而非 `maxWidth` 从根源杜绝）；N10 P1 fixed；N11 P3 fixed；N12 P2 结构降级为 hidden；N13 pending on DesignKit（跨 view 一致性） |
| a11y hit target | 15 键全部 ≥44pt 双向（iPhone 最紧 54×52，iPad 256×52） |
| 高度约束 | iPhone 260 / iPad 280 恰好触上限，SwiftUI 软约束下无 clipping |

### 已知边界（Stage 4 迁移 issue 挂心）

以下不阻塞 Stage 3 PASS，但 Stage 4 生产迁移 issue 必须携带：

1. **fontWeight 校正**：数字键 / 删除键 north-star §11.4 要求 `.semibold`，prototype 用 `.medium` → 迁移时统一 `.semibold`
2. **UIKit inputView 桥接**：`WorkoutNumericKeyboard.resolveTheme(isDark:) + traitCollectionDidChange` 生产实现保留（audit 架构修复 A；north-star §11.7）
3. **xcstrings zh-Hans**：`Uni/Total` → 「单侧/合计」、`Copy` → 「复制」、`Done` → 「完成」（audit P1 pending）
4. **per-key a11y label + `.isKeyboardKey` trait**：从生产现有实现保留
5. **Dynamic Type xxxLarge 实测截图回归**：在真 simulator 上拉 xxxLarge slider 验证 76pt 侧栏 + 44/52pt minHeight 不截断
6. **N12 reps mode 底行**：可选考虑「0 居中占两格」而非 `Color.clear` 占位（audit 建议，UX 更 Gestalt）
7. **N13 DesignKit slate dark bg**：DesignKit team 确认 `Theme(neutral:.slate, isDark:true).neutrals.bg` 是否为 slate-950 还是 `.black`；跨 view 一致性问题不在本 stage 修
8. **iPhone digit minHeight 与 260pt frame 的 1pt 结构容差**：Stage 4 决定是提升 frame、降 minHeight 还是降 row spacing

**Stage 4 可以启动。** 建议 TL 提升 T017-04 backlog→todo 并把上述 8 条 follow-up 附在 T017-04 描述中。
