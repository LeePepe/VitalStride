# Tasks: ExercisePicker 搜索框输入时保持 focus (spec 020)

**Spec**: `specs/020-exercise-picker-search-focus-fix/spec.md`
**Plan**: `specs/020-exercise-picker-search-focus-fix/plan.md`
**Parent bug issue**: MY-1368
**Planning gate**: MY-1369
**Round-2 revision**: Reviewer B1-B5 blockers addressed。
**Round-3 revision**: Reviewer round-2 R1/R2/R3 blockers addressed（scheme 归属 / T4 post-focus 触发 / T5d 平台默认 return）。

Legend: `[P]` = 可并行；无标记 = 串行。本 spec 只有单层单 sub-issue，`[P]` 仅在 sub-issue 内部标记。

---

## Sub-issue T020-01 — Fix search field focus loss on debounced content change

**Depends on**: none
**Assignee**: Dev Team squad → Fullstack Engineer

### Task description（copy-paste 到 `multica issue create --description-file`）

---

Parent: MY-1368 — [Bug] 动作选择页：输入时 list 变动导致搜索框失焦

按 `specs/020-exercise-picker-search-focus-fix/{spec,plan}.md` 实施 fix。**先红后绿**：先落测试拿到
baseline 红，再按 plan.md §2 决策树尝试修复。

#### 1. RED — 先落测试 + 测试入口 + UI test target（一次或两次 commit）

- **T020-01a (Reviewer B1 resolved + round-3 R1 resolved — pbxproj 明确在 scope、由 xcodegen 生成；且 VitalStrideUITests 加入 VitalStride scheme test.targets)**: 在 `project.yml`
  里新增 `VitalStrideUITests` target（`project.yml` 基线不含此 target，round-2 已确认）：
  - platform = iOS，type = bundle.ui-testing，depends on `VitalStride` app target；
  - 目录源引用 `VitalStrideUITests/` 目录（新建）；
  - **同时把 `VitalStrideUITests` 加入 `schemes.VitalStride.build.targets` 与
    `schemes.VitalStride.test.targets`** —— 这样 `-scheme VitalStride` xcodebuild test
    命令在 iOS 26 与 iOS 18 两个 destination 上都会一次性执行 unit + UI 测试（round-3 R1）；
  - scheme = `VitalStrideUITests`（自动生成，保留供定向调试）；
  - 跑 `xcodegen generate`。**必须提交**生成的
    `VitalStride.xcodeproj/project.pbxproj` 与
    `VitalStride.xcodeproj/xcshareddata/xcschemes/VitalStrideUITests.xcscheme` +
    `VitalStride.xcodeproj/xcshareddata/xcschemes/VitalStride.xcscheme`（scheme 的
    test.targets 变更也需要重新生成）diff。
  - **不得手改** pbxproj —— 宪法 §IV。若 `git diff` 显示 `project.pbxproj` 有超出 xcodegen
    生成范围的手动改动，`xcodegen generate` 后 `git diff --exit-code` 会失败。
