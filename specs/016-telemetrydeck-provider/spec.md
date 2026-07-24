# Feature Spec — 016 TelemetryDeck Provider (v3.1)

**Parent issue**: MY-1301
**Sub-issues**: MY-1327 (T001 — TelemetryKit adapter product) / MY-1328 (T002 — 三平台 project.yml + 启动接线)
**Constitution refs**: §I 健康隐私 (P0)、§II Swift 6 strict concurrency、§III SPM 优先、§IV XcodeGen 真理之源、§V narrow 例外 (ADR-0011)、§VII 范围克制
**ADR refs**: ADR-0011 (TelemetryDeck 首个生产 provider)、ADR-0012 path B（架构先、SDK 后）**仅 event 通道部分**；**crash/hang 诊断通道已由 ADR-0013 supersede（GlitchTip + sentry-cocoa）**——本 feature **不涉及诊断通道**。
**Version**: v3.1 (2026-07-24, incremental fix over v3: A-3 macOS BSD-grep 不可执行 → 换 `swift package dump-package | jq -e` 结构化断言；repo 内交叉引用改用最终 `spec.md`/`plan.md`/`tasks.md` 文件名)

## 1. Background & Motivation

- ADR-0011 决定 TelemetryDeck 作为首个生产 `TelemetryProvider`；ADR-0012 path B 已在 main 落地纯逻辑：`TelemetryProvider` 协议、`TelemetryDeckProvider` struct、`TelemetryDeckSignalSink` protocol、`TelemetryEvent → TelemetryDeckSignal` 映射 + fake-sink 单测。
- 目前生产运行时**仅**注册 `ConsoleTelemetryProvider`（DEBUG 分支），无远程 provider。缺 SDK adapter + 启动注册 → 生产环境事件全部落地本机 console。
- 诊断通道已由 ADR-0013 迁移到 GlitchTip + sentry-cocoa（spec 015），**本 feature 不承担 diagnostic transport**。`TelemetryProvider.record(_ diagnostic:)` 保留协议默认 no-op 实现，`TelemetryDeckProvider.record(_:)` 已存在的 diagnostic→signal 转发**留在 core 现状**——本 feature 不新增、不测试、不删除该行为；生产层永不给 `TelemetryDeckProvider` 传 diagnostic（GlitchTip 是唯一诊断 transport）。

## 2. In Scope

1. 在 `Packages/TelemetryKit` 新增独立 SPM product **`TelemetryDeckAdapter`**，承载 `import TelemetryDeck`（远程 SDK 依赖）
2. 唯一公开 API — facade：`TelemetryDeckAdapter.makeProvider(appID:) -> any TelemetryProvider`
3. Internal `TelemetryDeckSDKSink: TelemetryDeckSignalSink` + internal `init(dispatch:)` seam（生产走真 SDK，测试注入 fake collector）
4. Internal `makeProvider(appID:sink:)` overload（**internal only**）——facade round-trip 测试通过它注入 fake sink，从**真 facade 返回的 provider** 调 `track(_:)`，断言 signal 抵达 fake
5. `Packages/TelemetryKit/Tests/TelemetryDeckAdapterTests/` — **facade round-trip** + sink 单元测试
6. 三平台 app target（iOS / macOS / watchOS）依赖 `TelemetryDeckAdapter` product；`project.yml` 三处 `settings.base` 注入 `INFOPLIST_KEY_TelemetryDeckAppID: "$(TELEMETRY_DECK_APP_ID)"`（利用现有 `GENERATE_INFOPLIST_FILE: true` 基线，**不新增物理 Info.plist**）
7. 三个 `*App.swift` 启动分支：DEBUG → `ConsoleTelemetryProvider`；非 DEBUG → 读 `Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID")` → `TelemetryDeckAdapter.makeProvider(appID:)` → `TelemetryService.shared.register(...)`
8. `specs/016-telemetrydeck-provider/{spec.md, plan.md, tasks.md}` — 归 T001 提交（内容 = 本 v3.1 附件，落库时去掉 `-v3.1` 后缀）

