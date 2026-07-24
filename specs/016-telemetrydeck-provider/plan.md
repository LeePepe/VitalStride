# Implementation Plan — 016 TelemetryDeck Provider (v3.1)

**Parent**: MY-1301 | **spec**: `spec.md` (in same feature dir) | **tasks**: `tasks.md` (in same feature dir)
**Version**: v3.1 (2026-07-24, incremental fix over v3: A-3 换 `swift package dump-package | jq -e`；repo 内交叉引用改用最终 `spec.md`/`plan.md`/`tasks.md` 文件名)

## 1. Approach

**单 layer 拆分**（TL 已批准）：
- **T001 (MY-1327)** = TelemetryKit layer 内新增 `TelemetryDeckAdapter` product（含 SDK 依赖 + facade + internal SDK sink + facade round-trip 测试）+ 提交 `specs/016-telemetrydeck-provider/{spec,plan,tasks}.md`（唯一权威 artifact owner）
- **T002 (MY-1328)** = 三个 app target 层（非 SPM package layer）：`project.yml` 依赖与 Info-plist 键、`.xcodeproj` 重生成、三个 `*App.swift` 启动接线

两 task 有 stage 依赖（T001 提供 `TelemetryDeckAdapter` product → T002 才能 `import TelemetryDeckAdapter`）。

## 2. Working Directory & Verification Model

FS 在 Multica daemon 提供的 **`<task-dir>/workdir/`** 内工作。所有命令使用**仓库根相对路径**，禁 `cd ~/Development/VitalStride` 或 `git checkout` 在用户主 checkout（AGENTS.md Read Contract）。

**权威 remote = `github`**（`git remote -v` 唯一 remote 是 `github`）。所有 diff 使用：

```
git fetch github main
git diff github/main...HEAD -- '<patterns>'
```

`main` 本地分支可能不存在或陈旧，不使用。

**目标 shell 环境 = macOS BSD grep + Swift toolchain + jq**：所有 `grep` 使用可执行的 BSD-兼容 POSIX 语法（不使用 `-P` PCRE）；结构化断言使用 `swift package dump-package | jq -e`。

## 3. SPM-only Hook 触发分析

`~/.claude/hooks/block-xcodebuild-on-packages-only.sh` 仅在 diff **全部路径** 匹配 `^Packages/` 时阻断 `xcodebuild`。
- T001 diff = `Packages/TelemetryKit/**` + `specs/016-telemetrydeck-provider/**`（非 Packages-only）→ hook 不触发；正确验证仍是 `swift build/test --package-path`（constitutional §III）
- T002 diff = `project.yml` + `.xcodeproj` + `Sources/*App.swift`（无 `Packages/` 变更）→ hook 不触发；正确验证是三平台 `xcodebuild build`（constitutional §IV）

## 4. Task Boundaries

### T001 owns
- `Packages/TelemetryKit/Package.swift`
- `Packages/TelemetryKit/Sources/TelemetryDeckAdapter/*.swift` (new)
- `Packages/TelemetryKit/Tests/TelemetryDeckAdapterTests/*.swift` (new)
- `specs/016-telemetrydeck-provider/{spec.md, plan.md, tasks.md}` (new — 内容 = 本次 v3.1 附件去掉版本后缀；唯一权威 artifact 提交者)

### T001 explicitly does NOT touch
- `Packages/TelemetryKit/Sources/TelemetryKit/**`（core layer 冻结——`TelemetryProvider`、`TelemetryDeckProvider`、`TelemetryDeckSignal`、`TelemetryDeckSignalSink`、`TelemetryDiagnostic` 全部保持 public 现状）
- 其它 layer（VitalModels / HealthKitService / AIService / VitalUI / DesignKit）
- 3 个 app target 与 `project.yml`（归 T002）

### T002 owns
- `project.yml`（3 处 `dependencies` 追加 `TelemetryDeckAdapter` product 引用 + 3 处 `settings.base` 追加 `INFOPLIST_KEY_TelemetryDeckAppID: "$(TELEMETRY_DECK_APP_ID)"`）
- `VitalStride.xcodeproj/**`（`xcodegen generate` 重生成）
- `VitalStride/Sources/VitalStrideApp.swift`
- `VitalStrideMac/Sources/VitalStrideMacApp.swift`
- `VitalStrideWatch Watch App/Sources/VitalStrideWatchApp.swift`