- **T020-01b (Reviewer B2 resolved + round-3 R2 resolved + round-4 R2 resolved — 测试入口 + 显式 post-focus seed 触发 + 确定性 selector)**: 在
  `VitalStride/Sources/VitalStrideApp.swift` 里加 `#if DEBUG` 门禁下的 launch argument 处理：
  - 读取 `ProcessInfo.processInfo.arguments`，识别 `-ExercisePickerTestMode single|multi`；
  - 若命中，root view 的 `.task` / `.onAppear` 里 present `ExercisePickerView(selectionMode: .single, ...)`
    或 `.multiple` modal（用一个 `@State` sheet binding）；
  - 若同时识别到 `-ExercisePickerTestSeedTrigger 1`，则在 modal presentation 内**必须挂一个
    SwiftUI `Button`**（**round-4 R2 修正**：不用 `.accessibilityAction`，因为
    `app.buttons["ExercisePickerTestSeedTrigger"].tap()` 需要 hittable button；`Button` 通过
    `.frame(width: 1, height: 1).opacity(0.001)` 视觉隐藏但保持 hittable），
    `accessibilityIdentifier = "ExercisePickerTestSeedTrigger"`，其 action 同步执行：
    ```swift
    // round-5 R2 修正 —— 使用真实 Exercise 初始化器标签
    // (`muscleGroup:` + `equipment:`, 见
    // Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift init)。
    // 同时把 `nameZh` 设成与 `nameEn` 相同的确定性字符串 `TestSeedExercise`,
    // 因为 `Exercise.localizedName` 在中文 locale 下返回 `nameZh`,
    // `ExercisePickerView.swift:1229` 用 `Text(exercise.localizedName)` 渲染行标题,
    // 该 `Text` 即为 XCUITest `app.staticTexts["TestSeedExercise"]` 命中的元素。
    // 两者相等可保证握手不受模拟器 locale 影响。
    let seed = Exercise(
        nameEn: "TestSeedExercise",     // 确定性名称 — round-4 R2；不含 UUID
        nameZh: "TestSeedExercise",     // round-5 R2 — 与 nameEn 相同，规避 locale 依赖
        muscleGroup: .legs,             // round-6 R1 — 真实 case（`MuscleGroup` 无 `.quads`）
        equipment: .barbell             // round-5 R2 — 真实初始化器标签
    )
    modelContext.insert(seed)
    try? modelContext.save()
    ```
    Main actor 同步；不启动后台 sleep task。用 `@State var didSeed = false` 门控只允许 tap 一次。
    **不使用** round-2 的「500ms sleep 然后 insert」——那种时序不能保证发生在 XCUITest 聚焦
    键盘之后（round-3 R2）。**不使用** round-3 的 `"Test Squat Variant \(UUID())"` 名称——
    UUID 后缀会让 XCUITest 的 exact `staticTexts["Test Squat Variant"]` 查找超时（round-4 R2）。
  - Release build 通过 `#if DEBUG` 编译时剔除。
- **T020-01c**: 新增 `VitalStrideUITests/Sources/ExercisePickerSearchFocusUITests.swift`，实现
  spec §4.1 的 5 个 test：
  - **T1**: `searchFocus_persistsAcrossDebouncedContentChange`（单选 launch arg = `single`）；
  - **T2**: `searchFocus_persistsInMultiSelect`（launch arg = `multi`）；
  - **T3**: `searchFocus_persistsAfterScrollResetTokenBump`（覆盖程序化 `scrollTo`）；
  - **T4**: `searchFocus_persistsAcrossQueryRefresh`（launch arg 加
    `-ExercisePickerTestSeedTrigger 1`；**顺序**：聚焦搜索框 → 等 keyboard 出现 → 输入 `t` →
    sleep(0.3) 越过 debounce → 确认 keyboard 仍在 → **tap
    `app.buttons["ExercisePickerTestSeedTrigger"]`** 触发 SwiftData Exercise insert →
    等 `app.staticTexts["TestSeedExercise"].waitForExistence(timeout: 2.0)` 命中（握手
    `@Query` refresh 完成，selector 为确定性名称 — round-4 R2）→ 断言 keyboard
    仍在。round-3 R2 + round-4 R2 resolved —— mutation 确定发生在 focus 之后 + selector
    与 seed 记录名称一致，无 UUID 后缀）；
  - **T5**: `searchFocus_dismissedByExplicitPaths_stillWork`，四个 sub-case：
    - **T5a**: 点导航栏「取消」按钮；
    - **T5b**: 输入非空 → 点清除按钮 → 键盘收起、`collapsedSearchSurface` 复位；
    - **T5c**: 输入非空 → 手指下滑 grid → `.scrollDismissesKeyboard` 触发；
    - **T5d**: 输入非空 → 键盘 return 键（`app.keyboards.buttons["Search"].tap()` 或
      `app.typeText("\n")`）→ 键盘收起、`isSearchFocused == false`。
      **基线事实（round-3 R3 resolved）**：`ExercisePickerView.swift:415` 的 `TextField` 只有
      `.submitLabel(.search)`，**无** `.onSubmit` 闭包——依赖 SwiftUI 平台默认（单行 TextField
      按 return 会 resign first responder，`@FocusState` 置 false）。因此 T5d 在 **fix 前后**
      都应绿；fix 不得移除 `.submitLabel(.search)` 或引入拦截 return 的 `.onSubmit` 破坏语义。
      若 FS 主动新增 `.onSubmit { isSearchFocused = false }` 让 dismiss 显式化亦可，需同步在
      §7 Public signatures 里声明。回归护栏依然生效。
  - 每字之间 `sleep(0.3)` 越过 200ms debounce；用 `XCUIElement.waitForExistence(timeout: 1.0)`
    避免 flake；不用固定 sleep 作为断言依据。