## 3. Out of Scope (explicit)

- **诊断通道（crash/hang）任何改动**——由 ADR-0013 / spec 015 承担；本 feature 不测试、不引用 `TelemetryDeckProvider.record(_:)` 的现有行为；`TelemetryDiagnostic → diagnostic_*` signal 不出现在 acceptance
- `TelemetryProvider` 协议签名（含 `record(_ diagnostic:)` 默认实现）
- `TelemetryDeckSignal` 现有 public API（含 free-string init）—— core layer 冻结
- `TelemetryDeckProvider` / `TelemetryDeckSignalSink` 现有 public 类型（core layer 冻结）
- 埋点调用点（`TelemetryService.shared.track(...)` / `Telemetry.*`）
- MetricKit / sentry-cocoa / GlitchTip 相关代码
- CI 中 `TELEMETRY_DECK_APP_ID` 环境注入（属 CI infra 工单，本 PR 只落配置协议）

## 4. Typed-Event Boundary

现实基线：`TelemetryKit` core 已 export 的 public API（`TelemetryDeckSignal(signalType:parameters:)` free-string init、`TelemetryDeckProvider(sink:)`、`TelemetryDeckSignalSink`）**保持不变**——本 feature 不改任何 core layer 类型可见性。

typed-event-only 的**新增强制点**在 adapter product 的 public 面：
- `TelemetryDeckAdapter` product **只 export 一个 public 符号**：`enum TelemetryDeckAdapter` + `static func makeProvider(appID:) -> any TelemetryProvider`
- 真 SDK sink (`TelemetryDeckSDKSink`)、dispatch seam (`init(dispatch:)`)、round-trip overload (`makeProvider(appID:sink:)`) **均 internal**
- 外部包（三个 app target）**只能拿到** `any TelemetryProvider`——它只有 `track(TelemetryEvent)` 和 `record(TelemetryDiagnostic)` 两个方法，均为封闭类型
- 结论：外部**无路径**通过 adapter product 拿到 free-string transport；core 现存的 `TelemetryDeckSignal.init(signalType:parameters:)` 仍是 public，但**没有生产代码调用点**（本 PR 保证零新增调用点）

## 5. Functional Requirements

- **FR-1**：`TelemetryDeckAdapter.makeProvider(appID: String) -> any TelemetryProvider` 返回一个真实 `TelemetryDeckProvider`，其 sink 为 `TelemetryDeckSDKSink`（生产默认 dispatch = `TelemetryDeck.signal(_:parameters:)`）
- **FR-2**：`TelemetryDeckSDKSink` 是 internal `Sendable` struct，构造器 `init(dispatch: @escaping @Sendable (String, [String: String]) -> Void = { s, p in TelemetryDeck.signal(s, parameters: p) })`；生产走默认参数，测试注入 fake
- **FR-3**：Internal overload `TelemetryDeckAdapter.makeProvider(appID: String, sink: any TelemetryDeckSignalSink) -> any TelemetryProvider`——生产 public overload 内部委托到此 overload 并传入默认 SDK sink；facade round-trip test 直接用这个 overload 注入 fake sink，走 **facade → provider → sink → dispatch** 全链
- **FR-4**：`Packages/TelemetryKit/Package.swift` 声明 `.package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")`（FS 按 SPI 现行 major pin）；核心 `TelemetryKit` target dependencies 保持 `[]`（constitutional）；SDK 依赖仅落新 target `TelemetryDeckAdapter`
- **FR-5**：`project.yml` 三个 app target 的 `settings.base` 追加 `INFOPLIST_KEY_TelemetryDeckAppID: "$(TELEMETRY_DECK_APP_ID)"`；三处 dependencies 追加 `TelemetryDeckAdapter` product；`xcodegen generate` → commit 生成的 `.xcodeproj`；**不新增物理 Info.plist**
- **FR-6**：三个 `*App.swift` init 遵循对称模式；`import TelemetryDeckAdapter` 新增；DEBUG 分支不变；非 DEBUG 分支 `Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String` → 非空则调 facade 拿 provider → `Task { await TelemetryService.shared.register(provider) }`
- **FR-7**：Package tests 4 条硬断言（executable，见 §7）；facade round-trip 至少 1 条（§7 A-T1）

