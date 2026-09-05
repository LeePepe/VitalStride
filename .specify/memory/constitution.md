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
| DesignKit | 设计语言：seed 配色 token（Seed/PrimaryPalette/Theme）+ SwiftUI 组件 | — |

**规则**：
- App target 不互相依赖，只依赖 packages。
- App production/test/XcodeGen 真理源归 `AppUI`；repository automation/config 归 `RepoInfra`。
  `Prototype` 与 6 个 package layer 补齐其余 schedulable paths；治理/support 与 generated/cache/log/local-secret
  路径显式排除。ownership 与 gate speed 正交（ADR-0018、ADR-0019）。
- 新 AI provider = 在 `AIService` 实现 `AIProvider` 协议，不新建包。
- 改动仅涉及 `Packages/<X>/` 时，**必须**用 `swift build && swift test` 验证；禁止用 xcodebuild（慢且无意义）。
- 新增 package 需 ADR 并更新 `project.yml` + 本宪法表格。

参考：ADR-0004 (本地 SPM 包拆分)、ADR-0007 (TelemetryKit 独立包)、ADR-0008 (DesignKit 设计系统包)。

### IV. XcodeGen 是配置真理之源 (NON-NEGOTIABLE)

`project.yml` 是 Source of Truth；`VitalStride.xcodeproj/project.pbxproj` 是生成物。

- 任何长期 build setting（DEVELOPMENT_TEAM、签名、entitlements、target 配置）**必须**落在 `project.yml`。
- 禁止在 Xcode UI 改设置——任意 `xcodegen generate` 都会 reset。
- 改动 target 配置后必须 `xcodegen generate` 并 commit `.xcodeproj` 同步变更。
- 测试目录用目录源引用，新增测试文件无需 pbxproj 手动维护。

参考：vitalstride skill §"Xcode 项目配置"（账户/team reset 反复教训）。

### V. AI 用本地优先 + 国内 fallback，无第三方 SDK

AI provider chain：**Apple Intelligence Foundation Models 优先**（On-device, iOS 18.1+），**智谱 GLM-4-Flash fallback**（OpenAI-compatible REST via URLSession）。

- 禁止引入 OpenAI/Anthropic/Google **AI** SDK 等第三方包。
- API key 仅存 Keychain，不得硬编码。
- 新增 provider = 在 `AIService` 实现 `AIProvider` 协议接入 chain，不替换。
- **Telemetry 例外（narrow）**：允许引入**隐私合规的第三方 telemetry SDK**，当前限**自建 Aptabase**（开源 aptabase-swift SDK，上报到项目所有者掌控的自建实例，数据不离自有基础设施），且只能作为 `TelemetryProvider` 消费强类型 `TelemetryEvent`（DEBUG 不发、self-hosted host 注入、只发 count/duration/标识符）；§I 健康隐私红线对该 provider 全额适用，不得引入任何接受自由字符串 / 原始健康数值的 API。AI provider 的「无第三方 SDK」约束不变。原 TelemetryDeck（EU 托管 SaaS）已被 ADR-0015 取代——自建 Aptabase 满足 ADR-0011 预留的「data-never-leaves-own-infra → 迁移自建后端」触发条件，实际**收紧**隐私姿态。详见 [ADR-0015](../../docs/adr/0015-aptabase-self-hosted-analytics.md)（supersede [ADR-0011](../../docs/adr/0011-telemetrydeck-first-production-provider.md)）。
- **诊断通道例外（narrow）**：崩溃 / 挂起（hang）诊断由 **Apple MetricKit** 采集。原 ADR-0012 的「经 TelemetryDeck 通道自研上报」**已被 ADR-0013 取代**——改用**自建 GlitchTip**（部署在项目所有者掌控的 Azure，数据不离自有基础设施）+ 官方 **sentry-cocoa** SDK（`enableMetricKit=true`，GlitchTip 说 Sentry 协议）。此为对「AI 无第三方 SDK / telemetry 仅限 TelemetryDeck」的第二个 narrow 例外，**仅**允许 sentry-cocoa、**仅**用于崩溃/hang 诊断、**仅**上报到自建 GlitchTip。§I 健康隐私红线由**强制 `beforeSend` 钩子**守门（剥离/拒绝任何可能含健康数值或 PII 的字段，仅放行崩溃栈 + 粗粒度设备元数据），钩子过滤逻辑抽为纯函数配单测锁死。DEBUG 不发。产品分析（`TelemetryEvent`）路径不受影响、仍无生产 remote provider。详见 [ADR-0013](../../docs/adr/0013-self-hosted-glitchtip-sentry-cocoa.md)（supersede [ADR-0012](../../docs/adr/0012-metrickit-diagnostics-via-telemetrydeck.md) 崩溃通道）。