- **T020-01d (可选，仅当 Step 1 状态机路径准备采用时)**: 新增
  `VitalStrideTests/Sources/ExercisePickerSearchExpansionLogicTests.swift`，实现 spec §4.2 的 4 个
  case。若决定抽取 `nextIsSearchExpanded(...)` static function，在 `ExercisePickerView.swift` 里
  补上（还未开始 fix 逻辑；仅抽取纯函数，行为等价）。若不打算走 Step 1，此文件与状态机抽取
  一并跳过（AC2 标 N/A）。
- **Baseline 跑两次**（Reviewer B3 resolved + round-3 R1 resolved — iOS 18 无条件必跑，
  且两条命令因 `VitalStrideUITests` 加入 `VitalStride` scheme test.targets 都会执行 XCUITest）：
  ```
  # iOS 26 baseline
  xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
    -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation

  # iOS 18 baseline
  xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' -skipPackagePluginValidation
  ```
  截图 / 贴 output 到 PR 描述 — RED 通过条件（round-3 更新）：**T1-T3 至少 2 个 fail**，T4
  期望 fail（若 fix 前 `@Query` 变动确实丢焦；否则作为回归护栏）；**T5 四个 sub-case 全绿**
  （包括 T5d，其依赖平台默认 return 行为）。XCUITest 是唯一 mandatory RED signal —
  Reviewer B4 resolved。

#### 2. GREEN — 按决策树修复（plan.md §2）

顺序：Step 1 (A：子树切换) → Step 2 (B：宿主 identity) → Step 3 (C：scrollDismissesKeyboard)。
每 Step 独立 commit，全绿即停，不继续叠加。

- **T020-01e (Step 1, A)**: 在 `ExercisePickerView.swift`：
  - 方案 A1（首选）：把 `searchSurface` 的 `if isSearchExpanded { expanded } else { collapsed }`
    改为**同一子树 + `.opacity(isSearchExpanded ? 1 : 0)`** 或
    `.hidden()` 切换，保证 `TextField` 宿主不销毁。若视觉需求要求 collapsed 只显示 magnifier
    圆钮，用 `ZStack` 叠放两个子视图 + opacity 切换，`TextField` 始终在树上。
  - 方案 A2（次选）：加保护条件 `if !focused && searchText.isEmpty && debouncedSearchText.isEmpty`
    才 collapse——避免 debounce 期间的 transient focus flip 触发 collapse。
  - 跑 §6 verification pipeline 全部 5 步。全绿 → **停止**，跳到 §3 REFACTOR。红 → revert 本
    commit，进 Step 2。
- **T020-01f (Step 2, B)**: 在 `ExercisePickerView.body`：
  - 把 `.modifier(FloatingPanelAttachment(...))` 从 `exerciseCardGrid` 提到
    `NavigationStack { Group { ... } }.modifier(FloatingPanelAttachment(...))`，即挂在
    `NavigationStack` 层而不是 grid 层。
  - 检查 iOS 18 fallback path 的 `.contentMargins(.bottom, panelHeight, ...)` 是否仍能正常
    工作——`panelHeight` 通过 `.onGeometryChange` 反馈仍在同一层，不出现 relayout 收敛问题
    （这是 Risk R1）。iOS 18 xcodebuild test（§6 步骤 2）是强制门槛。
  - 跑 §6 verification pipeline 全部 5 步。全绿 → 停止。红 → revert，进 Step 3。
- **T020-01g (Step 3, C)**: 在 `exerciseCardGrid` 内：
  - 把 `.scrollDismissesKeyboard(.immediately)` 改为 `.scrollDismissesKeyboard(.interactively)`；
  - **必要时**给 `.onChange(of: scrollResetToken)` 的 `gridProxy.scrollTo(...)` 加
    `withTransaction { $0.disablesAnimations = false }` 包裹（视 SwiftUI 版本行为）；
  - 补 XCUITest T5c 的"下滑 dismiss"用例时序，确保 `.interactively` 语义下仍能通过手指下滑
    dismiss。
  - 跑 §6 verification pipeline 全部 5 步。全绿 → 停止。红 → 进 Step 4。
