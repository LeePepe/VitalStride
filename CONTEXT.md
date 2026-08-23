---
canonical_roles: [Types, Config, Repo, Service, Runtime, UI]
# Intra-layer stereotype order (class-role dependency axis), NOT package deps.
# Package deps live in each Packages/<X>/CONTEXT.md `depends_on`.
# A lower-role type must never import a higher-role type WITHIN the same package.
#   Types   — models, enums, protocols, DTOs, pure value types
#   Config  — container / configuration assembly
#   Repo    — persistence, keychain, anchor stores, external data access
#   Service — orchestration, providers, business logic
#   Runtime — process/UI-adjacent helpers (haptics, managers)
#   UI      — SwiftUI views / modifiers
---

# VitalStride Context

## Product Identity

VitalStride is a **health data collection + AI analysis** app. Strength training is one data source among many — the app's value is aggregating body data and providing AI-powered insights, not being a workout-only tool.

## Glossary

- **Health Data (健康数据)**: Any data readable from HealthKit — heart rate, steps, sleep, body mass, active energy, etc. This is the primary content of the Data Tab.
- **Workout Data (训练数据)**: Detailed exercise/set/rep data from in-app strength training sessions. Stored in SwiftData because HealthKit cannot represent per-set detail. Displayed in the Workout Tab.
- **Data Tab (数据 Tab)**: Tab 3 — a health data dashboard showing a summary card + grouped list of data types. NOT a training-specific view.

## Data Architecture Decisions

### HealthKit data caching: two-layer architecture

HealthKit is queried directly at read time with a two-layer caching strategy:

**L1: In-Memory Cache (HealthDataCache)** — Pure in-memory Swift actor cache. Primary cache layer for hot data. Lifetime = app process; no disk persistence, no CloudKit sync.

**L2: SwiftData Persistence (HealthCacheEntry)** — Local-only SwiftData model for persisting serialized `[HealthDataPoint]` across app launches. Uses a dedicated `ModelConfiguration(cloudKitDatabase: .none)` to guarantee CloudKit isolation — HealthKit cache data never syncs to other devices.

SwiftData models:
- **Training data** (CloudKit-synced): `Workout`, `WorkoutExercise`, `ExerciseSet`, `Exercise`, `WorkoutTemplate`, `TemplateExercise`
- **Health cache** (local-only, `cloudKitDatabase: .none`): `HealthCacheEntry`

### HealthKit 缓存层（L1 内存 + L2 SwiftData）

**双层缓存设计，平衡热路径性能与冷启动延迟。**

> 架构决策推翻记录：V1 最初选择"纯内存缓存（方案 B）"，理由是实现简单、隐私零风险。后因冷启动延迟过高（每次重新查询多种 HealthKit 数据类型），改为"方案 A（改良版）"：增加 SwiftData L2 持久化层 + CloudKit 隔离（`cloudKitDatabase: .none`），保留隐私合规的同时消除冷启动 penalty。

**L1: 纯内存 Swift actor 缓存 (HealthDataCache)**

理由：
- **零延迟热路径**：View 层优先从内存缓存读取，避免任何磁盘 I/O
- **CloudKit 零风险**：纯内存方案无需考虑 CloudKit 同步隔离
- **实现复杂度低**：无需额外的失效逻辑或 schema 演进负担

**L2: SwiftData 持久化缓存 (HealthCacheEntry)**

理由：
- **冷启动加速**：app 启动时从 L2 恢复数据到 L1（`hydrate()`），避免每次冷启动都查询 HealthKit
- **CloudKit 隔离**：使用独立 `ModelConfiguration("HealthCache", cloudKitDatabase: .none)`，L2 数据仅存本地磁盘
- **异步写回**：HealthKit fetch 成功后在后台将数据持久化到 L2（`persistInBackground()`）
- **Generation guard**：`invalidateAll()` 递增 generation 计数器，防止过期 persist 写入脏数据

**TTL 过期策略**：默认 1 小时（可配置）。L1/L2 共享同一 TTL，过期数据立即返回同时触发后台刷新（stale-serve-then-refresh），兼顾用户体验与数据新鲜度。