### T002 explicitly does NOT touch
- `Packages/**`（归 T001；typed-event boundary 已在 adapter product public 面收紧，T002 只消费 facade）
- 埋点调用点（`TelemetryService.shared.track(...)` / `Telemetry.*`）—— 零侵入是硬约束
- 物理 `Info.plist` 文件（不新增；`GENERATE_INFOPLIST_FILE: true` 是当前基线）
- 诊断相关代码（sentry-cocoa / MetricKit / GlitchTip） —— 独立 spec 015 通道

## 5. Diagnostic-transport Scope Removed

v2 acceptance 曾要求 `TelemetryDeckSDKSink.send(TelemetryDeckSignal(diagnostic:))` → signalType 前缀 `diagnostic_`。**v3+ 删除**该 acceptance——理由：
- 宪法 §V 于 2.4.0 supersede ADR-0012 crash/hang transport 段（ADR-0013）；诊断唯一 transport = 自建 GlitchTip via sentry-cocoa
- `TelemetryDeckProvider.record(_ diagnostic:)` 的现有 code 保留在 core（本 feature 不删代码，避免超范围），但生产**永不给它传 diagnostic**（GlitchTip 是唯一诊断入口）
- Adapter product 测试仅覆盖 **event** round-trip；不再对 diagnostic 走 TelemetryDeck 路径背书

## 6. Typed-Event Boundary

现实基线：`TelemetryDeckSignal(signalType:parameters:)` 是 core layer 的 public API 且**不改**。typed-event-only 的强制点搬到 adapter product public surface：

- Adapter 只 export `enum TelemetryDeckAdapter` + `static func makeProvider(appID:)`
- Sink 与 dispatch seam internal
- 生产代码通过 adapter 只能拿 `any TelemetryProvider`（其接口只 accept `TelemetryEvent` / `TelemetryDiagnostic` 两个封闭类型）
- Acceptance A-4 断言 adapter 目录 `^[[:space:]]*public ` 命中数 = 2（enum + func），A-5 断言 sink/dispatch seam 无 public 出口
- 生产埋点侧：B-9 用 `git diff github/main...HEAD -- '*.swift'` 断言埋点调用点零侵入

## 7. Executable Assertions（v3.1 修正）

**v3 → v3.1 差异**：
- **A-3 换实现**：v3 用 `grep -Pzo`（PCRE + `-z` 空字节分隔）在 macOS BSD grep 上会返回 exit `2`：`grep: invalid option -- P`。v3.1 换成 macOS 环境可执行的结构化断言：
  ```
  swift package dump-package --package-path Packages/TelemetryKit \
    | jq -e '.targets[] | select(.name == "TelemetryKit") | (.dependencies | length == 0)'
  ```
  `dump-package` 输出 Package manifest 的 canonical JSON；`jq -e` 在断言为 false 时以非零 exit 结束——比正则可靠。
- **交叉引用清理**：v3 内文中的 `spec-v3.md` / `plan-v3.md` / `tasks-v3.md` 出现在 spec/plan/tasks 三附件顶部与 §Source-of-truth。这些是**附件名**，不是**落库文件名**。v3.1 内文交叉引用一律用**最终落库文件名** `spec.md` / `plan.md` / `tasks.md`；只在附件顶部与「handoff attachment 命名」章节注明本轮附件命名 `-v3-1.md` 及落库改名规则。

其它负向检查（App ID / plist / 埋点）与 v3 一致。

## 8. Adapter Round-Trip Seam Design

`TelemetryDeckAdapter` 双 overload：

```swift
public enum TelemetryDeckAdapter {
    /// 生产入口
    public static func makeProvider(appID: String) -> any TelemetryProvider {
        TelemetryDeck.initialize(config: .init(appID: appID))   // real SDK API：按现行 major
        return makeProvider(appID: appID, sink: TelemetryDeckSDKSink())
    }

    /// Internal seam — facade round-trip 测试用这个 overload 注入 fake sink
    static func makeProvider(appID: String, sink: any TelemetryDeckSignalSink) -> any TelemetryProvider {
        TelemetryDeckProvider(sink: sink)
    }
}
```