- **T020-01h (Step 4, LAST RESORT)**: 若 A/B/C 全部失败：
  - **必须**先 comment 到 MY-1369（planning gate）附 signpost 证据 + 各 Step 尝试的 diff。
  - **暂停实施**等待 planner + reviewer 追加评审。
  - 不要直接切到 UIViewRepresentable 包装 UITextField。

#### 3. REFACTOR

- 移除所有临时打点（`signposter.emit` 除非本来就有守护、`print(...)`、`os_log(...) searchText` 等）
- 清理 `// TODO` / `// XXX` / `// FIXME`
- Diff 只保留：产品文件改动（`ExercisePickerView.swift` + `VitalStrideApp.swift` `#if DEBUG` 入口）
  + 1-2 个测试文件 + `project.yml` + `xcodegen generate` 生成的 pbxproj/scheme diff。

#### 4. Verification（PR 提交前 — 四步全 mandatory；Reviewer B3 + round-3 R1 resolved）

按 plan.md §6 跑四步：
1. `-scheme VitalStride` xcodebuild test — iOS 26 iPhone 16 Simulator（含 unit + XCUITest；因
   `VitalStrideUITests` 已加入 `schemes.VitalStride.test.targets`）
2. `-scheme VitalStride` xcodebuild test — iOS 18 iPhone 15 Simulator（**无条件必跑**，覆盖
   `.overlay` legacy 分支；同样含 unit + XCUITest）
3. Packages sanity — 六个 SPM 包（VitalModels / HealthKitService / AIService / VitalUI /
   TelemetryKit / DesignKit）`swift build && swift test`
4. `xcodegen generate` 后 `git diff --exit-code VitalStride.xcodeproj/`

（Optional 定向调试：`-scheme VitalStrideUITests` 单独跑 XCUITest。非 mandatory。）

PR 描述贴四段 output 摘要 + 说明落地在 Step 几（A/B/C）+ 附一段真机/simulator 录屏 GIF。

#### 5. Files in scope（Reviewer B1 + B2 resolved）

- `VitalStride/Sources/ExercisePickerView.swift`（改；产品代码变化 ≤ 60 行）
- `VitalStride/Sources/VitalStrideApp.swift`（改；`#if DEBUG` 门禁下加
  `-ExercisePickerTestMode` / `-ExercisePickerTestSeedTrigger` 处理与 modal 推入 +
  seed 按钮挂载（accessibility identifier `ExercisePickerTestSeedTrigger`，round-3 R2）；
  ≤ 50 行）
- `VitalStrideTests/Sources/ExercisePickerSearchExpansionLogicTests.swift`（新；**可选**，仅
  Step 1 状态机路径下）
- `VitalStrideUITests/Sources/ExercisePickerSearchFocusUITests.swift`（新；必须）
- `VitalStrideUITests/Info.plist`（新；UI test bundle 必要）
- `project.yml`（改；新增 `VitalStrideUITests` target + scheme）
- `VitalStride.xcodeproj/project.pbxproj`（由 `xcodegen generate` 生成 — **不得手改**，宪法 §IV）
- `VitalStride.xcodeproj/xcshareddata/xcschemes/VitalStrideUITests.xcscheme`（由 `xcodegen generate` 生成）

#### 6. Files NOT to touch

- `Packages/**`（VitalModels / HealthKitService / AIService / VitalUI / TelemetryKit / DesignKit
  全部零改）
- `VitalStride/Sources/LiquidGlassStyle.swift`
- `VitalStride/Sources/EquipmentIndexBar*.swift`
- `VitalStride/Sources/WorkoutListView.swift`、`WorkoutListMerger.swift`、`HealthKitWorkoutRowView.swift`
- `VitalStride/Sources/WatchInWorkoutView*.swift`
- `VitalStrideMac/**`、`VitalStrideWatch Watch App/**`、`VitalStrideWidgets/**`
- `.github/**`、`fastlane/**`、`scripts/**`
- `VitalStride.xcodeproj/**` **手动编辑**（生成物只能由 `xcodegen generate` 产生）

#### 7. Public signatures / API

- **无 public API 变化**——`ExercisePickerView.SelectionMode` / 两个 init / `onSelect` / `onConfirm`
  签名不变；Packages 公共 API 零改。
