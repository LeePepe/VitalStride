# VitalStride Constitution

VitalStride 是一个**健康数据收集 + AI 分析** iOS/macOS/watchOS App（个人项目）。本宪法是 audit 性的——每条原则都对应代码库已落地的事实，违反会被 hook / reviewer block。

---

## Core Principles

### I. 健康数据隐私零妥协 (NON-NEGOTIABLE)

HealthKit 数值不离设备、不入日志、权限撤销即清除。

- **本地隔离**：HealthKit L2 缓存（`HealthCacheEntry`）必须 `ModelConfiguration(cloudKitDatabase: .none)`，禁止参与 iCloud/CloudKit 同步。仅训练数据（`Workout`/`WorkoutExercise`/`ExerciseSet`/`Exercise`/`WorkoutTemplate`/`TemplateExercise`）允许 CloudKit-synced。
- **零日志**：os_log / print / 第三方 SDK 禁止输出实际健康数值（心率值、体重值、步数值、睡眠时长等）。仅可记录 sample type / 数量 / 时间范围等元数据。
- **撤销即清**：用户撤销 HealthKit 权限后必须立即完整清除 — `HealthDataCache.invalidateAll()` + 删除全部 `HealthCacheEntry` + `HealthKitAnchorStore.removeAllAnchors()` + 清零持久化 telemetry 计数器。

参考：ADR-0003 (HealthKit + SwiftData 双数据源)、CONTEXT.md §缓存层隐私合规约束。

### II. Swift 6 Strict Concurrency (NON-NEGOTIABLE)

`SWIFT_VERSION: 6.0` + strict concurrency，全 package 与 app target。引入新代码不得通过 `@preconcurrency` / `nonisolated(unsafe)` / `@unchecked Sendable` 绕过——必须用 actor / Sendable struct / MainActor isolation 表达。

例外仅限：Apple 系统 API 边界（HealthKit/CloudKit 旧签名）+ 必须在 ADR 中显式记录原因。

### III. SPM Package 优先 (NON-NEGOTIABLE)

业务逻辑住在 `Packages/`，app target 只放平台入口和 UI。

| Package | 职责 | 依赖 |
|---------|------|------|
| VitalModels | SwiftData models, enums, ModelContainerConfiguration | — |
| HealthKitService | HealthKit 查询、Anchor、HealthDataPoint、缓存 | VitalModels |
| AIService | AIProvider 协议、ZhipuProvider、ChatMessage/Response | — |
| VitalUI | 共享 UI 组件 | VitalModels |
| TelemetryKit | TelemetryEvent、TelemetryProvider、Console/Service | — |

**规则**：
- App target 不互相依赖，只依赖 packages。
- 新 AI provider = 在 `AIService` 实现 `AIProvider` 协议，不新建包。
- 改动仅涉及 `Packages/<X>/` 时，**必须**用 `swift build && swift test` 验证；禁止用 xcodebuild（慢且无意义）。
- 新增 package 需 ADR 并更新 `project.yml` + 本宪法表格。

参考：ADR-0004 (五个本地 SPM 包)、ADR-0007 (TelemetryKit standalone)。

### IV. XcodeGen 是配置真理之源 (NON-NEGOTIABLE)

`project.yml` 是 Source of Truth；`VitalStride.xcodeproj/project.pbxproj` 是生成物。

- 任何长期 build setting（DEVELOPMENT_TEAM、签名、entitlements、target 配置）**必须**落在 `project.yml`。
- 禁止在 Xcode UI 改设置——任意 `xcodegen generate` 都会 reset。
- 改动 target 配置后必须 `xcodegen generate` 并 commit `.xcodeproj` 同步变更。
- 测试目录用目录源引用，新增测试文件无需 pbxproj 手动维护。

参考：vitalstride skill §"Xcode 项目配置"（账户/team reset 反复教训）。

### V. AI 用本地优先 + 国内 fallback，无第三方 SDK

AI provider chain：**Apple Intelligence Foundation Models 优先**（On-device, iOS 18.1+），**智谱 GLM-4-Flash fallback**（OpenAI-compatible REST via URLSession）。

- 禁止引入 OpenAI/Anthropic/Google SDK 等第三方包。
- API key 仅存 Keychain，不得硬编码。
- 新增 provider = 在 `AIService` 实现 `AIProvider` 协议接入 chain，不替换。

