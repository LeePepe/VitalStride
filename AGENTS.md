# VitalStride — Agent Instructions

## Build & Test

### SPM Packages（优先使用）

`Packages/` 下的五个独立 SPM 包（VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit）支持 `swift build` 和 `swift test`，无需 Xcode 项目、无需模拟器，秒级完成。

**改动仅涉及 Packages/ 时，必须用 swift build/test 验证，禁止用 xcodebuild。**

```bash
cd Packages/VitalModels && swift build && swift test
cd Packages/HealthKitService && swift build && swift test
```

### 主 App Target（仅在必要时）

主 app（VitalStride/、VitalStrideMac/、VitalStrideWatch/）没有顶层 Package.swift，必须用 xcodebuild。但要遵守以下规则：

1. **destination 用 generic** — 避免设备连接超时：
   ```bash
   xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
     -destination 'generic/platform=iOS Simulator' \
     -skipPackagePluginValidation
   ```
2. **后台执行 + 长 timeout** — xcodebuild 首次 SPM resolve 可能需要 2-3 分钟，不要用前台短 timeout
3. **只在改动涉及 app target 源码时才跑 xcodebuild** — 如果只改了 Packages/ 下的代码，swift build/test 就够了
4. **运行测试**：
   ```bash
   xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -skipPackagePluginValidation
   ```

### XcodeGen

项目使用 `project.yml` + XcodeGen。修改 target 配置后需重新生成：

```bash
xcodegen generate
```

测试目录（VitalStrideTests/）使用目录源引用，新增测试文件自动包含，无需手动添加。

## Architecture

- **XcodeGen 项目**：`project.yml` 定义 targets，`xcodegen generate` 生成 `.xcodeproj`
- **5 个 SPM local packages**：VitalModels、HealthKitService、AIService、VitalUI、TelemetryKit（TelemetryKit 尚未注册到 `project.yml`，当前仅作为独立包使用，待集成 issue 添加到 app target）
- **Swift 6 strict concurrency**
- **SwiftData** 存储训练数据 + HealthKit L2 缓存（`HealthCacheEntry`，本地隔离，`cloudKitDatabase: .none`）
- **HealthDataCache** 是纯内存 actor L1 缓存层

## Key Conventions

- HealthKit 健康数值禁止出现在任何日志中（隐私合规）
- 详见 CONTEXT.md 的架构决策
