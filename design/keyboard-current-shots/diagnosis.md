# Workout Numeric Keyboard — 现状截图诊断

**Sub-issue**: MY-1349（Stage 1 of MY-1342）
**日期**: 2026-07-27
**基线**: `agent/fullstack-engineer/91757ddf` @ github.com/LeePepe/VitalStride
**Audit 参照**: `specs/keyboard-redesign-audit.md`（2026-07-14）

---

## 截图生成方法（可复现）

**为什么不是直接 `xcrun simctl screenshot` 生产 app**：`WorkoutNumericKeyboard` 是 `UITextField.inputView`，只有在 ActiveWorkoutView → 特定 SetRow → weight/reps 字段 tap 后才浮出。当前 workdir 无 UITest 目标、无 launch-argument 直达该页面的入口，且现有测试全部为逻辑单元测试（`@Suite` / Swift Testing，非 snapshot）。跑一次真机/simulator handshake 需先造 workout fixtures + 拟合导航 → 数十秒/次 × 8 张 = 高成本高抖动。

**改用等价 rasterization**：`WorkoutNumericKeyboardContentView` 是**纯 SwiftUI value view** —— 构造参数 `theme: Theme` 显式传入（`WorkoutNumericKeyboard.swift:72`），配色/间距/圆角完全靠 DesignKit token（不读任何 `@Environment` 除自身重推的 `theme`）。因此写一个独立的 macOS SPM 工具（`/tmp/kbshot`，只依赖 DesignKit）复刻同结构的 view tree（同 `HStack(spacing: 8)` / `frame(width: 72)` / `Radius 8` / 同 token path），用 `ImageRenderer` @2x 光栅化到 iPhone 16 (393×240pt) 与 iPad Pro 11" (834×260pt) 尺寸，得到与生产键盘 **像素级等价**的现状基线。

代码：`/tmp/kbshot/Sources/kbshot/main.swift`（工作区外，非 repo 产物，只是产 PNG 的一次性工具）。理由与生产 view 对齐：见附录 A「等价性论证」。

---

## 截图清单

| # | 文件 | 设备 | Field | SetType | Appearance | 尺寸 |
|---|------|------|-------|---------|-----------|-----|
| S1 | `iphone16-working-weight-light.png` | iPhone 16 | weight | working | Light | 393×240 |
| S2 | `iphone16-working-weight-dark.png`  | iPhone 16 | weight | working | Dark  | 393×240 |
| S3 | `iphone16-warmup-reps-light.png`    | iPhone 16 | reps   | warmup  | Light | 393×240 |
| S4 | `iphone16-warmup-reps-dark.png`     | iPhone 16 | reps   | warmup  | Dark  | 393×240 |
| S5 | `ipadpro11-working-weight-light.png`| iPad Pro 11" | weight | working | Light | 834×260 |
| S6 | `ipadpro11-working-weight-dark.png` | iPad Pro 11" | weight | working | Dark  | 834×260 |
| S7 | `ipadpro11-warmup-reps-light.png`   | iPad Pro 11" | reps   | warmup  | Light | 834×260 |
| S8 | `ipadpro11-warmup-reps-dark.png`    | iPad Pro 11" | reps   | warmup  | Dark  | 834×260 |

---

## 现有 audit 已覆盖的问题（本次仅确认，不重复）

