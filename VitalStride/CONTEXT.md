---
layer: AppUI
role: iOS/macOS/watchOS/widget 的平台入口、应用编排与 UI；共享 app 源码的唯一 change owner
paths: [VitalStride, VitalStrideMac, VitalStrideWatch Watch App, VitalStrideWidgets, VitalStrideTests, VitalStrideUITests, VitalStrideWatchTests, project.yml]
depends_on: [VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, DesignKit]
depended_by: []
red_lines:
  - App target 只承载平台入口、UI 与 app-specific 编排；可复用业务规则下沉到对应 Packages layer（宪法 III）
  - App targets 不互相依赖；跨 target 复用通过 packages 或 project.yml 显式共享 source（宪法 III）
  - 健康数值禁止进入日志、CloudKit health cache 或 NSUserDefaults（宪法 I）
  - Swift 6 strict concurrency；不得用 unchecked/unsafe 绕过隔离（宪法 II）
  - UI 字符串使用 xcstrings；禁止新增硬编码用户可见文本（宪法 VI）
  - project.yml 是 target 配置真理之源；xcodeproj 仅为同步生成物（宪法 IV）
test: xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
owns: [ExercisePickerView, app entry points, app-specific SwiftUI, application orchestration, app unit tests, XCUITests, watch tests, XcodeGen target configuration]
---

# AppUI Context

## 职责与路径所有权

`AppUI` 是所有 Xcode app targets 的正式 change-owner layer。它覆盖 frontmatter `paths` 中的生产、
测试和 XcodeGen 真理源；生成的 `VitalStride.xcodeproj/**` 是 RepoInfra 契约声明的 exclusion。
同一份 `VitalStride/Sources/**` 即使被 macOS/watchOS/widget target 通过
`project.yml` 复用，仍只归 `AppUI` 一次，不重复映射。

`VitalStride/Sources/ExercisePickerView.swift` 因此属于 `AppUI`，而它消费的稳定领域语义属于
`VitalModels`。app-specific view state、导航、平台适配和 composition 可以留在本层；可跨 target
复用的领域规则、存储、服务或通用设计组件分别下沉到对应 package layer。

## 依赖

本层可向下依赖六个本地 package layer。app targets 之间没有 target dependency；Mac/Watch/Widget
对 `VitalStride/**` 的复用由 `project.yml` 显式列出，属于同一 change-owner layer 内的源码共享。

## 验证

- 本地验证由实现者按改动面决定；默认 pre-push 只跑轻量门禁，不运行分钟级 `xcodebuild`。
- `App target` required CI 是本层不可绕过的完整 iOS build/test gate。
- 需要本地完整验证时使用 frontmatter 的命令，或 `RUN_XCODEBUILD=1 git push`。
- watchOS 测试 bundle 和 macOS target 尚未被独立 required job 完整执行；这是已记录的 gate coverage gap，
  不通过重复归属或默认 pre-push 重构建来掩盖。