- **新增 view-internal（可选，仅 Step 1 状态机路径）**：
  - `static func nextIsSearchExpanded(currentIsExpanded:isFocused:searchText:trigger:) -> Bool`
  - `enum ExpansionTrigger { case focusChanged; case searchTextChanged; case contentReloaded }`
- **新增 App-level test-only launch arguments（`#if DEBUG` 门禁，非 public API）**：
  - `-ExercisePickerTestMode single|multi`
  - `-ExercisePickerTestSeedTrigger 1`（可选，驱动 T4 `@Query` refresh）

#### 8. Out of scope

- 搜索防抖时长、`computeEquipmentGroups` 过滤算法
- Search 折叠/展开视觉设计（MY-1272 / MY-1277 已定）
- 训练页数字键盘、Watch 视图、WorkoutList 重设计
- 引入 UIKit 包装（除 §2 Step 4 last-resort 且已 planner 追评）

#### 9. Functional acceptance criteria（同 spec §9）

- [ ] AC1 — spec §4.1 的 5 个 XCUITest（T1-T5）全绿；**fix 前 T1-T3 中至少 2 个红，T4 期望红
  （若 fix 前 `@Query` 变动确实丢焦；若绿也接受作为回归护栏）**。T5 是回归护栏，fix 前后应
  始终绿（含 T5d 依赖平台默认 return 行为，round-3 R3）。
- [ ] AC2 — spec §4.2 的 4 个 unit test 全绿 **仅在 FS 采用 Step 1 状态机路径时** required；
  否则标记 N/A（Reviewer B4 resolved — 不作为 RED gate 替代品）。
- [ ] AC3 — 逐字输入「bench」在单选入口不失焦、键盘不收起（录屏）
- [ ] AC4 — 逐字输入「bench」在多选入口不失焦、键盘不收起（录屏）
- [ ] AC5 — iOS 26 iPhone 16 Simulator **与** iOS 18 iPhone 15 Simulator 均通过 AC1/AC3/AC4；
  两条 `xcodebuild test` 命令 output 必须都贴 PR（Reviewer B3 resolved — iOS 18 无条件必跑）
- [ ] AC6 — 主动 dismiss 路径回归全绿：取消 / 清除 / 下滑 / 键盘 return（T5a-T5d 全绿）
- [ ] AC7 — `xcodebuild test` 全绿；六个 Packages 内 `swift build && swift test` 无回归
- [ ] AC8 — `grep -n "logger.*searchText\|os_log.*searchText\|print.*searchText"
  VitalStride/Sources/ExercisePickerView.swift VitalStride/Sources/VitalStrideApp.swift` 无匹配
- [ ] AC9 — 无新增 UIKit dependency（除非 Step 4 触发并附证据）
- [ ] AC10 — 视觉无变化（snapshot / 手动 diff = 0）
- [ ] AC11 — `xcodegen generate` 后 `git diff --exit-code VitalStride.xcodeproj/` 为空（宪法 §IV
  一致性 — Reviewer B1 resolved）

#### 10. Verification command

见 §4 verification pipeline 的五步命令。全部 mandatory。

#### 11. Runtime workflow（Reviewer B5 resolved — 参照 AGENTS.md）

**Working Directory 与 branch 命名遵循 repo AGENTS.md 与 Multica runtime 约定**：

- daemon 已在 `~/multica_workspaces/<workspace>/<task-id>/workdir/` 下为 FS 建好隔离 worktree
  与 fresh branch。**只在那个 workdir 里工作**，绝对不要 `cd ~/Development/VitalStride` 或
  在用户主 checkout 里做 git 操作。
- Branch 命名、push 目标、pre-push ship gate 一律参照 `AGENTS.md` §"Where to push"
  （`agent/<issue-key>-<task-id-short>` 到 `github` remote，`gh pr create` 开 PR）。
- **不要**手写 `--no-verify` 或跳过 pre-push hook —— pre-push hook 是 ship gate，触发失败请
  按 AGENTS.md §"Ship-gate flake quarantine" 处理。若确实遇到 pre-push 在 workdir 内超时的
  environment 问题，先在 issue 上 comment 反馈，不要静默 bypass。

---

## 依赖关系

无。本 spec 只有 T020-01 一个 sub-issue，独立完成。

## 结束条件

T020-01 PR 合并 → MY-1368 close。planning gate MY-1369 在 T020-01 sub-issue 创建后即可 mark
in_review。