参考：ADR-0005 (AI ProviderChain)。

### VI. I18n：xcstrings 单源 + 无硬编码 (NON-NEGOTIABLE)

- UI 字符串必须用 `String(localized: "key", comment: ...)` 或 `NSLocalizedString("key", ...)` 引用 catalog。
- `Localizable.xcstrings` 是唯一翻译源，**严禁同名 `.strings` / `.stringsdict` 共存**（Xcode 26 硬错 + pre-push 必失败，详见 ADR-0007 教训 / MY-882）。
- SwiftLint `no_hardcoded_chinese` warning（非阻塞但代码 review 必处理）。
- 工具：`python3 scripts/i18n_extract_hardcoded.py` 找漏迁移；`python3 scripts/i18n_check_lproj_parity.py` 查覆盖率。

参考：AGENTS.md §I18n、`.swiftlint.yml`。

### VII. 范围克制：watchOS/macOS 是 companion

当前阶段：iOS 是主战场，macOS/watchOS 是 companion target，**不立项专属 feature**。

- iOS 全功能；macOS 复用 iOS 视图（SwiftUI 自适应）；watchOS 仅展示训练 + 健康概览。
- 不为 watchOS 写独立 complication / 独立训练流程；不为 macOS 写 menubar / shortcut intent 等。
- 重启 watchOS/macOS 专属 feature 需新 ADR 推翻 ADR-0002。

参考：ADR-0002 (deferred watchOS / macOS feature work)。

---

## Module Architecture

```
App targets (iOS / macOS / watchOS)
    │  仅含入口、平台 UI、Live Activity widget
    ↓
VitalUI ←── VitalModels
    │            ↑
    ↓            │
HealthKitService ┘
    AIService    (独立, 无依赖)
    TelemetryKit (独立, 无依赖)
```

**Rules**：
- 依赖单向：app → packages，packages 之间最多一层依赖（VitalUI → VitalModels，HealthKitService → VitalModels）。
- `DataView` / `DataSections` 保留在 app target（不在 package），因为耦合 platform-specific 行为。
- Rest Timer 用 Live Activity（iOS 16.1+ ActivityKit）渲染——见 ADR-0006。

---

## Data & Persistence

**SwiftData，双 ModelConfiguration**：

| Configuration | Models | CloudKit | 用途 |
|---------------|--------|----------|------|
| Default (Training) | Workout, WorkoutExercise, ExerciseSet, Exercise, WorkoutTemplate, TemplateExercise | ✅ synced | 训练数据多设备同步 |
| `"HealthCache"` | HealthCacheEntry | ❌ `.none` | HealthKit L2 本地缓存 |

**HealthKit 两层缓存**：
- **L1**: `HealthDataCache` actor（纯内存、零延迟热路径，进程生命周期）
- **L2**: `HealthCacheEntry` SwiftData（本地磁盘、跨启动、CloudKit 隔离）
- **TTL**: 默认 1h；stale-serve-then-refresh（过期数据立即返回 + 后台刷新）
- **Anchor**: 通过 `HealthKitAnchorStore` 持久化 HKQueryAnchor，增量查询新数据
- **冷启动**: `hydrate()` 从 L2 预加载 `overviewTypes` 到 L1

**禁止**：使用 NSUbiquitousKeyValueStore / 第三方 iCloud 包装 / 任何 HealthKit 数值参与 CloudKit / 任何健康数值进入 NSUserDefaults。

参考：CONTEXT.md §Data Architecture Decisions、ADR-0003。

---

## Development Workflow

### Git: No-PR Workflow (NON-NEGOTIABLE)

| 角色 | 推到哪 | 推什么 |
|------|--------|--------|
| Fullstack (FS) | 本地 bare repo | `agent/<issue-key>-<task-id-short>` |
| Team Lead (TL) | `github` remote | **只 main** |
| AI Reviewer | （不推） | review FS commits |