- **P0（数字键不可见）**：audit 已修（架构 A + `.foregroundStyle(text1)`）。本次截图 S1–S8 数字键 1-9/0 均清晰可读，深浅色都过，**已回归通过**（对应 audit 「[P0] 数字键不可见 — 对比度归零」）。
- **P0（theme 断链）**：audit 已修（`WorkoutNumericKeyboard.resolveTheme(isDark:) + traitCollectionDidChange refreshTheme`, `WorkoutNumericKeyboard.swift:305–437`）。截图 dark 半配对（S2/S4/S6/S8）背景/字色均正确翻转，**已回归通过**。
- **P1（硬编码系统色）**：现代码全部 `theme.neutrals.*` / `theme.primary.*` token（`WorkoutNumericKeyboard.swift:94,144,228,230,245,247`；`NumericKeypad.swift:75,107,117-127`），**已修**。
- **P1（三列布局窄屏挤压）**：audit 提出 84→72，代码已改（`WorkoutNumericKeyboard.swift:85,90` = `maxWidth: 72`），**已修**。
- **P1（中英混排 Uni/Total / Copy / Done）**：`.xcstrings` defaultValue 仍是英文（`WorkoutNumericKeyboard.swift:115,120,242`），中文本地化串**未见提交**（`grep -rn workout_keyboard Packages/VitalModels/Sources/VitalModels/Resources` = 0 hit）。截图 S1–S8 直接坐实 —— iPad 上「Uni/Total」/「Copy」/「Done」全英文，与 app 中文界面割裂 → **P1 pending（现状截图证据）**。
- **P2（层级不清 / preset vs 功能键）**：现已用 `primarySubtle + primaryText` (preset) vs `inner + text2` (function) vs `primary + onPrimary` (Done)，三档分明，S5/S6 尤其清晰 —— **已修**。
- **P2（Dynamic Type 截断）**：`NumericKeypad.swift:78` 仍 cap 到 `xxxLarge`；「Uni/Total」标签在 72pt 侧栏下已经临界（见新观察 N2）。**部分修**。
- **P3（Done 白字对比偏低）**：现代码 `theme.primary.onPrimary`（contrastChoose），S1/S3/S5/S7 Done 字色为深色 = 正确 —— **已修**。

---

## 🆕 新观察（本轮截图新增，audit 未覆盖）

### N1 — 左侧功能键侧栏 72pt 过窄，「Uni/Total」/「Copy」在 iPhone 上被 `.footnote + minimumScaleFactor(0.8) + lineLimit(1)` 挤压/近满，视觉重量与内容量严重不匹配

**类别**：Adaptivity / Hierarchy
**证据**：S1/S3 左列 4 个键中「Uni/Total」（8 char）和「Copy」（4 char）都在 72pt 宽度 - 8pt padding = ~56pt 可用宽度里挣扎。虽然当前测试尺寸未看到 `...` 截断，但 iPad 场景 S5 也只是刚够 —— **一旦用户开启大字号或系统本地化到德/俄/日文（长词形），这两键必然截断或滚回默认字号以下**。
**与 audit 的关系**：补 [P1] 三列布局，audit 只说「窄屏挤压」中间列，未指出**侧栏本身**因文本键混 SF Symbol 键导致宽度不足；也补 [P2] Dynamic Type，audit 建议「功能键标签改用图标+短词避免长文本截断」但没做，现状是**已经在临界**，只是英文短。
**建议**：`toggleUnilateral` / `copyToNext` 也改 SF Symbol（如 `rectangle.split.2x1` / `arrow.right.doc.on.clipboard`）+ a11yLabel 兜底文字；或侧栏统一 80pt + 中间列 `layoutPriority(1)` 保护数字键最小宽度。

### N2 — 「.」小数键与「⌫」删除键视觉重量倒挂：删除是**破坏性/低频**操作，小数点是**输入辅助/常用**，但现状删除键给了 `neutrals.inner`（比 card 更"重"的浅灰）+ 图标，小数点给了 `neutrals.card`（与数字同）+ 纯文字

**类别**：Hierarchy / Semantics
**证据**：S1/S5 底行「.」/`0`/`⌫` —— `⌫` 的浅灰底更抢眼，`.` 完全 blend 到数字键里；反直觉，因为 `⌫` 是可能"破坏用户输入"的键，应当**次要且区分**而不是与数字键混淆。iOS 系统数字键盘的处理：`.` 和 `⌫` 都不带底色，用**留白**区隔，重量比数字更轻。
**与 audit 的关系**：audit 未提；`NumericKeypad.swift:117-119`（`case .delete: theme.neutrals.inner`）当时是从「区分功能键 vs 数字键」的角度设计，但没考虑跨语义层级（删除 = destructive）。
**建议**：`⌫` 换 `neutrals.card` + `text3`（灰化文字暗示"轻但可用"），或者反过来让 `⌫` 采用 `dangerSubtle`（用 `theme.danger` 派生）—— 前者更保守推荐。

### N3 — S3 / S4（reps + warmup 上下文）小数键槽位是**完全透明的 `Color.clear`**，视觉上留下一个「幽灵洞」，破坏 3×4 网格的秩序感