参考：ADR-0005 (AI ProviderChain)、ADR-0011 (TelemetryDeck 首个生产 telemetry provider)、ADR-0012 (MetricKit 诊断 typed 通道)、ADR-0013 (自建 GlitchTip via sentry-cocoa)。

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
- **例外（ADR-0010）**：watchOS 实时心率训练流程（Watch `HKWorkoutSession` + `WatchConnectivity` 把实时心率推给 iOS active-workout）已被显式 promote，属 ADR-0002 的 narrow 例外，可立项。此例外仅限该实时心率路径；其余 watchOS/macOS 专属 feature 仍冻结。
- 重启其它 watchOS/macOS 专属 feature 需新 ADR（推翻或再开 ADR-0002 例外）。

参考：ADR-0002 (deferred watchOS / macOS feature work)、ADR-0010 (promote watchOS live heart-rate)。

---

## Module Architecture

```
AppUI (iOS / macOS / watchOS / widget + app tests/config)
    │  仅含入口、平台 UI、Live Activity widget
    ↓
VitalUI ←── VitalModels
    │            ↑
    ↓            │
HealthKitService ┘
    AIService    (独立, 无依赖)
    TelemetryKit (独立, 无依赖)
    DesignKit    (独立, 无依赖 — 设计系统 token + 组件)

RepoInfra (独立：CI/workflow/hooks/tooling/release/repo policy；无 product dependency)
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

### Git: PR-Required Workflow (NON-NEGOTIABLE)

| 角色 | 责任 | 证据/交付 |
|------|------|-----------|
| Fullstack (FS) | 实现、提交、在 exact revision 前发布候选 PR，随后更新 PR 直到 exact review 通过 | `agent/<issue-key>-<task-id-short>` + `gh pr create` / `gh pr edit` |
| AI Reviewer | 审查 exact revision 与规划/DoR 产物 | PR / planning review verdict |
| PR Manager | 负责 final readiness、required-check 监督、merge/cleanup 与 shipping handoff | PR merge state + final shipping conclusion |
| Team Lead (TL) | 负责 readiness 接受、调度、恢复、Owner escalation、生命周期关闭与 issue/workdir 失败-闭合 | issue status / recovery evidence |

所有代码只能经 PR 进 `main`。当前 Dev Team contract（[ADR-0021](../../docs/adr/0021-current-dev-team-delivery-contract.md)）要求：Team Lead 只管理 readiness / 资源 / 恢复，不在正常 shipping 流程中代替 PR Manager merge；Fullstack 只在 exact review 前发布候选 PR，真正的 shipping 由 PR Manager 承担。`main` 受 **ruleset**（`main protection`，active）保护：**required status
checks** = `Lint & policy` + 6× `SPM …` + `App target` + **一个 Codex required AI
review**。Claude review 暂停；Kimi review 是 advisory-only，findings 或不可用均不满足也不阻塞
required gate。Codex 控制面须按 [ADR-0020](../../docs/adr/0020-codex-required-kimi-advisory.md)
迁移到由默认分支评估的 `pull_request_target` workflow。`scripts/hooks/pre-commit` 禁止直接 commit 到
main；`pre-push` 只跑 agent-run-safe 的轻量门禁，分钟级 AppUI `xcodebuild` 由 required CI
不可绕过地执行（本地完整验证由 FS 按风险决定）。详见 [ADR-0009](../../docs/adr/0009-pr-required-workflow.md)、[ADR-0018](../../docs/adr/0018-formal-appui-change-owner-layer.md)、[ADR-0021](../../docs/adr/0021-current-dev-team-delivery-contract.md)、AGENTS.md §Git Workflow。

### Commit Message 约定

- **Agent 分支**：每个 commit **建议**含 `MY-\d+`（issue key），subject 或 body 任一位置（约定，
  非强制 —— pre-push 的 MY-key 强制已移除，见 commit `13505cd`）。
- **工程改动 commit**：用 `chore(...)` / `docs(...)` / `ci(...)` 前缀，无 issue key 时加
  `(retro A-XX)` 占位以保留追溯。
- 历史教训：2026-06 retro 发现 92% commit 缺 issue key —— 保留 MY-key 约定以维持可追溯。

### Build & Test Gate

- **Packages/ 仅改动** → `swift build && swift test`（per package）
- **AppUI 改动** → required CI 执行 `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation`
- **RepoInfra 改动** → 本地运行 `bash scripts/test-repoinfra.sh`；不触发 app xcodebuild
- 本地 AppUI 完整验证可选：直接运行上条命令，或 `RUN_XCODEBUILD=1 git push`
- pre-push hook 自动选择 fast path（production SPM build/test；Prototype build；AppUI 重验证 deferred to CI）
- support-only docs 改动 skip build；RepoInfra 路径走上述 fast validation

### 平台 Deployment Target

- iOS 18.0 / macOS 15.0 / watchOS 11.0（`project.yml options.deploymentTarget`）
- 降级需新 ADR + 全 package compatibility 审查

### Issue Tracker / Spec Execution

- **Multica** 项目 UUID `7adf8b88`，issue prefix `MY-*`
- 每个 issue 标题 `[T###] [Story] Brief description`（spec-kit handoff 约定）
- Hermes 端写 spec/plan/tasks，**`/speckit-implement` 不使用**——tasks.md 通过 `multica-quick-issue` 批量入 Multica，`TL → Planner → FS → Reviewer` pipeline 执行
- 每 feature 一个 Multica project（不要 phase 多项目）

### Planning Review / Dual-Approval Gate（ADR-0014）

- **Planner Lead** 对 spec-driven feature 做拆分 / DoR 补全后，**下游 stage 派发前**须过
  **AI Reviewer + Team Lead 双批准门**：两方都 ✅ 才派发；任一方 🟡 CHANGES REQUESTED → 回 Planner
  Lead 修订。批准后由 **TL** 派发（Planner / Reviewer 均不自行派发）。
- AI Reviewer 承担两类 review：**code review**（PR）+ **planning / DoR review**（Planner 产出）。
  规划审的 finding 源同为 §Cross-Cutting Quality Bars。
- DoR 硬合同（派发前必备）：`Files in scope` / `Files NOT to touch` / `Public signatures` /
  `Functional acceptance criteria`（≥3 可验证）/ `Verification command`（精确 + 工作目录）。
- **Planner 不内联实现级代码（红线）**：spec/plan/tasks 只写**契约级描述**（要 seed 什么、触发什么、断言什么），
  **禁止**内联「必须能编译」的 Swift 片段（具体 `init` 标签、枚举 case、fixture 字面量等）。这类实现细节留给
  GREEN 阶段由编译器兜底。理由：一旦计划写死可编译代码，规划审就被迫**当编译器**逐行验（错 `init` 标签、
  不存在的枚举 case……），把本可一次自查的编译级事实拆成多轮递归 finding。若确需示意，用**非编译**伪码并显式标注
  `// 示意，非最终签名`。
- **写前核验源码（红线）**：Planner 引用任何具体符号（类型 / `init` 签名 / 枚举 case / 方法名）前，
  必须先 `grep`/`git show` 对着真实源码确认存在，**不得凭记忆写**。规划审对「符号是否存在」应一次性全量核验，
  不做增量式逐个抓（类比编译器一次列出所有 error，而非修一个报一个）。
- 设计期 `check-tasks-fresh` 防腐 + TL sync-check 仍生效；规划审是其上的额外质量 pass，非替代。
- bug-fix fast-path（TL 直接拆，无 Planner 产出）不强制走规划审。详见 [ADR-0014](../../docs/adr/0014-restore-planner-review-dual-approval.md)。

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
- **K. 视觉验收用模拟器 snapshot，不写死真机**：纯视觉改动（token 迁移、配色 / 圆角 / 间距 / 字号、无逻辑变更）的
  before/after 验收，**默认标准 = iPhone Simulator（如 iPhone 16）light/dark 截图或 SnapshotTesting 用例**，非真机。
  验收门（spec/tasks 的 acceptance criteria）**禁止**对纯视觉改动写死 "real-device / 真机" 要求——runtime 无可达
  物理设备时会造出「任何 agent 都过不去、只能永远升级 human」的死结（历史教训：MY-1352 键盘迁移卡在真机截图门，
  PR 早已 green CI merge 仍无法收口）。真机验收仅保留给**模拟器测不了**的能力：触觉反馈、传感器、后台唤醒、
  真机性能 / 热。先例：`specs/017-add-set-button-redesign` AC-M1 = iPhone 16 Simulator before/after，是纯视觉改动的正确模板。

### P2 — Nice to Have (ℹ️，never blocks merge)

- 风格、注释优化、命名建议。

### J — Ship-Gate Failure Classification

Ship gate（required CI 的 `App target` / `SPM …`）失败时，PR Manager **必须**先判定失败是否由当前 patch 引入。AI Reviewer 只审内容，不执行或判断 build/test/lint/hook/CI gate；TL 仅处理证据冲突、恢复和升级：

- **Patch-induced**：失败 test 文件 ∈ `git diff github/main...HEAD --name-only`，或失败 test 所属 module 有源码改动 → 阻止 shipping，由 PR Manager 带证据直接请求 FS 修复
- **Pre-existing flake**：失败 test 与当前 patch 无源码关联 → 不改变 AI Reviewer 的内容 verdict；由 PR Manager 走 AGENTS.md §Pipeline Recovery → Quarantine 路径

把 gate state 写进 AI Reviewer verdict，或让 Reviewer/TL 代替 PR Manager 监督 CI，均为职责边界违规。

### Verdict Aggregation

- 任意 P0 → 🔴 FAIL
- 无 P0 + 有 P1 + **功能正确** → 🟢 PASS WITH FOLLOW-UP（拆 sub-issue，当前 PR 立即 merge）
- 无 P0 + 有 P1 + **功能 broken** → 🟡 CHANGES REQUESTED（回 FS）
- 仅 P2 / 无 finding → 🟢 PASS

---

## Pipeline Recovery Protocols

> Pipeline 失败时 agent 行为的宪法级约束。具体命令实现见 `AGENTS.md` §Pipeline Recovery。

### PR-1: 禁止 `human_triage` 作为常规状态

`waiting_on=human_triage` 仅在以下场景允许：
- Constitution P0 违规需人判断（例如隐私越界争议、范围争议）
- 自动恢复（Hermes）尝试 3 次后仍 fail 同一根因

其它 infra failure（CLI routing、runtime crash、quarantined flake、限流、网络）一律 Hermes auto-dispatch，TL **禁止**直接打 `human_triage` 标。

### PR-2: Sub-issue 幂等

Planner Lead / TL 创建 sub-issue 前必须查同 parent 的 alive (`todo`/`in_progress`/`in_review`/`blocked`) sub-issue；若 Scope 重合（同 Branch / 同 title trim / files ≥80% 重合）→ 复用而非新建。重复创建 sibling = 宪法违规。

历史教训：MY-857 / MY-859 / MY-999 三胞胎，同一 scope 三条独立 issue 同时被 dispatch，导致并行修改冲突 + run-count 浪费。

### PR-3: Run-Count Guard 区分 `run_attempts` vs `infra_failures`

- `run_attempts`：code-review iterate、patch-induced 测试失败（计 budget，默认 15）
- `infra_failures`：CLI 错误、runtime crash、quarantined flake、auth/network（不计 budget）

把 infra failure 计入 `run_attempts` 浪费 budget 并提早 stall pipeline = 宪法违规。

### PR-4: Ship-Gate Failure Classification

参见 Cross-Cutting Quality Bars §J。

### PR-5: Startup Scan

TL 每次 pipeline 起手前必须扫描：
- `gh pr list --state open`：PR 工作流下 open PR 是正常状态 —— TL 应 review 并推进（CI 绿 +
  review 后 `gh pr merge`），而非视为违规。长时间停滞的 PR 需 comment 跟进。
- 同 parent alive sub-issue（PR-2 前置）

## Governance

本宪法管辖 VitalStride 所有开发工作。所有 AI/人类贡献者（FS/TL/Reviewer，含 Codex/Claude/Hermes 子代理）必须读取并遵守。

- 任何与本宪法冲突的 PR 必须修改 PR 或修宪法（先 ADR）。
- **修改宪法**：新 ADR + 本文件 patch + 版本 bump + 在 PR 描述 link 到 ADR。
- 版本规则（语义化）：
  - MAJOR — 删除/反转原则；MINOR — 新增原则/新 Quality Bar；PATCH — 文字澄清不改语义
- 与本宪法相关：AGENTS.md（agent 操作手册）、CONTEXT.md（数据架构细节）、`docs/adr/`（决策档案）、`scripts/hooks/`（强制规则机器实现）。

**Version**: 3.0.0 | **Ratified**: 2026-06-25 | **Last Amended**: 2026-08-26

> 2.7.2（PATCH，补齐 schedulable ownership）：新增独立 `RepoInfra` change-owner layer，覆盖
> repository automation/config，并以 machine-readable support/generated exclusions 划清非 schedulable
> artifacts；path checker 对 unmapped 与 overlap fail closed。ownership 与 gate speed 继续正交，
> AI Reviewer/PR Manager 职责不变（[ADR-0019](../../docs/adr/0019-formal-repoinfra-change-owner-layer.md)）。

> 2.7.1（PATCH，正式化既有边界）：app production/test/build-config 路径归入一个跨平台
> `AppUI` change-owner layer，隔离的视觉原型归 `Prototype` layer；明确 layer ownership 与 gate
> speed 正交，AppUI 分钟级完整验证默认由 required CI 执行，本地运行由 FS 按风险决定
> （[ADR-0018](../../docs/adr/0018-formal-appui-change-owner-layer.md)）。

> 3.0.0（MAJOR，required AI review policy）：暂停 Claude required review；Codex 成为唯一 required AI gate；新增 tool-less Kimi K3 advisory review。Codex workflow 以两阶段 bootstrap 迁移到 `pull_request_target`，Kimi findings/故障均不参与 merge gate（[ADR-0020](../../docs/adr/0020-codex-required-kimi-advisory.md)）。

> 2.7.0（MINOR，新增 Quality Bar K + 收紧 DoR 硬合同）：两条 pipeline 质量改进，源自 MY-1369 规划递归与 MY-1352 真机门死结的复盘。(1) **DoR 硬合同**新增两条红线——Planner 不内联实现级可编译代码（只写契约级描述，实现细节留 GREEN 由编译器兜底）、引用符号前须 `grep`/`git show` 核验存在（规划审一次性全量核验，不做增量逐个抓）；修正 planner 把编译级自查外包给 reviewer、导致 R4/R5 逐轮抓 `init` 标签 / 枚举 case 的递归浪费。(2) **Quality Bar K**：纯视觉改动的 before/after 验收默认走 iPhone Simulator light/dark 截图或 SnapshotTesting，禁写死真机；修正 keyboard stage 因 runtime 无真机造出的「永远升级 human」死结。同步收紧 AGENTS.md 的 human 升级措辞与 Planner Lead 职责行（[ADR-0017](../../docs/adr/0017-planning-code-inlining-and-visual-acceptance-gates.md)）。

> 2.6.0（MINOR，§V telemetry provider 换自建后端）：产品分析 provider 由 **TelemetryDeck**（EU 托管 SaaS）换为**自建 Aptabase**（开源 aptabase-swift SDK，上报到所有者掌控的自建实例，数据不离自有基础设施）。narrow 例外仍限一个隐私合规 SDK、只作 `TelemetryProvider` 消费强类型 `TelemetryEvent`、DEBUG 不发；§I 全额适用。触发自 ADR-0011 自列的 revisit trigger「data-never-leaves-own-infra → 迁移自建后端」，实际**收紧**隐私姿态（[ADR-0015](../../docs/adr/0015-aptabase-self-hosted-analytics.md) supersede [ADR-0011](../../docs/adr/0011-telemetrydeck-first-production-provider.md)）。诊断通道（GlitchTip/sentry-cocoa）不受影响。

> 2.5.0（MINOR，新增 pipeline stage）：恢复 **Planner Lead 规划 / DoR 复审** + 建立
> **AI Reviewer + Team Lead 双批准门**——spec-driven feature 的拆分 / DoR 补全在下游派发前须两方都
> 批准。修正此前 AI Reviewer prompt 单方写入的「Plan/Decomposition Review removed」与宪法
> pipeline 描述的冲突。AI Reviewer 承担 code review + planning/DoR review 两类，finding 源同为
> §Cross-Cutting Quality Bars；设计期 `check-tasks-fresh` + TL sync-check 仍生效
> （[ADR-0014](../../docs/adr/0014-restore-planner-review-dual-approval.md)）。

> 2.4.0（MINOR，§V 增第二个 narrow 例外）：崩溃/hang 诊断改用**自建 GlitchTip**（部署在所有者掌控的 Azure，数据不离自有基础设施）+ 官方 **sentry-cocoa**（`enableMetricKit=true`），取代 ADR-0012 的自研 TelemetryDeck 通道。narrow 例外仅限 sentry-cocoa、仅崩溃/hang、仅上报自建 GlitchTip；§I 由**强制 `beforeSend` 钩子**守门（纯函数配单测）；DEBUG 不发。触发自 ADR-0011 revisit trigger「data-never-leaves-own-infra → self-hosted backend」（[ADR-0013](../../docs/adr/0013-self-hosted-glitchtip-sentry-cocoa.md) supersede ADR-0012 崩溃通道）。产品分析路径不变。

> 2.3.0（MINOR，收窄 §V telemetry 例外）：崩溃 / 挂起诊断由 **Apple MetricKit** 采集、经**同一** TelemetryDeck 通道上报（不引第二个 SDK）；「typed-event-only」收窄为允许一个封闭的 `TelemetryDiagnostic` 诊断通道（provider 新增 `record(_:)` sink），栈经 `DiagnosticSanitizer` 强制清洗、§I 全额适用（[ADR-0012](../../docs/adr/0012-metrickit-diagnostics-via-telemetrydeck.md)）。触发自 ADR-0011 自列的 revisit trigger：TestFlight-only app 的所有 Apple 自动诊断管道为空。

> 2.2.0（MINOR，放松 §V 约束）：允许**隐私合规的第三方 telemetry SDK**（narrow 例外，当前限 TelemetryDeck，只能作为 `TelemetryProvider` 消费强类型 `TelemetryEvent`），回答 ADR-0007 遗留的「first real provider」决策（[ADR-0011](../../docs/adr/0011-telemetrydeck-first-production-provider.md)）。§V 的 AI provider「无第三方 SDK」约束与 §I 健康隐私红线均不变。

> 2.1.0（MINOR，放松 §VII 约束）：watchOS 实时心率训练流程被显式 promote 为 ADR-0002 的 narrow 例外（[ADR-0010](../../docs/adr/0010-promote-watchos-live-heart-rate.md)）。companion-first 与「promote 须 ADR」的门槛不变，§I 隐私红线对该路径全额适用。

> 2.0.0（MAJOR，反转原则）：Git 工作流由 no-PR 反转为 PR-required（[ADR-0009](../../docs/adr/0009-pr-required-workflow.md) supersede ADR-0001）。`main` 改由 branch protection（6 required checks + 1 review + enforce_admins）强制，替代已移除的 pre-push main-only / MY-key 强制。