缓存层设计要点：
- 使用 Swift actor (`HealthDataCache`) 保证线程安全
- 按 `HealthSampleType` 分桶缓存 `HealthDataPoint` 数组
- Anchor Query 返回新数据时更新对应桶，整桶替换（immutable pattern）
- L1 缓存生命周期 = app 进程生命周期；L2 跨启动持久化
- 读取路径：L1 hit → 返回 | L1 miss → L2 load → L1 回填 | L2 miss → HealthKit fetch → L1+L2 回填
- 冷启动时 `hydrate()` 从 L2 预加载 `overviewTypes` 到 L1
- View 层从 L1 读取，cache miss 时依次查 L2、HealthKit 并回填

### 缓存层隐私合规约束

- **L1（内存）数据不离设备**：缓存数据仅存内存，不经任何网络传输
- **L2（SwiftData）本地隔离**：`HealthCacheEntry` 使用 `cloudKitDatabase: .none`，数据仅存本地磁盘，不参与任何 iCloud/CloudKit 同步
- **权限联动**：用户在系统设置中撤销 HealthKit 权限后，必须立即执行完整清除：清空 `HealthDataCache` 全部缓存数据（`invalidateAll()`）、删除所有 `HealthCacheEntry` 磁盘记录、重置持久化 anchor state（`HealthKitAnchorStore.removeAllAnchors()`）、清零已持久化的 telemetry 计数器，不保留只读副本
- **无日志泄露**：禁止在任何 log（os_log、print、第三方日志 SDK）中输出实际健康数值（心率值、体重值、步数等）。日志仅可记录 sample type、数量、时间范围等元数据
- **内存转储防护**：敏感健康数值在 actor 内部持有，不暴露为全局可访问状态

### 缓存层 Telemetry 需求

以下指标需在 MY-668 实现时埋点，本节仅定义需求：

| 指标 | 维度 | 说明 |
|------|------|------|
| `healthkit_cache_hit` | HealthSampleType | 缓存命中次数，用于衡量缓存有效性 |
| `healthkit_cache_miss` | HealthSampleType | 缓存未命中次数，触发 HealthKit fetch |
| `healthkit_fetch_duration_ms` | HealthSampleType | 单次 HealthKit 查询耗时（ms），用于衡量缓存带来的性能收益 |
| `healthkit_cache_refresh` | HealthSampleType | 缓存刷新次数（anchor query 返回新数据时） |

注意事项：
- Telemetry 仅记录计数和耗时，禁止记录实际健康数值
- 使用 OSSignpost 或自定义 MetricKit 上报，不依赖第三方 SDK

### macOS uses HealthKit for reading

macOS 13+ supports HealthKit (read-only, via iCloud Health sync). VitalStride's minimum is macOS 15.0, so the Data Tab uses the same HealthKit queries on both iOS and macOS. No platform-specific guards needed for data access.

### Single HealthKitService for all data types

One `HealthKitService` in `Shared/Services/` handles all HealthKit queries. Adding a new data type = registering a new type identifier, not creating a new file. Sleep (`HKCategoryType`) has special handling internally but the same external API.

## Data Tab Structure

### Summary Card (top)

2×2 grid of today's body metrics (complements Overview Tab's training summary):
- Steps (today)
- Resting heart rate (latest)
- Sleep (last night duration)
- Body weight (most recent)

### Grouped List

| Group | V1 Data Types |
|-------|---------------|
| 活动 (Activity) | 步数 (.stepCount), 活动能量 (.activeEnergyBurned) |
| 心脏 (Heart) | 心率 (.heartRate) |
| 身体测量 (Body) | 体重 (.bodyMass) |
| 睡眠 (Sleep) | 睡眠分析 (.sleepAnalysis) |

Tapping a row → Detail page.

### Detail Page (per data type)

- Time range Picker (day / week / month / year)
- Swift Charts graph with `chartXSelection` interaction
- Statistics summary (avg / max / min)
- No raw data point list in V1

## V1 Scope Boundaries

- 5 HealthKit data types (see table above)
- No background sync (Observer Query / BGHealthQuery deferred to V2)
- No data point list in detail pages
- Extensible: new types added via HealthKitService registration

## Project Structure: Formal Layers

The project uses XcodeGen + local SPM packages. Business logic lives in packages; app targets contain
platform-specific entry points, UI, and app-specific composition. Every production/test/build-config
path has one formal change-owner layer, including CI-only `AppUI`.

### Packages

