# Tasks — 016 TelemetryDeck Provider (v3.1)

**Parent**: MY-1301 | **spec**: `spec.md` (same feature dir) | **plan**: `plan.md` (same feature dir)
**Version**: v3.1 (2026-07-24) — synchronized with MY-1327 / MY-1328 DoR (v3.1)

> **Contract**: 本文件 §Acceptance/Verification 段落**逐字复制**到对应 sub-issue description。任何漂移均视为 gate 失败。
> **本轮 v3.1 附件命名** = `spec-v3-1.md` / `plan-v3-1.md` / `tasks-v3-1.md`，唯一。**落库时去掉 `-v3-1` 后缀** → `spec.md` / `plan.md` / `tasks.md`。所有 repo 内交叉引用一律使用最终 `spec.md` / `plan.md` / `tasks.md`。

---

## T001 — MY-1327 · TelemetryKit: TelemetryDeckAdapter product + facade round-trip test + spec/plan/tasks

**Status**: stage 1, `todo`, **undispatched**
**Blocks**: T002

### Files in scope
- `Packages/TelemetryKit/Package.swift`
- `Packages/TelemetryKit/Sources/TelemetryDeckAdapter/TelemetryDeckAdapter.swift` (new — facade + internal seam overload)
- `Packages/TelemetryKit/Sources/TelemetryDeckAdapter/TelemetryDeckSDKSink.swift` (new — internal SDK sink + dispatch seam)
- `Packages/TelemetryKit/Tests/TelemetryDeckAdapterTests/TelemetryDeckAdapterTests.swift` (new — facade round-trip + sink dispatch seam tests)
- `specs/016-telemetrydeck-provider/spec.md` (new — 内容 = 本轮 handoff comment 附件 `spec-v3-1.md` 去掉版本后缀)
- `specs/016-telemetrydeck-provider/plan.md` (new — 内容 = 本轮 handoff comment 附件 `plan-v3-1.md` 去掉版本后缀)
- `specs/016-telemetrydeck-provider/tasks.md` (new — 内容 = 本轮 handoff comment 附件 `tasks-v3-1.md` 去掉版本后缀)

### Files NOT to touch
- `Packages/TelemetryKit/Sources/TelemetryKit/**`（core layer 冻结——所有 public 类型可见性不变，含 `TelemetryDeckSignal(signalType:parameters:)` free-string init）
- 其它 SPM package（`VitalModels` / `HealthKitService` / `AIService` / `VitalUI` / `DesignKit`）
- 3 个 app target 与 `project.yml`（归 T002）
- 埋点调用点

### Public signatures / API
```swift
// TelemetryDeckAdapter product — 唯一 public 符号
public enum TelemetryDeckAdapter {
    public static func makeProvider(appID: String) -> any TelemetryProvider
}
```
- `TelemetryDeckSDKSink`、`TelemetryDeckSDKSink.init(dispatch:)`、`TelemetryDeckAdapter.makeProvider(appID:sink:)` **均 internal**
- `TelemetryKit` core product public surface：**无变更**

### Acceptance / Verification（executable, workdir-root-relative, macOS BSD grep + Swift + jq）