## 6. Non-Functional Constraints

- Swift 6 strict concurrency：所有新类型 `Sendable`；`dispatch` closure `@Sendable`；禁用 `@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)`
- 三平台构建（iOS / macOS / watchOS）——本仓库约定 `generic/platform=*` destination（AGENTS.md）
- 零健康数值 / 零 PII 逃逸：typed-event-only 由 adapter public 面收紧到 facade，生产无 free-string 调用点（`git grep` 断言）
- DEBUG 不发（ADR-0011 §Decision.2）

## 7. Executable Acceptance Probes（v3.1 权威列表 — 与 tasks.md 和 MY-1327/MY-1328 DoR 逐字一致）

**执行位置**：Multica daemon 提供的 `<task-dir>/workdir/` — 仓库根；**禁 `cd`**。所有断言使用可执行形式（预期为空的用 `!`，avoid exit-1 假失败）。**目标环境 = macOS BSD grep + Swift toolchain + jq**。

### T001 (MY-1327) probes — 全部在 workdir 根执行

```
# A-1 build
swift build --package-path Packages/TelemetryKit

# A-2 test
swift test --package-path Packages/TelemetryKit

# A-3 核心 TelemetryKit target 依赖仍为空数组（constitutional）— 结构化断言，macOS BSD grep 兼容
swift package dump-package --package-path Packages/TelemetryKit \
  | jq -e '.targets[] | select(.name == "TelemetryKit") | (.dependencies | length == 0)'

# A-4 Adapter product 唯一 public 符号：只 enum 声明 + facade func
[ "$(grep -rnE '^[[:space:]]*public ' Packages/TelemetryKit/Sources/TelemetryDeckAdapter/ | wc -l | tr -d ' ')" = "2" ]

# A-5 sink 与 dispatch seam 保持 internal（预期为空）
! grep -rnE '^[[:space:]]*public[[:space:]]+.*TelemetryDeckSDKSink' \
     Packages/TelemetryKit/Sources/TelemetryDeckAdapter/
! grep -rnE '^[[:space:]]*public[[:space:]]+init\(dispatch:' \
     Packages/TelemetryKit/Sources/TelemetryDeckAdapter/

# A-6 无并发规避
! grep -rnE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     Packages/TelemetryKit/Sources/TelemetryDeckAdapter/

# A-7 spec/plan/tasks 三文件到位
[ -f specs/016-telemetrydeck-provider/spec.md ] \
  && [ -f specs/016-telemetrydeck-provider/plan.md ] \
  && [ -f specs/016-telemetrydeck-provider/tasks.md ]
```

**Test suite (`TelemetryDeckAdapterTests`) 硬断言（`swift test` 通过即视为满足）**：

- **A-T1 facade round-trip（P1-I）**：`@testable import TelemetryDeckAdapter`；构造 fake sink（`FakeSink: TelemetryDeckSignalSink`，`send(_:)` 追加到 `signals: [TelemetryDeckSignal]`），调 internal overload `TelemetryDeckAdapter.makeProvider(appID: "test", sink: fake)`，调 `provider.track(.workoutStarted(source: "test"))`，`XCTAssertEqual(fake.signals, [TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "test"])])`
- **A-T2 facade round-trip 参数化事件**：同上 fake 注入，`provider.track(.aiInsightGenerated(durationMs: 42, cardCount: 3))` → `signals == [TelemetryDeckSignal(signalType: "ai_insight_generated", parameters: ["duration_ms": "42", "cards": "3"])]`
- **A-T3 SDK sink dispatch seam**：`TelemetryDeckSDKSink(dispatch: { s, p in captured = (s, p) }).send(TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "unit"]))` → `captured == ("workout_started", ["source": "unit"])`
- **A-T4 public facade 生产 overload 可被外部构造**：`let provider: any TelemetryProvider = TelemetryDeckAdapter.makeProvider(appID: "test")`；调 `provider.track(.workoutDiscarded)` 不抛不 crash（SDK 已初始化）——本条不注入 fake，验证生产入口不因 SDK 初始化姿态在测试环境失败

