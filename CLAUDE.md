# VitalStride — Agent Instructions

## Build & Test

### SPM Packages（优先使用）

`Packages/` 下的六个独立 SPM 包（VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, DesignKit）支持 `swift build` 和 `swift test`，无需 Xcode 项目、无需模拟器，秒级完成。

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
- **6 个 SPM local packages**：VitalModels、HealthKitService、AIService、VitalUI、TelemetryKit、DesignKit（均已注册到 `project.yml` 并接入 app target；TelemetryKit/DesignKit 为无本地依赖的独立包）
- **Swift 6 strict concurrency**
- **SwiftData** 存储训练数据 + HealthKit L2 缓存（`HealthCacheEntry`，本地隔离，`cloudKitDatabase: .none`）
- **HealthDataCache** 是纯内存 actor L1 缓存层

## Key Conventions

- HealthKit 健康数值禁止出现在任何日志中（隐私合规）
- 详见 CONTEXT.md 的架构决策

## PR 流程（提交后必须监督到 merge）

**开完 PR 不是终点。** 本 repo 的 PR 走 auto-merge（squash）：CI 全绿 + required review 通过后自动合并。提交 PR 后 agent 必须监督直到 PR 真正 merge，不能开完就撒手。

监督要求：

1. **盯 CI 与 review 直到终态** — 用 `gh pr view <n> --json state,mergeStateStatus,statusCheckRollup,reviewDecision` 轮询，直到 `state == MERGED`（成功）或明确失败需要人工介入。
2. **required checks**：`codex-review` 与 `claude-review` 是 required，二者 `critical/high` 结论会阻塞 auto-merge。CI job（App target / SPM / Lint & policy）任一失败也阻塞。
3. **有问题直接修** — CI 失败或 reviewer 提出阻塞项时，直接在分支上改代码 → commit → push（改写已 push 的 commit 用 `git push --force-with-lease`），触发重跑，无需等人。修完继续监督。
4. **常见阻塞项**：
   - **XcodeGen drift（宪法 IV）**：不要手动提交 `VitalStride.xcodeproj/project.pbxproj`。它是 `xcodegen generate` 的生成产物；CI 会自己跑 xcodegen（`ci.yml`）从 `project.yml` 的目录源引用（`VitalStrideTests` 等）重新生成。新增测试文件**只提交 `.swift` 源文件**，还原 pbxproj 到 main 版本。
5. **同步本地** — PR 合并后，把 merge 结果同步回本地（`git fetch github && git switch main && git pull`；worktree 场景收尾时同步主 checkout）。

