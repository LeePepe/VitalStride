# Tasks — 017 Add-Set Button Redesign

**Spec**: `specs/017-add-set-button-redesign/spec.md`
**Plan**: `specs/017-add-set-button-redesign/plan.md`
**Parent issue**: MY-1343 · **Implementation sub-issue**: MY-1348 · **Planning gate**: MY-1347

> **Contract**: 本文件 §Acceptance/Verification 段落**逐字复制**到对应 sub-issue description（MY-1348）。任何漂移均视为 gate 失败。

---

## T001 — MY-1348 · ActiveExerciseSection.addSetButton 视觉重设计（app target）

**Layer**: app target (`VitalStride/`) — 不属于任何 SPM layer
**Status**: stage 1, `backlog`（待 AI Reviewer + Team Lead 双批准后由 TL 提升 → `todo`）
**Blocks**: 无
**Depends on**: 无

### Files in scope

- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` — 只改：
  - `addSetButton` computed property（约 221-242 行）；
  - 底部 `#Preview` 块（扩展或新增，覆盖 4 态 `{normal, large} × {light, dark}`）；
  - **可选**：文件底部 `private struct AddSetButtonStyle: ButtonStyle { ... }` 声明（若引入自定义按下态样式）。
- `specs/017-add-set-button-redesign/spec.md` — 已由 Planner Lead 落库（见 MY-1347 handoff commit）
- `specs/017-add-set-button-redesign/plan.md` — 同上
- `specs/017-add-set-button-redesign/tasks.md` — 同上

### Files NOT to touch

- `Packages/DesignKit/**`（只**消费**现有 token，零新增）
- `Packages/VitalModels/**` / `Packages/HealthKitService/**` / `Packages/AIService/**` / `Packages/VitalUI/**` / `Packages/TelemetryKit/**`
- `VitalStride/Sources/ActiveWorkout/` 下其它文件（`SetRow.swift` / `SubSetRow.swift` / `ActiveWorkoutView.swift` / etc.）
- `VitalStrideWatch Watch App/**` / `VitalStrideMac/**` / `VitalStrideWidgets/**`
- `project.yml` / `VitalStride.xcodeproj/**`（无 XcodeGen drift；不新增 target / dependency）
- 埋点调用点（`TelemetryService.shared.track(...)` / `Telemetry.*`）
- `addSet()` / `addSubSet()` / `copyToNext()` / `deleteSet()` 函数体（数据逻辑冻结）

### Public signatures / API

**none — internal-only visual change.**

`ActiveExerciseSection` 是 `struct: View`，`addSetButton` 是 `private var`——无 public API 变更。

若引入自定义 `ButtonStyle`：

```swift
private struct AddSetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { /* ... */ }
}
```

保持 `private`，不 export。`ActiveExerciseSection` 对上游（`ActiveWorkoutView`）的 init 参数签名不变。

### Interaction Contract (frozen — 红线)

- 点击 → `addSet()`（函数体不改；沿用上一 main set 的 `weight` / `reps` / `setType` / `isUnilateral` / `weightRight`）
- `.accessibilityLabel(String(localized: "添加一组", ...))` 保留
- `.accessibilityHint(String(localized: "在列表末尾插入新的一组", ...))` 保留
- hit target ≥ 44 × 44pt（`.frame(minHeight: 44)`，从当前 36 提升）
- 位置：List section 内 exercise 的最后一行

### DesignKit Token 约束（红线）

**必须使用**（不新增 / 不硬编码）：

- **颜色**：`theme.primary.{primary, primaryHover, primaryActive, primarySubtle, primaryMuted, primaryBorder, primaryText, onPrimary, ring}` 或 `theme.neutrals.{text1, text2, bg}`
- **圆角**：`Radius.inner`（10）或 `Radius.card`（14）
- **间距**：`Space.gap`（12）/ `Space.cardPadding`（16）/ 常见 4/8/12/16pt 间距（`EdgeInsets`）
- **字体**：`Font.system(.callout | .subheadline | .body).weight(.medium | .semibold)` 或 `LargeWorkoutFonts.*`

**禁**：

- `Color(red:green:blue:)` / `Color(hex:)` / `#RRGGBB` literal
- `Font.system(size: N)` 魔法数（除非直接来自 DesignKit `TypeScale`）
- 硬编码圆角（如 `.cornerRadius(8)` — 用 `Radius.inner`）

### Design Direction（FS 自选一种落地）

- **(a) Subtle-fill 行内按钮**（推荐）：`theme.primary.primarySubtle` 背景 + `Radius.inner` 圆角 + 水平/纵向 padding + `theme.primary.primaryText` 前景 + icon
- **(b) Dashed-border chip**：透明背景 + `theme.primary.primaryBorder` 1pt dashed stroke + `Radius.inner`
- **(c) Primary-tinted 图标 + 强化文本**：现结构基础上 `theme.primary.primary` 前景 + `.font(.callout.weight(.medium))`

在 PR body 或 handoff comment 里说明选择哪种及理由（design review 会评估）。

