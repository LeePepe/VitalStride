# Tasks: 015-glitchtip-crash-reporting

**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)
执行走 Multica pipeline(不跑 `/speckit-implement`)。task 按 layer 拆,一层/一切面一 commit。
依赖组 → Multica `--stage`;同 stage 全完成才唤醒 parent。

---

## [T001] [Story] TelemetryKit: 崩溃事件 §I 脱敏纯函数 + 对抗单测

**Stage**: 1 · **Layer**: TelemetryKit · **Blocked by**: None — 可立即开始

**What**: 在 TelemetryKit 新增崩溃事件脱敏纯函数(如 `CrashEventSanitizer`,enum 命名空间,
**不 import Sentry**),对可疑字段(extra/contexts/message/breadcrumbs/request 的中间表示)做允许清单
过滤:只放行崩溃栈形状 + 粗粒度设备元数据,其余整体拒绝(不静默截断片段)。复用现有
`DiagnosticSanitizer` 的整帧拒绝纪律。

**Acceptance**:
- [ ] 纯函数不依赖 Sentry / MetricKit,吃/吐中间表示(字典或轻量 struct)
- [ ] 对抗单测:含心率值 / 体重 / 邮箱 / 自由文本的 event → 断言被拦截或脱敏
- [ ] 合法崩溃栈事件 → 断言放行
- [ ] `swift test --package-path Packages/TelemetryKit` 绿

**Constitution refs**: §I 健康隐私零妥协(P0)、§III SPM 优先、§II Swift 6 strict concurrency
**Layer 约束**(TelemetryKit CONTEXT.md):
- depends_on: `[]`(不得引入 Sentry 反向依赖)
- red_lines: Telemetry 仅计数/耗时/元数据,禁上报健康数值(宪法 I);类型须 Sendable(宪法 II)
- test: `swift test --package-path Packages/TelemetryKit`

---

## [T002] [Story] app: sentry-cocoa 接线 + DSN 注入 + 旧崩溃通道去重

**Stage**: 2 · **Layer**: app target(VitalStride/) · **Blocked by**: T001

**What**: iOS app target 接入 sentry-cocoa:`project.yml` 加远程 SPM 包 `Sentry`(`from: 8.0.0`,
仅 iOS `VitalStride` target)→ `xcodegen generate` → commit `.xcodeproj`。新建
`VitalStride/Sources/CrashReporting.swift` 封装 `SentrySDK.start`(`enableMetricKit=true`、
`debug=false`、`beforeSend` 转中间表示后调 T001 纯函数、nil 丢弃、`#if DEBUG` 不 start)。DSN 从
`Info.plist` `GlitchTipDSN` 读(不硬编码)。`VitalStrideApp.swift init()` 调 `CrashReporting.start()`,
停掉 `MetricKitDiagnosticCollector` 的 `recordNonisolated` 崩溃 transport(避免与 sentry
`enableMetricKit` 双报)。产品分析 `TelemetryEvent` 路径不碰。

**Acceptance**:
- [ ] `xcodegen generate` + `xcodebuild build -scheme VitalStride -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED
- [ ] DSN 走 Info.plist 注入,git diff 里无完整 DSN 硬编码
- [ ] DEBUG 构建不 start(或 enabled=false)——可观察/可断言
- [ ] Release 构建触发一次 `SentrySDK.capture` / 测试崩溃 → GlitchTip dashboard(project `VitalStride-iOS`)可见事件
- [ ] 上报 payload 审计无 HealthKit 数值(§I)
- [ ] 旧 collector 崩溃 transport 已停,无双重上报

**Constitution refs**: §I 隐私(P0)、§IV XcodeGen 真理之源(P0,禁手改 .xcodeproj)、§V 诊断 narrow 例外、§VII 仅 iOS
**Layer 约束**(app target,不属任何 layer):
- 依赖变更走 `project.yml` + `xcodegen generate`,提交生成的 `.xcodeproj`
- red_lines: 健康数值禁进 log / event(宪法 I);Mac/Watch 不接(宪法 VII);DEBUG 不发(ADR-0013)
- test: `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation`(后台 + 长 timeout)

---

## [T003] [Story] ci: dSYM 上传符号化崩溃栈

**Stage**: 3 · **Layer**: CI / docs · **Blocked by**: T002

**What**: sentry-cocoa 上报的栈需 dSYM 符号化。在 `.github/workflows/testflight.yml` 加一步
`sentry-cli upload-dif --url <GlitchTip host> --auth-token <CI secret> <dSYM 路径>`,或在
`docs/glitchtip-azure-deploy.md` §运维 写明手动步骤(该文档已有 dSYM 上传占位)。auth token 从
GlitchTip 生成,走 GitHub Actions secret,不进 repo。

**Acceptance**:
- [ ] testflight.yml 有 dSYM 上传步骤,或部署文档有可照做的手动步骤
- [ ] auth token 走 CI secret,git 里无明文
- [ ] GlitchTip 上报事件堆栈已符号化(函数名而非纯地址)

**Constitution refs**: §I(token 不进 repo)、ADR-0013 §运维
**Layer 约束**: CI 配置 / 文档;无 Package test,验证靠一次实际发版后 GlitchTip 栈符号化

---

## 依赖图

```
T001 (Stage 1, TelemetryKit) ──▶ T002 (Stage 2, app) ──▶ T003 (Stage 3, ci)
     独立可开始                    beforeSend 调 T001        符号化增强,收尾
```

parent = MY-1311(feature 总述,指向本 spec)。三个 sub-issue 按 stage 落,staged barrier 顺序唤醒。