`scripts/hooks/pre-push` 强制：只 `main` 能推 `github`/`gitlab`；agent/* 分支每个 commit 必须含 `MY-\d+`。详见 ADR-0001、AGENTS.md §Git Workflow。

### Commit Message 约定

- **Agent 分支**：每个 commit 必须含 `MY-\d+`（issue key），subject 或 body 任一位置。
- **Main 直 commit（工程改动）**：用 `chore(...)` / `docs(...)` / `ci(...)` 前缀，无 issue key 时加 `(retro A-XX)` 占位以保留追溯。
- 历史教训：2026-06 retro 发现 92% commit 缺 issue key，pre-push 已强制。

### Build & Test Gate

- **Packages/ 仅改动** → `swift build && swift test`（per package）
- **App target 改动** → `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation`
- pre-push hook 自动选择路径（SPM-only fast path）
- 共享 `<git-common-dir>/derived-data` + `flock` 保护并发 build
- 纯 docs/hooks/scripts 改动 skip build

### 平台 Deployment Target

- iOS 18.0 / macOS 15.0 / watchOS 11.0（`project.yml options.deploymentTarget`）
- 降级需新 ADR + 全 package compatibility 审查

### Issue Tracker / Spec Execution

- **Multica** 项目 UUID `7adf8b88`，issue prefix `MY-*`
- 每个 issue 标题 `[T###] [Story] Brief description`（spec-kit handoff 约定）
- Hermes 端写 spec/plan/tasks，**`/speckit-implement` 不使用**——tasks.md 通过 `multica-quick-issue` 批量入 Multica，TL → Planner → FS → Reviewer pipeline 执行
- 每 feature 一个 Multica project（不要 phase 多项目）

---

## Cross-Cutting Quality Bars

> AI Reviewer / TL 唯一权威 finding 源。task body 引用本节，不重述。

### P0 — Ship Blocker (🔴 FAIL)

- **A. 范围纪律**：PR 只能改 task 的 "Files in scope" + 对应测试。删除/改动 sibling task 的文件 = 🔴 FAIL（关 PR 重派，不 rebase）。
- **B. 健康隐私**：任何 HealthKit 数值进 log / 进 CloudKit / 进 NSUserDefaults = 🔴 FAIL（Principle I）。
- **C. Strict Concurrency**：新增 `@preconcurrency` / `nonisolated(unsafe)` / `@unchecked Sendable` 未在 ADR 记录 = 🔴 FAIL（Principle II）。
- **D. 错误处理**：production 代码新增 `fatalError` / `try!` / `as!` = 🔴 FAIL。HealthKit/AI/网络错误必须 graceful degradation。
- **E. XcodeGen Drift**：直接改 `.xcodeproj` 不改 `project.yml` = 🔴 FAIL（Principle IV）。
- **F. xcstrings 共存**：与 `Localizable.xcstrings` 同名的 `.strings`/`.stringsdict` = 🔴 FAIL（Principle VI）。

### P1 — Must Fix (🟡)

- **G. I18n**：硬编码用户可见字符串（中/英）= P1。功能正确时 → 🟢 PASS WITH FOLLOW-UP + 拆 follow-up sub-issue。
- **H. Accessibility**：Dynamic Type 支持、hit target ≥ 44pt、decorative icon hidden。
- **I. Test Coverage**：新 public API 必须有 round-trip 测试；新 SwiftUI view 至少 2 个 Preview。

### P2 — Nice to Have (ℹ️，never blocks merge)

- 风格、注释优化、命名建议。

### Verdict Aggregation

- 任意 P0 → 🔴 FAIL
- 无 P0 + 有 P1 + **功能正确** → 🟢 PASS WITH FOLLOW-UP（拆 sub-issue，当前 PR 立即 merge）
- 无 P0 + 有 P1 + **功能 broken** → 🟡 CHANGES REQUESTED（回 FS）
- 仅 P2 / 无 finding → 🟢 PASS

---

## Governance

本宪法管辖 VitalStride 所有开发工作。所有 AI/人类贡献者（FS/TL/Reviewer，含 Codex/Claude/Hermes 子代理）必须读取并遵守。

- 任何与本宪法冲突的 PR 必须修改 PR 或修宪法（先 ADR）。
- **修改宪法**：新 ADR + 本文件 patch + 版本 bump + 在 PR 描述 link 到 ADR。
- 版本规则（语义化）：
  - MAJOR — 删除/反转原则；MINOR — 新增原则/新 Quality Bar；PATCH — 文字澄清不改语义
- 与本宪法相关：AGENTS.md（agent 操作手册）、CONTEXT.md（数据架构细节）、`docs/adr/`（决策档案）、`scripts/hooks/`（强制规则机器实现）。

**Version**: 1.0.0 | **Ratified**: 2026-06-25 | **Last Amended**: 2026-06-25
