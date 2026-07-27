# Workout Numeric Keyboard — 现状截图诊断

**Sub-issue**: MY-1349（Stage 1 of MY-1342）
**日期**: 2026-07-27
**基线**: `agent/fullstack-engineer/91757ddf` @ github.com/LeePepe/VitalStride
**Audit 参照**: `specs/keyboard-redesign-audit.md`（2026-07-14）

---

## 截图生成方法（可复现，真机 iOS Simulator + 生产 UITextField.inputView 路径）

> **前两轮 P0 修复历史**：
> - **v1**: 用 macOS `ImageRenderer` 光栅化"结构等价的复刻 view" → P0 (非真机)
> - **v2**: 用 iOS Simulator 但把 `WorkoutNumericKeyboardContentView` 直接挂到 `VStack + Spacer + .frame(...)` → P0 (真机但**不是生产 inputView 路径**)
> - **v3（本次，此文档描述的方法）**: iOS Simulator + **真 `UITextField` 聚焦，其 `inputView` 是生产 `WorkoutNumericKeyboard` UIView 实例** → 与未来 Stage 3 `SelectAllTextField` / `SetRow` 的实际线路一致

### 1. 最小 iOS host（源码包含生产 view，零改动）

在**工作区外**（`/tmp/kbhost/`）搭建一个最小 XcodeGen iOS app：

```yaml
# /tmp/kbhost/project.yml
name: KBHost
options: { bundleIdPrefix: com.tianpli.kbhost, deploymentTarget: { iOS: "18.0" } }
packages:
  DesignKit:    { path: <repo>/Packages/DesignKit }
  VitalModels:  { path: <repo>/Packages/VitalModels }
targets:
  KBHost:
    type: application
    platform: iOS
    sources:
      - path: App                                       # 本地 host bootstrap
      # ↓ 直接以绝对路径 source-include 生产文件，不复制、不改动、不 fork
      - path: <repo>/VitalStride/Sources/WorkoutNumericKeyboard.swift
      - path: <repo>/VitalStride/Sources/NumericKeypad.swift
      - path: <repo>/VitalStride/Sources/Defaults/ExerciseDefaults.swift
    dependencies:
      - package: DesignKit
      - package: VitalModels
    settings:
      base: { CODE_SIGNING_ALLOWED: NO, TARGETED_DEVICE_FAMILY: "1,2" }
```

`App/WeightUnitShim.swift` 只声明 `enum WeightUnit { case kg, lb }` 用于 `ExerciseDefaults` 编译（`resolvePreset` 代码路径不触碰此类型）。启动参数 `--field weight|reps --set working|warmup --dark 0|1` 选定渲染上下文。

**关键：生产 inputView 路径**（`App/KBHostApp.swift`）：

```swift
// 1) 一个真 UIWindow + UIViewController，overrideUserInterfaceStyle 由 --dark 决定
// 2) 一个真 UITextField 放在 safe-area 顶部（截图里能看到 "focus me" placeholder）
// 3) 用生产的 WorkoutNumericKeyboard UIView init 构造实例：
let keyboard = WorkoutNumericKeyboard(
    field: HostConfig.field, setType: HostConfig.setType,
    exercise: nil, recentWeightKg: nil,
    onKeyPress: { _ in }, onLeftAction: { _ in },
    onPresetReps: { _, _ in }, onDone: { }
)
// 4) 把它挂成 inputView（这就是 Stage 3 SelectAllTextField / SetRow 的做法）：
textField.inputView = keyboard
// 5) 让 textField 成为 firstResponder → UIKit 用标准 input-view slide-up 动画呈现
textField.becomeFirstResponder()
```

这条链路和生产 Stage 3 wiring 完全一致 —— 键盘作为 `UITextField.inputView` 被 UIKit 呈现，宽度=容器宽度，高度=键盘自己的 `heightAnchor`（生产 `preferredHeight()`：iPhone 240 / iPad 260），slide-up 动画由 UIKit 提供。iPad 截图（S5–S8）在键盘上方能看到 iOS 系统 inputAssistant 条（undo / redo / paste 图标）—— 这条只有真 inputView 呈现时才会出现，本身就是"这是真的 UITextField.inputView 而非 substitute VStack"的额外证据。