### T002 (MY-1328) probes — 全部在 workdir 根执行

```
# B-1 XcodeGen 无警告
xcodegen generate

# B-2 iOS build
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

# B-3 macOS build
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStrideMac \
  -destination 'generic/platform=macOS' -skipPackagePluginValidation

# B-4 watchOS build
xcodebuild build -project VitalStride.xcodeproj -scheme 'VitalStrideWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' -skipPackagePluginValidation

# B-5 Info-plist key 名字面量出现在 3 个 App.swift（配置协议允许）
[ "$(grep -rn '"TelemetryDeckAppID"' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]

# B-6 project.yml 中 INFOPLIST_KEY_TelemetryDeckAppID 值严格等于占位符（禁真实 App ID）
[ "$(grep -cE '^[[:space:]]*INFOPLIST_KEY_TelemetryDeckAppID:[[:space:]]*"\$\(TELEMETRY_DECK_APP_ID\)"[[:space:]]*$' project.yml)" = "3" ]

# B-7 无其它对 TELEMETRY_DECK_APP_ID 的赋值（禁把值 hardcode 进 project.yml）
!  grep -nE 'TELEMETRY_DECK_APP_ID[[:space:]]*[:=][[:space:]]*"[^"]*[^)]"' project.yml

# B-8 三处 App.swift 均具备 DEBUG Console / else facade 对称结构
[ "$(grep -rn 'TelemetryDeckAdapter\.makeProvider' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]
[ "$(grep -rn 'ConsoleTelemetryProvider' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]

# B-9 零埋点调用点侵入 — 用 github merge-base（正确的权威 remote）
git fetch github main
!  git diff github/main...HEAD -- '*.swift' \
     | grep -E '^\+.*(TelemetryService\.shared\.track\(|Telemetry\.(track|record))'

# B-10 未新增物理 Info.plist（检查文件路径，而不是 grep 文件内容）
!  git diff --name-only --diff-filter=A github/main...HEAD | grep -E '(^|/)Info\.plist$'

# B-11 无并发规避
! grep -rnE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources'
```

## 8. Rollout & Verification

- T001 → T002 stage 依赖（stage 1 → stage 2）；MY-1327 完成后 TL 提升 MY-1328 backlog → todo
- 三平台 build 通过 + package test 通过 → 视为 feature 完成
- CI 中 `TELEMETRY_DECK_APP_ID` 环境注入是独立工单（本 PR 不承担）

## 9. Source-of-truth pointers

- MY-1327 T001 DoR（本 spec §7 T001 probes 逐字复制到 acceptance）
- MY-1328 T002 DoR（本 spec §7 T002 probes 逐字复制到 acceptance）
- `tasks.md`（本 spec §7 逐字复制到每个 task 的 verification 段）
- 本 spec 与 `plan.md` / `tasks.md` **同 feature 目录并列**：`specs/016-telemetrydeck-provider/{spec.md, plan.md, tasks.md}`
- 三附件命名（v3.1 handoff comment 上）：`spec-v3-1.md` / `plan-v3-1.md` / `tasks-v3-1.md`（唯一标识，避免与 v1/v2/v3 混淆）；落库时去掉版本后缀 → `spec.md` / `plan.md` / `tasks.md`
