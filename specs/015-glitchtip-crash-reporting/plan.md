# Implementation Plan: 015-glitchtip-crash-reporting

**Spec**: [spec.md](./spec.md) · **ADR**: [0013](../../docs/adr/0013-self-hosted-glitchtip-sentry-cocoa.md)
**Constitution refs**: §I 隐私、§III SPM 优先、§IV XcodeGen、§V 诊断例外、§VII 范围克制

---

## 架构决策:按 layer 拆,脱敏纯逻辑下沉 TelemetryKit

功能主体落在 **app target `VitalStride/`**(不属于任何 layer),但 §I 脱敏逻辑按宪法 §III 下沉到
**TelemetryKit** layer——纯函数、无 Sentry 依赖、可 `swift test` 秒验、复用该层隐私 red_lines。
据此拆成 3 个按依赖排序的 task(一层/一切面一 commit):

```
Stage 1  T001 [TelemetryKit]  脱敏纯函数 + 对抗单测        (swift test 秒验,无 app 依赖)
Stage 2  T002 [app]           sentry-cocoa 接线 + DSN 注入 + 旧通道去重  (依赖 T001)
Stage 3  T003 [ci]            dSYM 上传符号化                (收尾,不阻塞主链路)
```

依赖顺序:T002 的 `beforeSend` 调用 T001 的纯函数,故 T001 先。T003 是符号化增强,崩溃已能上报后再做。

## 各 task 技术要点

### T001 — TelemetryKit 脱敏纯函数(Stage 1)
- **交付**:TelemetryKit 新增 `CrashEventSanitizer`(或等价 enum 命名空间纯函数),对崩溃事件的
  可疑字段(`extra`/`contexts`/`message`/`breadcrumbs`/`request`)做允许清单过滤。
  - **不 import Sentry**:TelemetryKit `depends_on: []`,不能引入 Sentry 依赖。用一个中间表示
    (如 `[String: Any]` 字典 / 轻量 struct)描述待脱敏字段,app 侧 `beforeSend` 负责在 Sentry
    `Event` ↔ 该中间表示之间转换。纯函数只吃/吐中间表示。
  - 复用现有 `DiagnosticSanitizer` 的「整体拒绝而非静默截断」纪律 + 帧形状白名单。
- **对抗单测**:含心率/体重/邮箱/自由文本的 event → 断言被拦截/脱敏;合法崩溃栈 → 断言放行。
- **验证**:`swift test --package-path Packages/TelemetryKit` 绿。
- **red_lines**(TelemetryKit CONTEXT.md):Telemetry 仅计数/耗时/元数据,禁上报健康数值;
  Swift 6 strict concurrency,类型 Sendable。

### T002 — app target sentry-cocoa 接线(Stage 2,依赖 T001)
- `project.yml` 加远程 SPM 包 Sentry(`from: 8.0.0`),仅挂 iOS `VitalStride` target →
  `xcodegen generate` → commit `.xcodeproj`(§IV)。
- 新建 `VitalStride/Sources/CrashReporting.swift`:`SentrySDK.start`,`enableMetricKit=true`,
  `debug=false`,`beforeSend` = 转中间表示 → 调 T001 纯函数 → nil 则丢弃;`#if DEBUG` 不 start。
- DSN 从 `Info.plist` `GlitchTipDSN` 读(值见 spec FR-4),不硬编码。
- `VitalStrideApp.swift init()` 调 `CrashReporting.start()`;停掉 `MetricKitDiagnosticCollector`
  的 `recordNonisolated` 崩溃 transport(sentry `enableMetricKit` 已接管),避免双报。产品分析路径不碰。
- **验证**:`xcodebuild build -scheme VitalStride -destination 'generic/platform=iOS Simulator'`
  BUILD SUCCEEDED;DEBUG 跑一次确认未发送;Release 触发测试崩溃 → GlitchTip 收到。

### T003 — dSYM 上传(Stage 3,收尾)
- `.github/workflows/testflight.yml` 加 `sentry-cli upload-dif --url <GlitchTip host>`,auth token
  走 CI secret;或在 `docs/glitchtip-azure-deploy.md` 补手动步骤。
- **验证**:GlitchTip 上报事件的堆栈已符号化(有函数名而非纯地址)。

## 风险 / 注意

- **首个远程 SPM 依赖**:现有全是本地包,首次 resolve sentry-cocoa 会拉网络,CI/pre-push 首跑变慢。
- **§I 是 P0 ship blocker**:T001 对抗单测是硬门,Reviewer 会 gate。宁可多拒绝字段,不可漏放健康数值。
- **双报去重**:T002 停旧 transport 时保留 collector 结构,避免误删 ADR-0012 遗留的可测逻辑。
- **DSN 非密钥但仍注入**:public key 可公开,但按 §I 纪律走配置注入,git 里不出现完整 DSN。

## 不做(承 spec Out of scope)

Mac/Watch 接入、产品分析 remote provider、GlitchTip 运维、告警邮件。