```
# A-1 build
swift build --package-path Packages/TelemetryKit

# A-2 test — 包含 A-T1..A-T4 硬断言
swift test --package-path Packages/TelemetryKit

# A-3 核心 TelemetryKit target 依赖仍为空数组（constitutional）— macOS BSD 兼容结构化断言
swift package dump-package --package-path Packages/TelemetryKit \
  | jq -e '.targets[] | select(.name == "TelemetryKit") | (.dependencies | length == 0)'

# A-4 Adapter product 唯一 public 符号数 = 2
[ "$(grep -rnE '^[[:space:]]*public ' Packages/TelemetryKit/Sources/TelemetryDeckAdapter/ | wc -l | tr -d ' ')" = "2" ]

# A-5 sink / dispatch seam 保持 internal（预期为空）
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

**Test-suite hard assertions (`TelemetryDeckAdapterTests`)** — 全部走 `@testable import TelemetryDeckAdapter`：

- **A-T1 facade round-trip（P1-I）**：`let fake = FakeSink()` (符合 `TelemetryDeckSignalSink`，`send(_:)` 追加到数组)；`let provider = TelemetryDeckAdapter.makeProvider(appID: "test", sink: fake)`；`provider.track(.workoutStarted(source: "test"))`；`XCTAssertEqual(fake.signals, [TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "test"])])`
- **A-T2 facade round-trip 参数化**：同 fake 注入，`provider.track(.aiInsightGenerated(durationMs: 42, cardCount: 3))` → `signals == [TelemetryDeckSignal(signalType: "ai_insight_generated", parameters: ["duration_ms": "42", "cards": "3"])]`
- **A-T3 dispatch seam**：`TelemetryDeckSDKSink(dispatch: { s, p in captured = (s, p) }).send(TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "unit"]))` → `captured == ("workout_started", ["source": "unit"])`
- **A-T4 public production overload smoke**：`let provider: any TelemetryProvider = TelemetryDeckAdapter.makeProvider(appID: "test")`; `provider.track(.workoutDiscarded)`（不注入 fake；只验证外部入口 SDK 初始化后调 track 不 crash）

### v3.1 spec/plan/tasks source (authoritative attachments)
必须使用 handoff comment 上文件名以 `-v3-1.md` 结尾的 3 个附件（`spec-v3-1.md` / `plan-v3-1.md` / `tasks-v3-1.md`）；attachment IDs 由 Planner 在 handoff comment 中给出并在 MY-1327 DoR §"v3.1 spec/plan/tasks source" 回填。**禁**取 v1 / v2 / v3 历史附件。落库时去掉 `-v3-1` 后缀。

---

## T002 — MY-1328 · app: 三平台 project.yml 依赖 + Info-plist 键注入 + 启动接线

**Status**: stage 2, `backlog`, **undispatched**
**Blocked by**: T001 (MY-1327)

### Files in scope
- `project.yml`（3 处 `dependencies` 追加 `TelemetryDeckAdapter` product 引用 + 3 处 `settings.base` 追加 `INFOPLIST_KEY_TelemetryDeckAppID: "$(TELEMETRY_DECK_APP_ID)"`）
- `VitalStride.xcodeproj/**`（`xcodegen generate` 重生成）
- `VitalStride/Sources/VitalStrideApp.swift`
- `VitalStrideMac/Sources/VitalStrideMacApp.swift`
- `VitalStrideWatch Watch App/Sources/VitalStrideWatchApp.swift`

### Files NOT to touch
- `Packages/**`（归 T001）
- 埋点调用点（`TelemetryService.shared.track(...)` / `Telemetry.*`）
- 物理 `Info.plist` 文件（禁新增；`GENERATE_INFOPLIST_FILE: true` 是当前基线）
- 诊断相关代码（sentry-cocoa / MetricKit / GlitchTip）

### Public signatures / API
none — internal-only change to app-target startup wiring; app targets 不 export public API.

### Acceptance / Verification（executable, workdir-root-relative, macOS BSD grep）

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

# B-5 Info-plist key 名字面量出现在 3 个 App.swift = 3 处
[ "$(grep -rn '"TelemetryDeckAppID"' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]

# B-6 project.yml 中 INFOPLIST_KEY_TelemetryDeckAppID 值严格等于占位符（正好 3 处）
[ "$(grep -cE '^[[:space:]]*INFOPLIST_KEY_TelemetryDeckAppID:[[:space:]]*"\$\(TELEMETRY_DECK_APP_ID\)"[[:space:]]*$' project.yml)" = "3" ]

# B-7 无对 TELEMETRY_DECK_APP_ID 的字面值赋值（禁 hardcode 真实 App ID 进仓库）
!  grep -nE 'TELEMETRY_DECK_APP_ID[[:space:]]*[:=][[:space:]]*"[^"]*[^)]"' project.yml

# B-8 三处 App.swift 具备 DEBUG Console / else facade 对称结构
[ "$(grep -rn 'TelemetryDeckAdapter\.makeProvider' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]
[ "$(grep -rn 'ConsoleTelemetryProvider' \
       VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources' \
     | wc -l | tr -d ' ')" = "3" ]

# B-9 埋点调用点零侵入 — 权威 remote 是 github
git fetch github main
!  git diff github/main...HEAD -- '*.swift' \
     | grep -E '^\+.*(TelemetryService\.shared\.track\(|Telemetry\.(track|record))'

# B-10 未新增物理 Info.plist（检查新增文件路径，而非文件内容）
!  git diff --name-only --diff-filter=A github/main...HEAD | grep -E '(^|/)Info\.plist$'

# B-11 无并发规避
! grep -rnE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources VitalStrideMac/Sources 'VitalStrideWatch Watch App/Sources'
```

### App.swift 改写模板（三处对称）
```swift
import TelemetryDeckAdapter
// ...
#if DEBUG
Task { await TelemetryService.shared.register(ConsoleTelemetryProvider()) }
#else
if let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String,
   !appID.isEmpty {
    let provider = TelemetryDeckAdapter.makeProvider(appID: appID)
    Task { await TelemetryService.shared.register(provider) }
}
#endif
```

### project.yml 三处 `settings.base` 追加片段
```yaml
INFOPLIST_KEY_TelemetryDeckAppID: "$(TELEMETRY_DECK_APP_ID)"
```
（与既有 `INFOPLIST_KEY_*` 键并列；iOS target 约 L92-119，macOS 约 L166-174，watchOS 约 L226-238；行号仅参考，FS 以实际文件为准）

---

## Dependency Graph

```
T001 (MY-1327, stage 1, todo)
  │  provides TelemetryDeckAdapter product + facade round-trip test + spec/plan/tasks
  ▼
T002 (MY-1328, stage 2, backlog)
```

TL 在 T001 done 后提升 T002 backlog → todo。两 sub-issue **均未 dispatch**，等 v3.1 双批准。

## Constitution / ADR Compliance

- §I / §II / §III / §IV / §V (ADR-0011)：见 `plan.md` §9 矩阵
- §V.2.4.0 / ADR-0013：本 feature 不承担 crash/hang transport
- §VII：三平台一次落地；无侵入埋点、无侵入 core layer 类型可见性
- P1-I：facade round-trip A-T1/A-T2 覆盖新增 public API