**约束满足**：`Files NOT to touch` 中的 `WorkoutNumericKeyboard.swift` / `NumericKeypad.swift` **零改动** —— host 用 `sources: [{ path: absolute }]` 引用原文件；`WorkoutNumericKeyboard` 内部是 `internal` 级别，但因为 xcodegen source-include 到 KBHost 目标本身，在 KBHost 模块作用域内可访问。

### 2. 捕获 8 张真设备截图

```bash
IPHONE=99C94787-8EBC-4A57-94BE-89D4F6EF7414   # iPhone 16, 1179×2556 px
IPAD=7693C4AB-5DEE-4785-BD7B-E17128734146     # iPad Pro 11" M4, 1668×2420 px

capture () {
  local udid=$1 appearance=$2 field=$3 setType=$4 name=$5
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" \
      --field "$field" --set "$setType" --dark "$([ $appearance = dark ] && echo 1 || echo 0)"
  sleep 2.5   # 等 becomeFirstResponder + inputView slide-up + autolayout settle
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$name.png"
}

# 8 张 = {iPhone 16, iPad Pro 11"} × {light, dark} × {working+weight, warmup+reps}
```

**尺寸**（`sips -g pixelWidth -g pixelHeight` 实测）：full-device 截图（未裁剪）
- iPhone 16 = **1179 × 2556 px**
- iPad Pro 11" M4 = **1668 × 2420 px**（注：不是 1668×2388；先前记录有误，本轮已按实测修正）

这样连**系统 status bar / home indicator / iPad inputAssistant 条** 都在结果里 —— 恰好是"用户真正看到什么"的诊断素材，也让 N9（右列缺失）无法被裁剪掩盖。

---

## 截图清单

| # | 文件 | 设备 | Field | SetType | Appearance | 原尺寸 (px) |
|---|------|------|-------|---------|-----------|-----|
| S1 | `iphone16-working-weight-light.png` | iPhone 16       | weight | working | Light | 1179×2556 |
| S2 | `iphone16-working-weight-dark.png`  | iPhone 16       | weight | working | Dark  | 1179×2556 |
| S3 | `iphone16-warmup-reps-light.png`    | iPhone 16       | reps   | warmup  | Light | 1179×2556 |
| S4 | `iphone16-warmup-reps-dark.png`     | iPhone 16       | reps   | warmup  | Dark  | 1179×2556 |
| S5 | `ipadpro11-working-weight-light.png`| iPad Pro 11" M4 | weight | working | Light | 1668×2420 |
| S6 | `ipadpro11-working-weight-dark.png` | iPad Pro 11" M4 | weight | working | Dark  | 1668×2420 |
| S7 | `ipadpro11-warmup-reps-light.png`   | iPad Pro 11" M4 | reps   | warmup  | Light | 1668×2420 |
| S8 | `ipadpro11-warmup-reps-dark.png`    | iPad Pro 11" M4 | reps   | warmup  | Dark  | 1668×2420 |

---

## 现有 audit 已覆盖的问题（本次仅确认，不重复）