好处：
- Public API surface 只增 1 个 symbol（生产 overload），internal overload 不出 module
- Facade round-trip test 走**真 facade → 真 provider → fake sink**（除 dispatch 外全链真实），满足宪法 P1-I round-trip 要求
- SDK 初始化在生产 overload 里；测试 overload 不初始化 SDK，避免测试环境 SDK 状态污染

## 9. Constitution & ADR Compliance Matrix

| 约束 | 落地 |
|------|------|
| §I 健康隐私 | Adapter public 面只 export facade + `any TelemetryProvider`；provider 接口只接封闭 `TelemetryEvent` / `TelemetryDiagnostic`；`TelemetryIdentifier` ASCII 校验在 core 现状保留 |
| §II Swift 6 strict concurrency | 所有新类型 `Sendable`；`dispatch` closure `@Sendable`；acceptance A-6 / B-11 断言无 `@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)` |
| §III SPM 优先 | Adapter 是 SPM product；round-trip 可 `swift test --package-path` 秒验；SDK 依赖仅落 adapter product，core `TelemetryKit` target dependencies 保持 `[]`（A-3 结构化断言） |
| §IV XcodeGen 真理之源 | 依赖变更走 `project.yml`（B-1 `xcodegen generate`）；App ID 走 `INFOPLIST_KEY_*` build setting；不新增物理 plist（B-10） |
| §V narrow 例外（ADR-0011） | 仅 `TelemetryDeck/SwiftSDK`、仅消费 `TelemetryEvent`；诊断通道**不用** TelemetryDeck（已由 ADR-0013 GlitchTip 承担） |
| §V.2.4.0 / ADR-0013 | 本 feature 明确 **不承担** crash/hang transport；诊断相关 acceptance 全部删除 |
| §VII 范围克制 | 三平台一次接线；不改埋点、不改协议、不改 core 类型可见性、不动物理 plist |
| P1-I round-trip | 新增 public API `TelemetryDeckAdapter.makeProvider(appID:)` 有 facade round-trip test（A-T1/A-T2 走 internal overload 注入 fake sink） |

## 10. Risks & Mitigations

- **SDK API 版本漂移**：`TelemetryDeck.initialize(config:)` / `TelemetryDeck.signal(_:parameters:)` 实际签名可能在 major 版本间变化 → FS 按当时 SPI 现行 major API 微调（描述里给方向，具体调用交 FS TDD 收敛）
- **CI `TELEMETRY_DECK_APP_ID` 未注入** → 生产 build App ID 为 `$(TELEMETRY_DECK_APP_ID)` 字面量 → `Bundle.main.object(forInfoDictionaryKey:)` 返回该字面量 → 启动分支不匹配「非空 + 有效」策略；FR-6 判空即可（`!appID.isEmpty`），未展开的 shell 引用字面量仍是非空但会被 SDK 拒绝，无 crash
- **`TelemetryDeckProvider.record(_:)` 现有 diagnostic 转发行为** → 生产代码永不给它传 diagnostic（GlitchTip 唯一诊断入口）；本 feature 不删代码、不测试该路径，避免超范围
- **`jq` 未安装** → CI/dev 环境需要 `jq`；macOS 默认无 `jq`，但工作站/CI runner 通常已装 (`brew install jq`)。FS 若在 workdir 中检测到 `jq` 缺失，先 `brew install jq` 再跑 A-3

## 11. Handoff attachment 命名规则

本轮 v3.1 handoff comment 附件命名 = `spec-v3-1.md` / `plan-v3-1.md` / `tasks-v3-1.md`（唯一，避免与 v1/v2/v3 混淆）。FS 落库时**去掉 `-v3-1` 后缀**得到最终 `spec.md` / `plan.md` / `tasks.md`。**repo 内文本引用一律使用最终文件名**；附件命名只作为 handoff 层次的传输标识。