### Preview Coverage

在 `ActiveExerciseSection.swift` 底部加/扩展 `#Preview` 覆盖 4 态：`{normal, large} × {light, dark}`。每个 preview 应包含 ≥ 2 个 sets，以看到 `addSetButton` 与 `SetRow` 的视觉关系。

### Functional Acceptance Criteria (Automatic — executable, workdir-root-relative)

```bash
# A-1 iOS build (app target — 有源码改动)
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

# A-2 macOS build (Mac Catalyst 共享此按钮)
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStrideMac \
  -destination 'generic/platform=macOS' -skipPackagePluginValidation

# A-3 无并发规避
! grep -nE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift

# A-4 无新增硬编码颜色
! grep -nE 'Color\(red:|Color\(hex:|#[0-9A-Fa-f]{6}' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift

# A-5 无新增字体魔法数（diff 内新增行不得有 Font.system(size:)）
git fetch github main
! git diff github/main...HEAD -- \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift \
   | grep -E '^\+.*Font\.system\(size:'

# A-6 交互契约防回归
grep -q 'accessibilityLabel(String(localized: "添加一组"' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift
grep -q 'accessibilityHint(String(localized: "在列表末尾插入新的一组"' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift
grep -q 'private func addSet' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift

# A-7 hit target ≥ 44pt
grep -qE 'minHeight:[[:space:]]*44' \
     VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift

# A-8 diff 范围硬限——只碰一个源文件（+ 可选 spec 三文件）
CHANGED=$(git diff --name-only github/main...HEAD)
echo "$CHANGED" | grep -qxE 'VitalStride/Sources/ActiveWorkout/ActiveExerciseSection\.swift'
[ "$(echo "$CHANGED" | grep -vE '^(VitalStride/Sources/ActiveWorkout/ActiveExerciseSection\.swift|specs/017-add-set-button-redesign/(spec|plan|tasks)\.md)$' | wc -l | tr -d ' ')" = "0" ]

# A-9 spec 三文件到位
[ -f specs/017-add-set-button-redesign/spec.md ] \
  && [ -f specs/017-add-set-button-redesign/plan.md ] \
  && [ -f specs/017-add-set-button-redesign/tasks.md ]
```

### Manual Acceptance (PR body 必须包含)

- **AC-M1**：4 张 before/after 截图，覆盖 `{normal, large} × {light, dark}`（iPhone 16 Simulator）；并排 before/after，标注 design direction。
- **AC-M2**：一句话说明选择的 design direction（a/b/c）及理由。
- **AC-M3**：手动点击回归——真实 workout 触发一次 addSet，确认新组沿用上一 main set 的 `weight` / `reps` / `setType` / `isUnilateral` / `weightRight`。

### Design Review

走 AI Reviewer + design-reviewer sub-agent（若可用），CHANGES REQUESTED 时 FS 迭代。关注点：

- 「可点新增」视觉信号清晰（区别于 SetRow 数据行）
- 与 SetRow / section header hierarchy 协调
- Large Mode 不拥挤 / 不过大
- 深浅色对比度 WCAG AA

### Verification Command (per `AGENTS.md`, layer = app target)

```bash
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation
```

（`Packages/` 无改动，禁用 `swift build/test`；SPM-only hook 不触发。）

### Layer Red Lines

- HealthKit 健康数值禁止进日志（宪法 §I）——本改动无风险，无数值触及。
- 配色 / 尺寸走 DesignKit token（见「DesignKit Token 约束」）。
- Swift 6 strict concurrency（`@Sendable` 若逃逸；`AddSetButtonStyle` 若引入必须 `Sendable`——`struct` 天然满足）。
- 不可变优先（`ButtonStyle` 若引入用 `struct`）。

### Test Policy (unit tests)

**免除**——本任务是纯视觉改动，无新增业务逻辑。若 FS 抽取任何纯函数，加相应 unit test 到 `VitalStrideTests/`。设计正确性由手动 4 张截图 + design review 承担。

### Working Directory (CRITICAL — 禁污染主 checkout)

daemon 已在 `~/multica_workspaces/<workspace>/<task-id>/workdir/` 下建好隔离 worktree。**只在那个 workdir 里工作。**

- **绝对不要** `cd ~/Development/VitalStride`，绝对不要在用户主 checkout 里 `git checkout` / `git checkout -b` / `git fetch` / `git push`。
- 分支操作（建分支、commit、push、开 PR）全部在 daemon 给的 workdir 内完成。
- `git push` 用 `--no-verify`（pre-push hook 在 workdir 内会超时；服务端 required CI 是权威门）。

---

## Design-Time Freshness Guard

VitalStride **未提供** `scripts/hooks/check-tasks-fresh` 脚本；ADR-0014 §3 引用的「设计期防腐机制」在本 repo 仅落地为约定（constitution + TL sync-check），未落地为独立可执行脚本。本 spec 三文件在 PR merge 后即代表 authoritative 源。