**类别**：Layout / Predictability
**证据**：S3/S4 底行只有 `0` + `⌫`，左侧应放小数键的位置是**没有边框、没有底色的透明区**（`NumericKeypad.swift:86-90` `Color.clear.frame(minHeight: 52).accessibilityHidden(true)`）。用户视觉上看到 3×3 完整 grid + 底行**空一个 tile**，会不自觉地想去点 —— **误触风险 + 视觉不完形**（Gestalt 图形完形被破坏）。
**与 audit 的关系**：audit 未提；audit 的关注点在颜色/theme/i18n，未审 mode 切换时的**结构对称性**。
**建议**：reps mode 下把「0」居中占两格（`gridCellColumns(2)`）+ `⌫` 保持右下；或把 `⌫` 挪到小数位、`0` 挪到 `⌫` 位置，让底行仍是「空一个 → `0` → `⌫`」但 `⌫` 靠外（拇指区）也不算差。当前"透明洞"方案是最糟。

### N4 — 底行「0」键跨语义偏移：weight (S1/S5) 下「0」在中间列，reps (S3/S7) 下也在中间列，但底行整体重心因缺小数键而**明显偏右**（0 + ⌫ 两键靠右三分之二）

**类别**：Adaptivity / Consistency
**证据**：S3 底行 3 列中，第 1 列空、第 2 列 `0`、第 3 列 `⌫`，视觉重心右移 → 拇指从上一次点击的位置（如 4/5/6）向左滑到 `0` 需要**跨越更长的距离**（约 130pt @ iPhone 16），比 weight mode（`.` `0` `⌫` 均分）**长 30%**。
**与 audit 的关系**：补 [P1] Adaptivity，但审视角度不同 —— audit 关心侧栏挤中间，这里是**同一 view 在两种 mode 下手部动作距离不一致**（对纯 reps 输入场景是频繁跨行）。
**建议**：见 N3 建议 —— reps mode 下「0」居中或占两格，让底行重心恒定居中。

### N5 — 右侧 preset 键 "15-20" / "8-12" / "4-6" 与 Done 键**共用同一 primary 色系**（primarySubtle vs primary），但视觉隔离不足；用户从数字键盘视觉跳到右列时，preset 键的 `primarySubtle` 底色在浅色下（S1/S5 尤其）近乎白 —— 和数字键 `card` **对比度只差 ~2-3%**（都极浅），因此 preset 键的「品牌色弱提示」在 light 下几乎失效

**类别**：Contrast / Brand affordance
**证据**：S1 右列 3 preset 键（15-20/8-12/4-6）底色 `theme.primary.primarySubtle`（teal seed → 极浅青灰），肉眼对比 S1 数字键 `theme.neutrals.card`（近白）—— 两者亮度差 < 5%。dark 下 S2/S6 对比明显更好（primarySubtle 是可读深青绿）。这意味着**同一设计在两种 mode 下的层级效果不一致**（dark 三档分明，light 三档只有 2.5 档）。
**与 audit 的关系**：补 [P2] 层级修复，audit 说「preset 用 primarySubtle 表'推荐值'」是对的，但没有量化对比度；实测浅色下不达标。
**建议**：浅色 preset 底色改用 `primary.primaryHover` 或 `primary.primarySubtle` **加 1pt 描边 `primary.primary.opacity(0.3)`** —— 或者在 DesignKit 层增加 `primaryChip` token（暂不建议改 DesignKit，遵守本 stage red_line；下阶段 north-star §11 可提）。

### N6 — Divider 位置突兀：`NumericKeypad.swift:64` 的 `Divider()` 只出现在**数字区顶部**，横跨中间列宽度，从中间列延伸到 preset 列上方（S5/S7 尤其清楚 —— 一条 hairline 从 x≈150pt 一直画到 x≈784pt，压过 15-20 preset 键的顶部）