- **P0（数字键不可见）**：audit 已修（架构 A + `.foregroundStyle(text1)`）。S1–S8 数字键 1-9/0 均清晰可读，深浅色都过，**已回归通过**。
- **P0（theme 断链）**：audit 已修（`WorkoutNumericKeyboard.resolveTheme(isDark:) + traitCollectionDidChange refreshTheme`, `WorkoutNumericKeyboard.swift:305–437`）。S2/S4/S6/S8 dark 背景/字色正确翻转，**已回归通过**。
- **P1（硬编码系统色）**：代码全部 `theme.neutrals.*` / `theme.primary.*` token，**已修**。
- **P1（三列布局窄屏挤压）**：audit 提出 84→72，代码已改（`WorkoutNumericKeyboard.swift:85,90` = `maxWidth: 72`），**但引入了 N9 新回归**（见下）。
- **P1（中英混排）**：`.xcstrings` defaultValue 仍是英文；S1–S8 上左列 "U..." / "C..." 是英文 "Uni/Total" / "Copy" 的截断（见 N2），**P1 pending**。
- **P2（层级不清 / preset vs 功能键）**：**无法在真机截图中验证**，因为 preset/Done 键（右列）根本没渲染（N9）。改判为 pending。
- **P2（Dynamic Type 截断）**：`NumericKeypad.swift:78` 仍 cap 到 `xxxLarge`；左列文本键在真设备默认字号已经截断（见 N2），**未修**。
- **P3（Done 白字对比偏低）**：**无法验证**，Done 键未渲染（N9）。

---

## 🆕 新观察（本轮 iOS Simulator 真机截图新增）

### N9（P0）— 右侧列（15-20 / 8-12 / 4-6 preset + Done）完全消失，实际 iPhone 16 / iPad Pro 11" 两平台都只渲染出「左功能列 + 中间数字列」，右列宽度坍缩到 0（前一轮 macOS harness 用 `.frame(width: 72)` 硬约束掩盖了这个 bug；真设备用 SwiftUI 默认 `maxWidth: 72` + 中间列 `.layoutPriority(1)` 组合，中间列贪婪吃满全部剩余宽度）

