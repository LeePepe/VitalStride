# Feature Spec: iOS 崩溃/Hang 上报到自建 GlitchTip (sentry-cocoa)

**Spec ID**: 015-glitchtip-crash-reporting
**Status**: Ready for planning
**Origin**: Multica MY-1311 · [ADR-0013](../../docs/adr/0013-self-hosted-glitchtip-sentry-cocoa.md)
**Constitution refs**: §I 健康数据隐私零妥协 (NON-NEGOTIABLE)、§V AI 用本地优先(诊断通道 narrow 例外)、§III SPM Package 优先

---

## Why

VitalStride 是 TestFlight-only app,Apple 的自动诊断管道对未上架 app **为空**——崩溃 / hang 拿不到堆栈,
无法定位线上闪退。ADR-0013 已决策:用官方 **sentry-cocoa** SDK(`enableMetricKit=true` 原生抓
crash + hang + 符号化),上报到**自建 GlitchTip**(Sentry 协议兼容,已部署在项目所有者掌控的 Azure,
事件接收已验证 HTTP 200)。数据留在自有基础设施,不落第三方云。

本 spec 是 ADR-0013 的 iOS 端落地。ADR-0013 已合进 `main`,宪法 §V 已记录此为第二个 narrow 例外
(**仅** sentry-cocoa、**仅**崩溃/hang、**仅**上报自建 GlitchTip)。

## What(用户/系统价值)

- Release 构建发生崩溃或 hang 后,下次启动 sentry-cocoa 经 MetricKit 采集诊断,上报到 GlitchTip
  dashboard(project `VitalStride-iOS`),开发者能看到符号化堆栈。
- **§I 健康隐私零妥协**:上报 payload **绝不含**任何 HealthKit 数值(心率/体重/步数…)或 PII
  (邮箱等)。由强制 `beforeSend` 钩子结构化守门:只放行崩溃栈 + 粗粒度设备元数据,其余一律拒绝。
- DEBUG 构建**不发送**。

## Scope

### In scope
- iOS app target(`VitalStride`)接入 sentry-cocoa,首个远程 SPM 依赖。
- `beforeSend` §I 脱敏钩子,过滤逻辑抽为**纯函数 + 对抗单测**,归属 **TelemetryKit** layer。
- DSN 走配置注入(不硬编码进 git)。
- 与现有 ADR-0012 MetricKit→TelemetryDeck 崩溃 transport 的关系处理(避免双重上报)。
- dSYM 上传符号化(CI 步骤或文档,收尾,不阻塞主链路)。

### Out of scope
- **Mac / Watch target 不接**(§VII companion 范围克制;仅 iOS)。
- 产品分析 `TelemetryEvent` / `TelemetryService` 路径**不动**(仍无生产 remote provider,§V)。
- GlitchTip 后端部署 / 运维(已完成,见 `docs/glitchtip-azure-deploy.md`)。
- 告警邮件 / 自定义域名等 GlitchTip 可选配置。

## Functional requirements

### FR-1 sentry-cocoa 依赖(app target only)
`project.yml` 增加首个远程 SPM 包 `Sentry`(getsentry/sentry-cocoa,`from: 8.0.0`),仅挂
`VitalStride` iOS target 的 dependencies(product `Sentry`)。`xcodegen generate` 后 commit 生成的
`.xcodeproj`(§IV XcodeGen 是配置真理之源)。

### FR-2 CrashReporting 接线
新建 `VitalStride/Sources/CrashReporting.swift` 封装 `SentrySDK.start`:
- `options.dsn` 从配置读(FR-4)、`options.enableMetricKit = true`、`options.debug = false`。
- `options.beforeSend` 调用 TelemetryKit 的脱敏纯函数(FR-3);纯函数返回 `nil` 时事件被丢弃。
- `#if DEBUG` 不 start(或 `options.enabled = false`)——ADR-0013 §Decision.4。

### FR-3 §I 脱敏纯函数(TelemetryKit,本 spec 隐私核心)
在 TelemetryKit 新增纯函数(如 `CrashEventSanitizer.scrub(_:) -> Event?` 或等价的、不 import Sentry
的中间表示),对 Sentry event 的 `extra` / `contexts` / `message` / `breadcrumbs` / `request` 字段:
- **只放行**崩溃栈(符号/地址/偏移形状)+ 粗粒度设备元数据(OS 版本、机型、app build)。
- **拒绝/剥离**任何可能含健康数值或 PII 的自由字段;不匹配允许形状的整体拒绝(而非静默截断片段),
  与现有 `DiagnosticSanitizer` 的「整帧拒绝」纪律一致。
- **对抗单测**:构造含心率值 / 体重 / 邮箱 / 自由文本的 event,断言这些必被拦截或脱敏;
  合法崩溃栈事件断言放行。可 `swift test --package-path Packages/TelemetryKit` 秒验。

### FR-4 DSN 配置注入(不硬编码)
DSN 的 public key 可公开,但仍走配置注入、不硬编码进 git。放 `Info.plist` 键(如 `GlitchTipDSN`)
或 xcconfig,`CrashReporting` 从 bundle 读取。DSN 值:
`https://d900071abb35440d92029631132232f4@glitchtip-web.wonderfulriver-644a3e45.eastasia.azurecontainerapps.io/1`

### FR-5 App 启动接入 + 旧通道去重
`VitalStrideApp.swift` `init()` 调 `CrashReporting.start()`。评估现有
`MetricKitDiagnosticCollector` 的崩溃 transport 分支:sentry `enableMetricKit` 接管后停掉
collector 的 `recordNonisolated` transport 避免双重上报(保留其结构或按需移除)。产品分析路径不碰。

### FR-6 dSYM 上传(收尾,不阻塞)
sentry-cocoa 上报栈需 dSYM 符号化。在 `.github/workflows/testflight.yml` 加
`sentry-cli upload-dif`(`--url` 指向 GlitchTip host,auth token 从 GlitchTip 生成、走 CI secret),
或在部署文档写明手动步骤。可作独立收尾子任务。

## Acceptance criteria

- [ ] `xcodegen generate` + `xcodebuild build`(含 Sentry SPM)BUILD SUCCEEDED
- [ ] `beforeSend` §I 脱敏纯函数单测绿——含「健康值/PII 必被拦截」的对抗用例,`swift test` 通过
- [ ] Release 构建触发一次测试崩溃 / `SentrySDK.capture` → GlitchTip dashboard(project
      `VitalStride-iOS`)能看到事件
- [ ] 审计上报 event payload 不含任何 HealthKit 数值(§I)
- [ ] DEBUG 构建不发送(验证 SDK 未 start 或 enabled=false)

## Constitution alignment

| 原则 | 本 spec 如何遵守 |
|------|-----------------|
| §I 健康隐私零妥协 | 强制 `beforeSend` 脱敏钩子,纯函数 + 对抗单测锁死;只放行崩溃栈 + 粗粒度元数据 |
| §V 诊断通道 narrow 例外 | 仅 sentry-cocoa、仅崩溃/hang、仅上报自建 GlitchTip;产品分析路径不受影响 |
| §III SPM Package 优先 | 脱敏纯逻辑落 TelemetryKit(可 swift test 秒验),app target 只做平台接线 |
| §IV XcodeGen 真理之源 | 依赖改 project.yml + xcodegen generate,不手改 .xcodeproj |
| §VII 范围克制 | 仅 iOS,Mac/Watch 不接 |