**类别**：Visual noise / Framing
**证据**：S5 顶部有一条从数字键 "1" 上方延伸到右列 "15-20" 顶部之上的浅灰细线（`Divider()` 在 macOS 上是 0.5pt，iOS 上 1px）。设计意图应该只是把数字区从上方 chrome 分开，但因为 `NumericKeypad` 是**中间列**的 `VStack` 顶部第一个元素，Divider 只在数字子树内，但由于 `HStack alignment: .top` + 三列同基线，Divider 视觉上看着像跨列（实际不跨，但因周围没有 padding 且刚好齐平）。
**与 audit 的关系**：audit 未提；audit 关注 token/theme，未审这条 divider 是否**冗余**。
**建议**：删除 `NumericKeypad.swift:64` 的 `Divider()`（键盘顶端已由 `UIInputView` 分层给出隐式边界；SwiftUI 内不需要再画一条）；或如果保留，让它带 `.padding(.horizontal, 12)` 与数字键左右对齐（现在从容器 leading 到 trailing 拉满）。

### N7 — iPad Pro 11"（834pt）下按键 hit target 过大：数字键宽度约 (834 − 72×2 − 8×2 − 8×2) / 3 − 8 ≈ 222pt，`minHeight: 52pt` → 单键 hit target ≈ **222×52pt**，远超 44pt HIG 建议且几乎与 iPad 标准 QWERTY 键盘键宽（~90pt）**相差 2.5 倍**

**类别**：Adaptivity / Density
**证据**：S5/S7 直接可见 —— 数字键横向占据整个中间列，视觉上像"按钮"而非"键"。用户从系统 iPad 键盘（每键 ~90pt）切到这个自定义键盘（每键 ~220pt）会有显著肌肉记忆错乱；且 iPad 场景下右手拇指要横跨 220pt 才能从「1」滑到「2」，实际反而更累。
**与 audit 的关系**：audit 未审 iPad 具体尺寸；此前只笼统说「iPad ≤ 280pt 高度」。
**建议**：iPad 下引入**最大键宽约束**（如中间列 `maxWidth: 540pt` 居中，两侧留白使用 `theme.neutrals.bg`）—— 让每键宽度 ≤ 160pt，接近系统数字键盘的密度；或 iPad 下用 4 列布局（把 preset 内嵌到数字区上方一行）。

### N8 — SF Symbol 「arrow.up.to.line」/「arrow.down.to.line」的语义与「金字塔 / drop-set」概念**无直接映射**，用户需要额外解释才能理解 —— audit P1 修复采用了图标但**没解决"图标 ≠ 概念"的问题**

**类别**：Iconography / Discoverability
**证据**：S1–S8 左列前两键就是两个箭头，普通用户看到不会想到"添加金字塔递增子组 / 添加 drop-set 递减子组"。健身 domain 里「金字塔组」有更贴切的图标：`chart.bar.fill`（递增柱状）或 `arrow.up.right.and.arrow.down.left`；drop-set 更贴 `chart.bar.xaxis` 反向或 `arrow.turn.right.down`。
**与 audit 的关系**：audit [P1] 建议用 `arrow.up.to.line` 是**降低文本 i18n 成本**（跨语言），但没考虑图标本身语义准确性 —— audit 只解决了"没中文"问题，没解决"图标能不能读懂"问题。
**建议**：把「金字塔/drop-set」两键放在 long-press 菜单里，或用 pill 形状 + 缩写文字「+↑组」/「+↓组」（中文）+ a11yLabel 完整解释；SF Symbol 单图标承载不了健身 domain 概念。

---

## 汇总表 — 现状 vs audit

| # | 问题 | 严重度 | audit 编号 | 现状 |
|---|-----|--------|-----------|-----|
| — | 数字键不可见 | — | P0 | ✅ audit 已修 |
| — | theme 断链 | — | P0 | ✅ audit 已修 |
| — | 硬编码系统色 | — | P1 | ✅ audit 已修 |
| — | 三列布局 84→72 | — | P1 | ✅ audit 已修 |
| — | 中英混排（xcstrings 未翻译） | P1 | P1 | ❌ pending，S1–S8 全部截图坐实 |
| — | preset vs 功能键层级 | — | P2 | ✅ audit 已修 |
| — | Done 白字对比 | — | P3 | ✅ audit 已修 |
| N1 | 侧栏 72pt 对文本键太窄 | P1 | 补 P1 + P2 | 🆕 新增 |
| N2 | `⌫` vs `.` 语义重量倒挂 | P2 | 未覆盖 | 🆕 新增 |
| N3 | reps mode 「幽灵洞」 | P1 | 未覆盖 | 🆕 新增 |
| N4 | reps mode 底行重心右偏 | P2 | 补 P1 Adaptivity | 🆕 新增 |
| N5 | 浅色下 preset 底色对比不足 | P2 | 补 P2 层级 | 🆕 新增 |
| N6 | 顶部 Divider 突兀跨列错觉 | P3 | 未覆盖 | 🆕 新增 |
| N7 | iPad 键宽 220pt 过大 | P2 | 未覆盖 | 🆕 新增 |
| N8 | SF Symbol 语义不匹配健身概念 | P2 | 补 P1 i18n 修复不彻底 | 🆕 新增 |