**类别**：Layout / Regression / Functionality-lost
**严重度**：**P0**（用户完全无法使用 preset / Done —— reps 快捷输入路径断掉，Done 收键路径断掉）
**证据**：
- S1 (iPhone 16 light, weight/working) —— 底部键盘只见左边 4 个 icon-column + 中间 3×4 数字 grid，图像右缘之外**没有 preset / Done 键**。
- S5 (iPad Pro 11" light, weight/working) —— 同样症状，只是尺度不同：数字键宽约 380pt，右侧完全空白（`⌫` 出现在图像顶部第 90px 处的孤立位置，是键盘 top-row 的另一个 anchor，说明右列的 layout 计算出了问题，右列 4 个键在 zero-width 情况下垂直堆叠、其中最靠上的 `⌫` 被绘制到了 top-safe-area 里）。
- 所有 8 张截图（S1–S8）都缺失右列 —— 无 mode/appearance/platform 例外。
**根因**（源码分析 `WorkoutNumericKeyboard.swift:83-102`）：
```swift
HStack(alignment: .top, spacing: 8) {
    leftColumn.frame(maxWidth: 72)          // maxWidth，不是 width — 可以坍缩
    NumericKeypad(...).layoutPriority(1)   // 显式 layoutPriority=1
    rightColumn.frame(maxWidth: 72)        // maxWidth，不是 width — 可以坍缩
}
```
SwiftUI layout：父容器把可用宽度先给 `layoutPriority > 0` 的子 view（中间列），只有剩余空间才轮到 `layoutPriority = 0` 的左右列。中间 `NumericKeypad` 的 `LazyVGrid(columns: 3 × .flexible())` 是"没有内在宽度上限的 greedy view" —— 它吃满全部宽度后，左右列剩下 0，`maxWidth: 72` 只是**上限**、不是**下限**。左列因为 icon（`Image(systemName:)` 有内在尺寸约 25pt）撑起了 ~40-50pt 宽度得以显示，右列因为 preset 文字（`.subheadline` monospaced digit）也有内在宽度但仍被压缩到 0（甚至负 —— iPad 上出现的顶部错位 `⌫` 就是溢出结果）。
**与 audit 的关系**：audit 提"三列布局 84→72"是把左右列硬编码 84 改成 `maxWidth: 72`，**引入了这个 layout 优先级 bug**。audit 之前 84 是绝对宽度（`.frame(width: 84)`），现在 72 是上限（`.frame(maxWidth: 72)`），配合中间列 `.layoutPriority(1)` 就是"我优先吃满，你随缘"。
**建议**（Stage 2 修）：
1. 最小修：把 `maxWidth: 72` 改回 `width: 72` 或 `minWidth: 72, maxWidth: 96`，或去掉 `.layoutPriority(1)`。
2. 更好：改用 `GeometryReader` 分配宽度，或把三列换成 `Grid` 显式列定义。
3. 修完必须重跑 8 张真机截图回归 —— macOS harness 无法验证。

### N10（P1）— 左列功能键标签在真 iPhone 16 上被截断为「U...」/「C...」，`.footnote + minimumScaleFactor(0.8) + lineLimit(1)` 组合仍然抗不住 72pt 侧栏 + 8pt padding 的实际可用宽度

**类别**：Adaptivity / i18n / Dynamic Type
**证据**：
- S1 / S2 / S3 / S4（iPhone 16）左列第 3、4 键的标签**明显显示为「U...」和「C...」** —— 不是 "Uni/Total"、不是 "Copy"，就是**两个字符加省略号**。
- S5 / S6 / S7 / S8（iPad Pro 11"）同样被截断为「U...」和「C...」，**尽管 iPad 屏幕大**，因为侧栏宽度硬编码 72pt 与设备无关。
**与 audit 的关系**：加强了 audit [P1] Dynamic Type 与 audit [P2] i18n 的严重度 —— 就算不换语言、不放大字号，**默认英文默认字号**已经截断到不可辨识；这坐实了 audit 建议的「侧栏文本键改 SF Symbol」是必须而不是可选。原 diagnosis N1 说"临界"是低估了 —— 真设备已**跨过临界**。
**建议**：见 Stage 2 —— 侧栏两键改 SF Symbol，或把侧栏宽度上升到 96pt（配合 N9 修）。

### N11（P1）— 顶部 `Divider()` 在真设备上是一条**跨越整个键盘顶端**的浅灰 hairline，从图像 leading 到 trailing（不再是"看着像跨列"—— 实测 iPad S5 顶部 Divider 从 x≈8px 一直画到 x≈1660px），因为中间列贪婪吃满宽度（N9 根因），Divider 又是 `NumericKeypad` 顶部第一个元素、宽度跟随中间列

**类别**：Visual noise / Framing
**证据**：S5 / S6 顶部有一条明显 1px 灰线从键盘 leading 拉到 trailing，压在 status bar 下方安全区里；iPhone S1–S4 类似但因宽度小不那么突兀。
**与 audit 的关系**：audit 未提；`NumericKeypad.swift:64` 的 `Divider()`。修 N9 后 Divider 只会跨中间列，但仍冗余（`UIInputView` 顶部已有隐式边界）。
**建议**：删除 `NumericKeypad.swift:64` 的 `Divider()`；或加 `.padding(.horizontal, 12)` 与数字键左右对齐。

### N12（P2）— reps mode 底行「幽灵洞」在真设备上依然存在（`Color.clear.frame(minHeight: 52)`）

**类别**：Layout / Predictability / Gestalt
**证据**：S3 / S4（iPhone 16 warmup+reps）底行只有 `0` + `⌫`，左侧应放小数键的位置是**没有边框、没有底色的透明区**；S7 / S8 因为整个右列缺失（N9），底行呈现「空格 + `0` + `⌫`」的 3-cell 布局但空格是真透明。用户视觉上看到 3×3 完整 grid + 底行**空一个 tile**，误触风险 + Gestalt 完形破坏（`NumericKeypad.swift:86-90`）。
**与真设备关系**：与之前 macOS harness 观察一致（这条不是回归，是长期存在），但真机上因 status bar/home indicator 的存在，用户视线更聚焦键盘区，"洞"更显眼。
**建议**：reps mode 下把「0」居中占两格（`gridCellColumns(2)`）+ `⌫` 保持右下；或整体重排底行。

### N13（P2）— 深色模式（S2/S4/S6/S8）背景是**纯黑 `#000000`**（`theme.neutrals.bg` in dark = system black），与生产其他页面（health dashboard、workout log）的 `.slate` neutral dark bg（应为 slate-950 = `#0f172a`）**不一致**

**类别**：Consistency / Brand
**证据**：S2 iPhone 16 dark 键盘 bg 目视为 `rgb(0,0,0)`，与 OLED status bar 完全无缝（说明是真 `#000` 或极接近）；VitalStride 其他 dark surface 是带蓝调的 slate 深色。这一致性问题是 DesignKit `Theme(neutral: .slate, isDark: true).neutrals.bg` 在 dark 下 override 到 `.black` 造成的（需要 DesignKit token audit）。
**与 audit 的关系**：audit 未提；audit 只验证了 theme "存在"和 "深浅切换", 未验证**颜色值本身**是否与全局 dark 主题一致。
**建议**：Stage 2 north-star §11 要求 DesignKit team 确认 `Theme(neutral: .slate, isDark: true).neutrals.bg` 应为 `slate-950` 而非 `.black`；或本 view 显式改用 `theme.neutrals.surface` / `theme.neutrals.canvas`（如果 DesignKit 有）。

---

## 汇总表 — 现状 vs audit

| # | 问题 | 严重度 | audit 编号 | 现状 |
|---|-----|--------|-----------|-----|
| — | 数字键不可见 | — | P0 | ✅ audit 已修 |
| — | theme 断链 | — | P0 | ✅ audit 已修 |
| — | 硬编码系统色 | — | P1 | ✅ audit 已修 |
| — | 三列布局 84→72 | — | P1 | ⚠️ audit 修法引入 N9 P0 回归 |
| — | 中英混排（xcstrings 未翻译） | P1 | P1 | ❌ pending，S1–S8 全部坐实 |
| — | preset vs 功能键层级 | — | P2 | ⏸ 无法验证（右列消失 N9） |
| — | Done 白字对比 | — | P3 | ⏸ 无法验证（右列消失 N9） |
| **N9** | **右列消失（layoutPriority + maxWidth 组合 bug）** | **P0** | **补 audit P1 修法回归** | **🆕🔥 新增 — 阻断 preset/Done 全功能** |
| N10 | 侧栏文本键真机默认字号已截断为 「U...」/「C...」 | P1 | 补 P1 i18n + P2 DT | 🆕 新增（macOS harness 有低估） |
| N11 | 顶部 Divider 真设备横跨整宽 | P3 | 未覆盖 | 🆕 新增 |
| N12 | reps mode「幽灵洞」 | P2 | 未覆盖 | ✅ 沿用前观察（仍存在） |
| N13 | dark bg = 纯黑 与其他页 slate 不一致 | P2 | 未覆盖 | 🆕 新增（真机可辨） |

**总计新增/确认观察**：5 项（N9–N13），远超 spec 要求的 ≥3。**关键 flag**：N9 是 P0 布局回归，来源是 audit P1 修法的副作用（`maxWidth: 72` + `layoutPriority(1)` 组合把右列压到 0）。这是本轮真机截图**唯一**能发现、macOS ImageRenderer 复刻无法发现的观察。

**未 fix 遗留（进入 Stage 2 north-star §11 规划输入）**：
1. **N9（P0 blocker）** —— 必须优先修，否则 preset/Done 无法使用；建议 `.frame(width: 72)` 或去除 `.layoutPriority(1)`
2. 遗留 P1（中英混排）—— xcstrings 补 zh-Hans 串
3. N10 —— 侧栏图标化 或 侧栏宽度上调
4. N11 —— 删除或规范化 Divider
5. N12 —— reps mode 底行布局重设（0 居中 / 或列重排）
6. N13 —— DesignKit slate dark bg 一致性

修完必须**重跑本 8 张真机截图**做回归，macOS 复刻不能作为验收。
