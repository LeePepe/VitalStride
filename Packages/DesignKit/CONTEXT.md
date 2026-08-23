---
layer: DesignKit
role: VitalStride 唯一设计语言；单 seed color → 主色 token 全集 + 固定 neutral/semantic + SwiftUI 组件
paths: [Packages/DesignKit]
test_paths: [Packages/DesignKit/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/DesignKit
depends_on: []
depended_by: [AppUI, Prototype]
red_lines:
  - 单一设计语言、单一 seed-based 配色：换主题只换 seed，禁止 fork 语言或另起第二套 palette
  - neutral + semantic palette 固定，不随 seed 变（与 design-system web 端同一套 seed 数学）
  - UI 字符串必须用 String(localized:) / NSLocalizedString 引用 xcstrings，禁止硬编码中文（宪法 VI）
  - Swift 6 strict concurrency，token/palette 须 Sendable，View 遵守 MainActor（宪法 II）
roles:
  Types: [Color, Theme]
  UI:    [Components, DashboardView]
test: swift test --package-path Packages/DesignKit
owns: [Seed, PrimaryPalette, Theme, Card, Metric, Sparkline, RingGauge, DashboardView]
---

# DesignKit Context

## 职责

VitalStride **唯一**设计语言(iOS / macOS / watchOS 共用)。核心是"**单 seed color → 全套主色 token**"
的确定性生成 + 固定的 neutral / semantic palette + 一组 SwiftUI 组件。与 design-system web 端
共用同一套 seed 数学,保证跨平台视觉一致。

> **集成状态**:已注册到 `project.yml`(`packages:` + iOS/macOS/watchOS 三个 app target
> 依赖),与 VitalUI 同级共享。改动 target 配置后需 `xcodegen generate`(宪法 §IV)。

## 架构

### Color(Types)

`ColorSystem.swift` —— 配色系统事实源:

- `enum Seed` —— 预设 seed 色(每个可解析为 hex)。
- `makePrimaryPalette(seed:isDark:) -> PrimaryPalette` —— 从单个 seed 派生 light/dark 主色全集。
- `chartPalette(seed:isDark:) -> [Color]` —— 8 档图表色。
- `enum Neutral` / `Neutrals` —— **固定**中性色阶(不随 seed 变)。
- `enum Semantic` —— **固定**语义色(success/warning/danger 等,不随 seed 变)。

**红线**:主色随 seed 变,neutral/semantic **不变**。改配色 = 换 seed,**不新增第二套 palette**。

### Theme(Types)

`Theme.swift` —— 把三层色(primary / neutral / semantic)+ `Radius` / `Space` / `TypeScale`
组装成可注入的 `Theme`,经 `EnvironmentValues` + `View` 扩展下发给组件。

### Components / DashboardView(UI)

`Components.swift` —— `Card` / `CardInner` / `Metric` / `Sparkline` / `RingGauge` /
`StatusPill` / `SectionHeader` 等无业务逻辑的展示组件,全部消费 `Theme` token。
`DashboardView.swift` —— 组合上述组件的示例仪表盘视图。

## 依赖

无本地 layer 依赖(`depends_on: []`)。纯 SwiftUI + Foundation。

## 约束

- 换主题 = 传新 seed 给 `makePrimaryPalette`,不改组件、不 fork 语言。
- 新组件消费 `Theme` token,不硬编码颜色/间距/圆角/字号。
- 层内轴:`Color`/`Theme`(Types)不得依赖 `Components`/`DashboardView`(UI)。