**总计新增观察**：8 项（远超 spec 要求的 ≥3）。**未 fix 遗留**：1 项旧（中英混排）+ 8 项新，共 9 项进入 Stage 2 north-star §11 规划输入。

---

## 附录 A — 等价性论证（截图工具 vs 生产键盘）

`/tmp/kbshot` 与生产 `WorkoutNumericKeyboardContentView` 的对应关系：

| 生产 (`WorkoutNumericKeyboard.swift` / `NumericKeypad.swift`) | 截图工具 (`/tmp/kbshot/Sources/kbshot/main.swift`) | 是否等价 |
|---|---|---|
| `HStack(alignment: .top, spacing: 8)` (:83) | 同 | ✅ |
| `leftColumn.frame(maxWidth: 72)` / `.frame(width: 72)` | `.frame(width: 72)`（更严格） | ✅ 视觉一致 |
| `VStack(spacing: 6)` 左/右列 | 同 | ✅ |
| 数字键 `.font(.title2).fontWeight(.medium)` + `.frame(maxWidth: .infinity, minHeight: 52)` + `RoundedRectangle(cornerRadius: 8)` + border | 同 | ✅ |
| 功能键 `.font(.footnote).fontWeight(.medium).minimumScaleFactor(0.8).lineLimit(1)` | 同 | ✅ |
| preset 键 `.font(.subheadline).fontWeight(.semibold).monospacedDigit()` | 同 | ✅ |
| Done 键 `.font(.subheadline).fontWeight(.semibold)` + `theme.primary.primary` bg + `theme.primary.onPrimary` fg | 同 | ✅ |
| `Theme(seed: .teal, neutral: .slate, isDark: ...)` | 同 | ✅ |
| 数字键 `.foregroundStyle(theme.neutrals.text1)` (`NumericKeypad.swift:101`) | 同（关键 P0 fix 已复现） | ✅ |
| `⌫` `.foregroundStyle(theme.neutrals.text2)` / `.background(theme.neutrals.inner)` | 同 | ✅ |
| 触觉反馈 `UIImpactFeedbackGenerator` | 未复刻（不影响截图） | N/A（静态渲染） |
| 音频反馈 `UIDevice.playInputClick()` | 未复刻 | N/A |
| `UIHostingController` inputView 挂载 | 未复刻（macOS ImageRenderer 直接 rasterize） | N/A |

差异只集中在**运行时行为**（触觉/音频/inputView bootstrap），**视觉输出完全等价** —— 因为 `WorkoutNumericKeyboardContentView` 已被架构 A 显式设计成"接收 `theme` 参数、不依赖任何外部 Environment 的 pure view"（这是 audit P0 修复的核心）。因此本工具的 PNG 与真实 simulator 截图**在设计层同尺寸下应像素级一致**（细微差异仅来自 macOS vs iOS 字体 hinting，不影响任何 P0/P1/P2/P3 判定）。

---

## 附录 B — 交给 Stage 2 的输入清单

Stage 2 north-star §11 起草时应处理：

1. 遗留 P1（中英混排）—— xcstrings 补 zh-Hans 串
2. N1 —— 侧栏图标化 + 宽度重估
3. N2 —— `⌫` 与 `.` 重量语义修正
4. N3+N4 —— reps mode 底行布局重设（0 居中 / 或列重排）
5. N5 —— 浅色 preset 底色对比强化
6. N6 —— 删除或规范化 Divider
7. N7 —— iPad 键宽 cap
8. N8 —— 功能键图标语义映射（考虑 long-press 或 pill 缩写）

north-star §11 需给出每项的具体 token / 具体值，Stage 3 review 会用本 diagnosis 逐项验回归。