| Package | Contents | Dependencies |
|---------|----------|-------------|
| VitalModels | SwiftData models (Workout, Exercise, etc.), enums, ModelContainerConfiguration | None |
| HealthKitService | HealthKitService, HealthDataPoint, HealthKitAnchorStore, HealthSampleType | VitalModels |
| AIService | AIProvider protocol, ZhipuProvider (智谱 GLM), ChatMessage/ChatResponse models | None |
| VitalUI | Shared UI components (DataStoreErrorView) | VitalModels |
| TelemetryKit | TelemetryEvent, TelemetryProvider protocol, ConsoleTelemetryProvider, TelemetryService | None |
| DesignKit | 设计语言:seed-based 配色 token (Seed/PrimaryPalette/Theme) + SwiftUI 组件 (Card/Metric/Sparkline/DashboardView) | None |

### Non-production-package layers

| Layer | Owned paths | Dependencies |
|---|---|---|
| AppUI | `VitalStride/**`, companion app roots, app test roots, `project.yml`, generated `.xcodeproj` | all 6 production packages |
| Prototype | `Prototype/**` | DesignKit |

### Rules

- App targets (iOS/macOS/watchOS) depend on packages, not on each other
- Shared Mac/Watch/Widget source entries remain owned once by AppUI; target reuse does not duplicate layer ownership
- DataView + DataSections remain in app target (shared via project.yml), not in a package
- XcodeGen is retained for managing app targets, entitlements, and package references
- Adding a new AI provider = implementing `AIProvider` protocol in AIService package

## AI Architecture

### Provider

智谱 AI (GLM-4-Flash, free tier). OpenAI-compatible REST API via URLSession. No third-party SDK.

- Endpoint: `https://open.bigmodel.cn/api/paas/v4/chat/completions`
- Auth: `Authorization: Bearer <api-key>`
- Key stored in Keychain, not hardcoded

### AIService Package Interface

```swift
public protocol AIProvider: Sendable {
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error>
}
```

Swappable: ZhipuProvider now, DeepSeek/OpenAI/通义 later — same protocol.

## Git Workflow (PR-required)

VitalStride uses a **PR-required Git workflow**. Full rationale: [`docs/adr/0009-pr-required-workflow.md`](docs/adr/0009-pr-required-workflow.md) (supersedes ADR-0001). FS/TL command sequences: `AGENTS.md` § Git Workflow.

**One-line summary**: all code reaches `main` only via a GitHub PR that passes the required
checks + review. FS pushes `agent/<issue>-<task>` to `github` and opens a PR; TL merges via
`gh pr merge` after CI is green and the PR is approved.

**Roles**:

| Role | Pushes to | Pushes what |
|------|-----------|-------------|
| FS | `github` | `agent/<issue-key>-<task-id-short>` + opens PR |
| TL | — | merges the PR (`gh pr merge`); never pushes `main` directly |

**Hard rule**: `main` ruleset requires `Lint & policy`, 6× `SPM …`, `App target`, `claude-review`,
and `codex-review` (10 checks total);
direct pushes to `main` are rejected — even for admins. The only path to `main` is a merged PR
whose required checks are green. `pre-commit` also blocks local commits to `main`.

**Conflict policy (B2)**: TL resolves trivial conflicts (different lines, import additions, separate methods, whitespace) inline; semantic conflicts (same line, deletion of changed code, logic-overlap) get reassigned to FS.

## Git Hooks

Git hooks live in `scripts/hooks/` and are activated via `core.hooksPath`. This ensures all git working directories — including agent worktrees under `~/multica_workspaces/` — share the same hooks.

**First-time setup after clone:**
```bash
./scripts/setup-hooks.sh
```

**Hooks:**

| Hook | Purpose |
|------|---------|
| `pre-commit` | Blocks direct commits to `main` / `master`; SwiftLint staged Swift; touched `Packages/<X>` build/test and touched `Prototype` build (fast, no simulator) |
| `pre-push` | Fast package/Prototype validation, touched-line SwiftLint, and layer frontmatter anti-rot. AppUI `xcodebuild` is opt-in via `RUN_XCODEBUILD=1`; required CI owns the default full run |

**Build performance**: default pre-push stays under the agent-run budget. An explicit
`RUN_XCODEBUILD=1 git push` shares `<git-common-dir>/derived-data` and serializes the optional local
app build via the common build lock. The non-optional full AppUI test runs in required CI.

**Fast paths**: touched production packages run `swift build && swift test`; `Prototype` runs
`swift build --package-path Prototype`; pure docs/hooks/scripts changes skip build entirely.
