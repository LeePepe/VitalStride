# Feature Spec: ExercisePicker 搜索框输入时保持 focus

**Spec ID**: 020-exercise-picker-search-focus-fix
**Status**: Ready for planning review (round 3 — AI Reviewer round-2 blockers 1-3 addressed)
**Origin**: Multica MY-1368 (bug) → planning gate MY-1369
**Constitution refs**: §I 健康隐私（不涉及数值日志）、§V DesignKit token（不改视觉）、§H a11y (44pt hit)、Swift 6 strict concurrency
**Category**: bug fix（regression-guarding）

---

## 1. Background & Motivation

动作选择页（`ExercisePickerView`）自绘搜索框在用户逐字输入时会**被动失焦、键盘收起**，用户必须
重新点搜索框才能继续输入。这是 MY-1272 引入自绘浮动搜索面板后暴露的回归——原系统 `.searchable`
的 focus 由 UIKit 全局管理，不会因下方 list 内容变化而丢失；替换成
`TextField + @FocusState + FloatingPanelAttachment` 后，当 list 因查询/`@Query` 变动重渲染时，
承载 `TextField` 的宿主视图 identity 可能被牵连重建，`@FocusState` 被丢弃。

这是**呈现/生命周期问题**，不是搜索防抖或过滤算法问题——`debouncedSearchText`、
`computeEquipmentGroups`、`scrollResetToken` 的语义不变。

---

## 2. Repro / 现状证据

Repro（人工，真机 + 模拟器均可）：
1. 打开动作选择页（单选或多选入口）。
2. 点搜索框（磁贴展开为 `expandedSearchSurface`），键盘弹出。
3. 连续快速输入多个字符（如「bench」）。

**期望**：焦点全程保留，键盘不收起，一路输完。
**实际**：某个字符输入后（通常是首个非空字符触发 debounce → list 重算的那一步）焦点被摘掉、
键盘收起，需要重新点框继续输入。

关键路径（现状 basis: `VitalStride/Sources/ExercisePickerView.swift`）：

| # | Observation | File:line |
|---|---|---|
| E1 | `TextField($searchText)` + `.focused($isSearchFocused)` 定义在 `searchRow` | `ExercisePickerView.swift:391-444` |
| E2 | `searchRow` 被 `expandedSearchSurface` 包装 → `searchSurface` 用 `if isSearchExpanded { expandedSearchSurface } else { collapsedSearchSurface }` **两条子树**互切 | `ExercisePickerView.swift:336-353` |
| E3 | `searchSurface` 在 `floatingSearchAndFilterPanel` 内 | `ExercisePickerView.swift:294-313` |
| E4 | 面板挂载点：`exerciseCardGrid.modifier(FloatingPanelAttachment(...))` | `ExercisePickerView.swift:143-150` |
| E5 | `FloatingPanelAttachment`：iOS 26 走 `.safeAreaBar(edge:.bottom)`；iOS 18 走 `.overlay(alignment:.bottom)` | `ExercisePickerView.swift:1117-1134` |
| E6 | 输入触发链：`searchText` → `.task(id: searchText)` debounce 200ms → `debouncedSearchText` → `.onChange(debouncedSearchText)` 重算 `cachedEquipmentGroups` + 写 `visibleEquipment`/`pendingScrollAnchor` + `scrollResetToken &+= 1` | `ExercisePickerView.swift:219-247` |
| E7 | `.onChange(of: exercises)`（`@Query` 结果）也会重算 `cachedEquipmentGroups` | `ExercisePickerView.swift:192-198` |
| E8 | `.scrollDismissesKeyboard(.immediately)` 挂在 `ScrollView` 上——只有滚动手势才 dismiss，`scrollTo` 程序化滚动是否也触发是待验证项 | `ExercisePickerView.swift:643` |
| E9 | `.onChange(of: scrollResetToken)` 会用 `gridProxy.scrollTo(anchor, anchor:.top)`（带 `withAnimation`）——**每次 debounce 都会程序滚动** | `ExercisePickerView.swift:695-701` |
| E10 | 现有单元测试覆盖 `scrollResetToken`、`equipmentGroups`、索引栏 sync，但**没有守护 focus 保持** | `VitalStrideTests/Sources/ExercisePicker*.swift` |

**结论**：没有测试守护「输入期间 focus 不掉」的行为。

---

## 3. 根因假设（供 FS 用 TDD 定位收敛）

规划阶段**不预设**根因结论——但把候选按证据强度排序，FS 在红测试的诊断信号下再定位。

1. **A：`searchSurface` 子树切换**。`isSearchFocused` 在空 query + `focused=false` 时会用
   `withAnimation` 将 `isSearchExpanded` 拨回 false（第 178-183 行），若输入过程中出现瞬时
   `isSearchFocused=false`（可能来自 identity churn 触发的 focus 重定位），会连带切换
   `expandedSearchSurface ↔ collapsedSearchSurface` 两条子树 → `TextField` 被销毁 → focus 彻底丢失
   → 自我强化循环。**证据**：186-190 行的反向 `.onChange(of: searchText)` 又会把 expanded 拨回来，
   但为时已晚。
2. **B：面板宿主 identity 被 grid 重建牵连**。`FloatingPanelAttachment` 用
   `.safeAreaBar` / `.overlay` 挂在 `exerciseCardGrid` 上——`exerciseCardGrid` 内层
   `VStack(ForEach(equipmentGroups))` 结构在 `cachedEquipmentGroups` 替换时结构性变化，如果
   SwiftUI 将 `.safeAreaBar` 的 content 视作 modifier chain 一部分并连带重建，`TextField` 宿主
   identity 变化 → `@FocusState` 丢弃。
3. **C：程序化 `scrollTo` 触发 `.scrollDismissesKeyboard(.immediately)`**。`scrollResetToken` 在
   每次 debounce 后 bump → `gridProxy.scrollTo(...)` → 若 iOS 视之为「滚动」→ 触发
   `.scrollDismissesKeyboard(.immediately)` → 键盘和 focus 一并丢。**证据**：这一路径最"顺理成章"
   解释「debounce 后必失焦」的时间相关性。
4. **D：`@Query exercises` 抖动**。SwiftData `Exercise` 表在动作选择页打开期间被其它 actor 写入 →
   `exercises` 数组标识变化 → `.onChange(of: exercises)` 触发（第 192-198）→ 重算路径与 debounce
   相同 → 附加 identity churn。**证据**：动作选择页打开期间不预期有对 `Exercise` 表的写入，但需
   排除后台 backfill/同步。

FS 应通过失败测试（§4）定位到一条主因，其它作为附加保险修（若必要）。

---

## 4. 失败信号（先红后绿）

在写产品修复代码前，先补一个会因当前 bug 变红的自动化测试。因涉及 `@FocusState`（SwiftUI runtime
状态，纯 `swift test` 单元测试难以观测），选 **XCUITest** 作为主守护，unit test 作为辅助定位。

### 4.1 XCUITest（首选，守护端到端行为）

新增 `VitalStrideUITests` target（`project.yml` 当前不含此 target — 见 §6.2 基线事实；FS 必须
新增，非 "若无则..."）。新增测试文件 `ExercisePickerSearchFocusUITests.swift`：

**测试入口路径（Reviewer B2 resolved — 从可选降为唯一路径）**：所有 XCUITest 用
`-ExercisePickerTestMode single|multi` launch argument 从冷启动直达动作选择页。此 launch
argument 在 `VitalStride/Sources/VitalStrideApp.swift` 内以 `#if DEBUG` 门禁实现：
- `single` → App onAppear 后立即 present `ExercisePickerView(selectionMode: .single, ...)` modal。
- `multi` → App onAppear 后立即 present `ExercisePickerView(selectionMode: .multiple, ...)` modal。
- Release build 该 launch argument 无效（`#if DEBUG` 编译时剔除）。
- 理由：以真实入口导航（训练详情 → +动作 → 动作选择）路径长、依赖 SwiftData 有种子数据、
  可能受 onboarding / auth 状态影响 → XCUITest 慢且 flakey；测试专用直达入口给出稳定 baseline。

- **T1: `searchFocus_persistsAcrossDebouncedContentChange`**（单选路径，覆盖 debounce → 过滤重
  算 → focus 不掉）：
  1. `app.launchArguments = ["-ExercisePickerTestMode", "single"]`；`app.launch()`。
  2. 等 `app.textFields["搜索动作"]` 出现（`waitForExistence(timeout: 5.0)`）。
  3. 点搜索磁贴 → 键盘弹出（`app.keyboards.firstMatch.waitForExistence(timeout: 2.0) == true`）。
  4. 逐字输入 `b`、`e`、`n`、`c`、`h`（每字后 `sleep(0.3)` 越过 200ms debounce 并让 SwiftUI
     完成 re-render）。
  5. 每字后断言 `app.keyboards.firstMatch.exists == true` 且
     `app.textFields["搜索动作"].value as? String` 前缀匹配已输入字符。
- **T2: `searchFocus_persistsInMultiSelect`**：同 T1，`launchArguments = [..., "multi"]`。
- **T3: `searchFocus_persistsAfterScrollResetTokenBump`**（覆盖程序化 `scrollTo`）：
  1. 输入 `d` → 等 debounce → 断言 `app.keyboards.firstMatch.exists == true`；
  2. 观察 `firstEquipmentSection` XCUIElement 的 `frame.origin.y` 变化（scrollResetToken bump
     应该触发 grid `scrollTo(anchor,.top)`）→ 断言键盘仍在。
- **T4: `searchFocus_persistsAcrossQueryRefresh`**（**新增 — Reviewer B3 resolved / round-3 R2
  resolved / round-4 R2 resolved**：覆盖 `@Query exercises` 变动路径，post-focus deterministic 触发）：
  1. `app.launchArguments = [..., "single", "-ExercisePickerTestSeedTrigger", "1"]`。
  2. `#if DEBUG` 门禁下，`VitalStrideApp` 在推入 picker modal 后**不再自动 sleep+insert**——
     round-3 修订：改为**在 modal presentation 内挂一个 SwiftUI `Button`**（**不是**
     `.accessibilityAction`——round-4 R2 修正：为了让 XCUITest 的
     `app.buttons["ExercisePickerTestSeedTrigger"]` 稳定命中并可 `tap()`，必须是 hittable
     `Button`，只是通过 `.opacity(0.001)` + `.frame(width: 1, height: 1)` 在视觉上隐藏，
     `accessibilityIdentifier = "ExercisePickerTestSeedTrigger"`，`accessibilityLabel = "Test Seed"`），
     其 tap handler 执行（**round-4 R2 修正 — 确定性名称，不含 UUID**）：

     ```swift
     // round-5 R2 修正 —— 使用真实 Exercise 初始化器标签
     // (`muscleGroup:` + `equipment:`, 见
     // Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift init)。
     // 同时把 `nameZh` 设成与 `nameEn` 相同的确定性字符串 `TestSeedExercise`，
     // 因为 `Exercise.localizedName` 在中文 locale 下返回 `nameZh`；
     // `ExercisePickerView.swift:1229` 用 `Text(exercise.localizedName)` 渲染行标题，
     // 该 `Text` 即为 XCUITest `app.staticTexts["TestSeedExercise"]` 命中的元素。
     // 两者相等可保证握手不受模拟器 locale 影响。
     let seed = Exercise(
         nameEn: "TestSeedExercise",     // 确定性名称，与 XCUITest exact 断言一致
         nameZh: "TestSeedExercise",     // 与 nameEn 相同，规避 locale 依赖 — round-5 R2
         muscleGroup: .legs,             // round-6 R1 — 真实 case（`MuscleGroup` 无 `.quads`）
         equipment: .barbell             // 真实标签 — round-5 R2
         // 其余字段用初始化器默认值（primaryMuscles=[], defaultReps* 等）
     )
     modelContext.insert(seed)
     try? modelContext.save()
     ```

     在 main actor 上同步执行；不启动后台 sleep task。同一 modal 内只允许 tap 一次（tap 后
     用 `@State var didSeed = false` 变 true 后 disable，避免重复插入影响 T4 的重复运行）。
  3. XCUITest 顺序（**post-focus 触发保证 + exact selector 一致性**）：
     a. 聚焦搜索框 → `waitForExistence(app.keyboards.firstMatch, timeout: 2.0)` == true；
     b. 输入 `t` → `sleep(0.3)` 越过 200ms debounce（选 `t` 因为 seed 名 `TestSeedExercise`
        以 `T` 开头，`t` 输入后过滤仍会命中 seed 行——避免 focus 检测被过滤为空掩盖）；
     c. **确认 focus + 键盘仍在**（若此时已丢，交给 T1 报告，T4 不再继续，避免结果混淆）；
     d. **触发 seed 按钮**：`app.buttons["ExercisePickerTestSeedTrigger"].tap()` —— 此
        步骤显式发生**在** focus 拿到之后（步骤 a）；SwiftUI 收到 `Exercise` 表 insert →
        `@Query exercises` 数组标识变化 → `.onChange(of: exercises)` fire。
     e. **握手（round-4 R2 修正 — exact 断言）**：
        `app.staticTexts["TestSeedExercise"].waitForExistence(timeout: 2.0) == true`
        （名字确定，`==` 语义精确；不使用 `BEGINSWITH` 谓词，因为 identifier 现在是确定的）；
     f. 断言 `app.keyboards.firstMatch.exists == true`（`@Query` refresh 不得导致失焦）。
  4. 若 launch argument 未启用，SwiftData 写入路径不执行，seed 按钮不挂载——保持普通
     XCUITest 语义。
  5. **禁止**：round-2 曾用的「modal present 后立即 500ms sleep + insert」路径已作废
     （Reviewer round-2 R2）——那种时序无法保证 mutation 发生**在** focus 之后。
     round-3 曾用的 `Test Squat Variant \(UUID())` 名称也已作废（round-4 R2）——`UUID` 后缀
     会让 `staticTexts["Test Squat Variant"]` exact 查找超时；round-4 改为确定性名称
     `TestSeedExercise`。
- **T5: `searchFocus_dismissedByExplicitPaths_stillWork`**（防回归——四条主动 dismiss 路径全覆
  盖，**Reviewer B3 resolved 增补 Return 路径**）：
  - **T5a**: 点导航栏「取消」按钮 → dismiss 整个 modal，键盘消失。
  - **T5b**: 输入非空 → 点清除按钮（`xmark.circle.fill`）→
    `app.textFields["搜索动作"].value == ""`、键盘收起、`collapsedSearchSurface` 复位。
  - **T5c**: 输入非空 → 手指下滑 grid（`swipeDown`）→ `.scrollDismissesKeyboard` 触发 →
    键盘收起（此 case 会在 §2 Step 3 修法下需要同步调整断言容差 — 见 tasks.md T020-01f）。
  - **T5d**: 输入非空 → 键盘 return 键（`app.keyboards.buttons["Search"].tap()` 或
    `app.typeText("\n")`）→ 键盘收起、`isSearchFocused == false`。
    **基线事实（round-3 R3 resolved）**：当前 `ExercisePickerView.swift:415` 的 `TextField`
    只带 `.submitLabel(.search)`，**没有** `.onSubmit { ... }` 闭包——SwiftUI 平台默认在
    单行 `TextField` 上按 return 会 resign first responder 并把 `@FocusState` 置 false，
    这也是当前的用户可见行为。因此 T5d 断言基于**平台默认 return 行为**，**不**假设已存在
    `.onSubmit` 回调。
    - **fix 前 T5d 期望**：绿（平台默认已生效）。
    - **fix 中约束**：Step 1/2/3 的任一 fix 都**不得移除** `.submitLabel(.search)`，也不得
      新增会拦截 return（例如 `.onSubmit { ... isSearchFocused = true }`）而破坏 return
      dismiss 语义的代码——若 FS **主动新增** `.onSubmit { isSearchFocused = false }` 让
      dismiss 语义显式化，则同步在 `Files in scope` 与 `Public signatures` 里声明；不新增
      也可以，T5d 依赖的是平台默认，回归护栏依然生效。
    - **回归护栏**：若 fix 意外改动 `.submitLabel(.search)` 或引入拦截 return 的
      `.onSubmit`，T5d 立刻变红。

**RED 期望（round-4 R1 resolved — 单一权威阈值，与 AC1 / plan §3 / tasks §1 完全一致）**：
- **T1-T3 中至少 2 个变红**（本 bug 直接现象：debounce → 过滤重算 → focus 掉、程序化 scrollTo →
  focus 掉；至少两条路径必须在 fix 前观测到失焦）。
- **T4 conditional**：若 fix 前 `@Query` 变动会导致失焦则期望红；若绿则作为 fix 后的回归护栏
  保留。T4 不列入「至少 2 个红」的分子。
- **T5（a/b/c/d）在 fix 前后均应绿**——主动 dismiss 路径的回归护栏，不作为 RED 信号，任何时刻
  的红均视为 blocker。

### 4.2 补充：unit test（辅助定位根因，非替代 XCUITest）

**RED 契约（Reviewer B4 resolved — 单一契约同步三份文档）**：
- **XCUITest 是唯一 mandatory RED signal**——本 bug 是 SwiftUI `@FocusState` runtime 生命
  周期问题，只能在真实 UI runtime 里观测。
- **Unit test 是 optional**——仅在 FS 选定 §2 Step 1 方案 A2（状态机保护条件）或抽取
  `nextIsSearchExpanded(...)` 作为 fix 主体时，unit test 才作为**附加护栏**存在（RED-then-GREEN
  只对该状态机变化生效）；若 FS 选 Step 2（B：宿主 identity）或 Step 3（C：scrollDismissesKeyboard），
  则可跳过 unit test 文件（AC2 相应标记 N/A）。
- **不允许**用 unit test 替代 XCUITest 作为 RED gate——纯状态机测试不能证明 `@FocusState`
  在真实 SwiftUI runtime 下不掉。

新增 `VitalStrideTests/Sources/ExercisePickerSearchExpansionLogicTests.swift`（**仅在 FS 采用
Step 1 状态机路径时**）：

守护「`isSearchExpanded` 状态机不因内容变化被动翻转」的**纯逻辑**部分。抽取
`ExercisePickerView` 里 focus/expansion 决策为可测的 nonisolated static function：

```
static func nextIsSearchExpanded(
    currentIsExpanded: Bool,
    isFocused: Bool,
    searchText: String,
    trigger: ExpansionTrigger  // .focusChanged / .searchTextChanged / .contentReloaded
) -> Bool
```

Test cases：
- `contentReloaded_whileFocused_keepsExpandedTrue`（当前 bug 会红——若 focus 丢失导致状态机走
  `.focusChanged(false)` → expanded=false）
- `focusChanged_toFalse_whileSearchTextEmpty_collapses`（现有主动 dismiss 语义不变）
- `focusChanged_toFalse_whileSearchTextNonEmpty_keepsExpanded`（现有语义）
- `searchTextChanged_toNonEmpty_expands`（现有语义）

若 FS 定位到根因不在此状态机（例如是 identity churn 或 scrollDismissesKeyboard），此 unit test
仍作为回归护栏保留。

---

## 5. Desired behavior（行为契约）

| # | 契约 |
|---|---|
| B1 | 搜索框在输入过程中**全程保持 focus**：`@FocusState isSearchFocused` 在 `debouncedSearchText`、`cachedEquipmentGroups`、`scrollResetToken`、`@Query exercises` 变化后仍为 true。 |
| B2 | 键盘不因上述任一变化被 dismiss。 |
| B3 | `searchSurface` 在整个输入序列中稳定停在 `expandedSearchSurface` 分支（`isSearchExpanded == true`），不因 debounce 抖动。 |
| B4 | 主动 dismiss 路径**全部保留**：点取消按钮、点清除按钮（`searchText=""` 后显式 `isSearchFocused = false`）、下滑 grid（`.scrollDismissesKeyboard(.immediately)`）、点键盘 return。 |
| B5 | 单选入口（`.single`）与多选入口（`.multiple`）行为一致。 |
| B6 | iOS 26+（`.safeAreaBar`）与 iOS 18（`.overlay`）两条 `FloatingPanelAttachment` 路径均满足 B1-B5。 |
| B7 | 视觉不变——`searchRow` 布局、`PanelSurfaceModifier` 材质、DesignKit tokens、chip strip、44pt hit target（Constitution §H）保持现状。 |
| B8 | 隐私红线：产品代码路径不新增任何 `logger` / `os_log` / `print` 携带 `searchText` 内容的日志（§I 涉及用户输入内容，虽非健康数值也不下发）。 |

---

## 6. Scope

### 6.1 In scope（App target layer）

- `VitalStride/Sources/ExercisePickerView.swift`：**最小改动**修 focus 生命周期。允许的方向（按
  A/B/C 假设一一对应，FS 三选一或组合）：
  - **A 修**：把 `searchSurface` 的 expanded/collapsed 分支重构为**同一子树 + `.opacity` /
    `.disabled` 切换**，避免 `TextField` 宿主销毁；或把 `.onChange(of: isSearchFocused)` 的
    collapse 逻辑加保护「仅在 `searchText` 空且已完成 debounce 时执行」。
  - **B 修**：把 `TextField` + `.focused($isSearchFocused)` 移到不随 `exerciseCardGrid` 重建的
    稳定容器（例如 `NavigationStack` 直下、`floatingSearchAndFilterPanel` 提到 body 顶层，用
    `.safeAreaBar` 挂 `NavigationStack`）。
  - **C 修**：把 `.scrollDismissesKeyboard(.immediately)` 改为 `.interactively` 或 `.never`
    并显式在下滑手势里 dismiss；或在 `.onChange(of: scrollResetToken)` 的
    `gridProxy.scrollTo(...)` 外面用 `withTransaction(...) { transaction.disablesAnimations = ... }`
    抑制 keyboard dismiss。**注意**：C 路径若采用，必须补上「用户下滑仍能 dismiss 键盘」的
    XCUITest 用例（§4.1 已列）。
- 若引入辅助 static function（§4.2）：可放在 `ExercisePickerView` 内部或抽到同目录新文件
  `ExercisePickerSearchExpansion.swift`（不进 Packages）。
- 新增 UI test target（如缺失）+ 新增 test 文件。

### 6.2 Files in scope（精确）

**基线事实（round-2 修订）**：`project.yml` 当前**不存在** `VitalStrideUITests` target（仅有
`VitalStride`、`VitalStrideTests`、`VitalStrideMac`、`VitalStrideWatch Watch App`、
`VitalStrideWatchTests`、`VitalStrideWidgets`）。因此 FS 必须新增 UI test target，此为**确定动作**
不再由 FS 判断（Reviewer B1 resolved / U3 resolved）。

**Round-3 R1 resolved（scheme 归属）**：新增 `VitalStrideUITests` target 之后，`project.yml` 的
`schemes.VitalStride.test.targets` **必须同时包含** `VitalStrideTests` 与 `VitalStrideUITests`，
即改为：
```yaml
schemes:
  VitalStride:
    build:
      targets:
        VitalStride: all
        VitalStrideTests: [test]
        VitalStrideUITests: [test]
    test:
      targets:
        - VitalStrideTests
        - VitalStrideUITests
```
这样 §7 里给出的 `-scheme VitalStride` xcodebuild test 命令（iOS 26 与 iOS 18 两条）在两个 OS
上都会一次性执行 unit + UI 测试，验证矩阵完整覆盖（round-2 R1 resolved — 独立 UI test scheme
不再需要作为额外命令，但仍作为 optional 的定向调试入口保留）。

- `VitalStride/Sources/ExercisePickerView.swift`（改）
- `VitalStride/Sources/VitalStrideApp.swift`（**改**；在 `#if DEBUG` 门禁下读取
  `-ExercisePickerTestMode single|multi` launch argument，直接推入对应 modal 供 XCUITest 使用。
  Reviewer B2 resolved — 测试专用入口路径显式落在 Files in scope。）
- `VitalStrideTests/Sources/ExercisePickerSearchExpansionLogicTests.swift`（新；可选：仅当采用
  §4.2 状态机抽取路径时新增）
- `VitalStrideUITests/Sources/ExercisePickerSearchFocusUITests.swift`（新；必须）
- `VitalStrideUITests/Info.plist`（新；UI test bundle 必要）
- `project.yml`（**必改**；新增 `VitalStrideUITests` target + scheme。宪法 §IV：`project.yml` 是
  单一真相源，pbxproj 由 XcodeGen 生成。）
- `VitalStride.xcodeproj/project.pbxproj`（**必改，由 `xcodegen generate` 生成；不得手改**——
  宪法 §IV 只禁止「手动编辑 pbxproj」，不禁止由 XcodeGen 生成。FS 必须提交 `xcodegen generate`
  产生的 diff 以保持 XcodeGen 一致性。Reviewer B1 resolved — 三份文档在此项上一致。）
- `VitalStride.xcodeproj/xcshareddata/xcschemes/VitalStrideUITests.xcscheme`（新；由
  `xcodegen generate` 产生）
- `specs/020-exercise-picker-search-focus-fix/{spec,plan,tasks}.md`（本 planning task 产出）

### 6.3 Files NOT to touch

- `Packages/**`（本 bug 不涉及 SPM 层——`VitalModels.Exercise`、`HealthKitService`、`AIService`、
  `VitalUI`、`TelemetryKit`、`DesignKit` 均不改；这是纯 app-target 修复）。
- `VitalStride/Sources/LiquidGlassStyle.swift`（材质定义不改）。
- `VitalStride/Sources/EquipmentIndexBar*.swift`、`WatchInWorkoutView*.swift`、
  `WorkoutListView.swift`、其它 view file（不在本 bug 路径）。
- `VitalStrideMac/**`、`VitalStrideWatch Watch App/**`、`VitalStrideWidgets/**`（其它平台 target
  不涉及本 bug）。
- `.github/**`、`fastlane/**`、`scripts/**`（不涉及 CI）。

**关于 `VitalStride.xcodeproj/project.pbxproj`**：`round-1` 曾把它列为 "NOT to touch"，但同时又
要求新增 UI test target——两者矛盾。Round-2 修订：pbxproj **在 scope 内**但**只允许由
`xcodegen generate` 生成**，不得手改。见 §6.2 说明与 tasks.md T020-01a 的强制 `xcodegen generate`
+ `git diff --exit-code` 检查步骤。

### 6.4 Out of scope

- 搜索防抖时长（`searchDebounceNanoseconds = 200_000_000`）与过滤算法（`computeEquipmentGroups`
  逻辑）不改，**除非**证明其为失焦根因——需在 comment 附加证据。
- 搜索折叠/展开的视觉设计（MY-1272 / MY-1277 已定）不改。
- 训练页数字键盘、Watch 视图、WorkoutList 重设计等其它 issue。
- 修复不应引入 UIKit `UIViewRepresentable` 包装 `UITextField`——除非纯 SwiftUI 路径全部失败并留
  证据；此为 "last resort" 保留选项。

---

## 7. Layer / red lines / verification

| Key | Value |
|---|---|
| **layer** | app target（`VitalStride/Sources/*.swift`，非 Packages） |
| **red_lines** | §I 隐私（不 log `searchText`）；Swift 6 strict concurrency；不可变优先；配色/尺寸走 DesignKit token；§H 44pt hit target；§IV pbxproj 不手改（但可由 `xcodegen generate` 生成） |
| **verification command (iOS 26 baseline — mandatory)** | `cd <repo root> && xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation` — 覆盖 unit test + XCUITest（`schemes.VitalStride.test.targets` 已含 `VitalStrideUITests`，round-3 R1 resolved） |
| **verification command (iOS 18 legacy path — mandatory, Reviewer B3 resolved / round-3 R1 resolved)** | `cd <repo root> && xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' -skipPackagePluginValidation` — 无论 §2 决策树落在哪一步，此命令都必须无条件跑绿；因 `VitalStride` scheme 现在包含 `VitalStrideUITests`，iOS 18 上也会执行 T1-T5 全部 XCUITest；覆盖 `FloatingPanelAttachment` 的 `.overlay(alignment:.bottom)` 分支。 |
| **verification command (UI test scheme — optional 定向调试)** | `cd <repo root> && xcodebuild test -project VitalStride.xcodeproj -scheme VitalStrideUITests -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation` — 仅用于 FS 单独调 XCUITest 时定向执行，非 mandatory（主验证已在 `VitalStride` scheme 上做完）。 |
| **verification command (XcodeGen 一致性)** | `cd <repo root> && xcodegen generate && git diff --exit-code VitalStride.xcodeproj/project.pbxproj VitalStride.xcodeproj/xcshareddata/xcschemes/` — 应无 diff。 |

**测试环境提示（供 FS）**：XCUITest 冷启动直达动作选择页的机制**已在 §4.1 定型**为
`-ExercisePickerTestMode single|multi` launch argument（Reviewer B2 resolved — 唯一路径）。
FS 在 `VitalStride/Sources/VitalStrideApp.swift` `#if DEBUG` 门禁下实现读取与 modal 推入。
Release build 不含此代码路径。

---

## 8. Public signatures / API

**App-level API（用户不可见）**：无变化——`ExercisePickerView.SelectionMode`、两个 init、
`onSelect` / `onConfirm` 回调签名不变。

**View-internal（可能新增，FS 判断）**：
- `static func nextIsSearchExpanded(currentIsExpanded:isFocused:searchText:trigger:) -> Bool`（若采用
  §4.2 状态机抽取）
- `enum ExpansionTrigger { case focusChanged; case searchTextChanged; case contentReloaded }`

**测试 helper（launch argument 支持，Reviewer B2 resolved — 必须实现，非可选）**：
- `VitalStride/Sources/VitalStrideApp.swift` 在 `#if DEBUG` 门禁下读取
  `ProcessInfo.processInfo.arguments`，识别 `-ExercisePickerTestMode single|multi`
  与可选的 `-ExercisePickerTestSeedTrigger 1`，在根 view `.task` / `.onAppear` 里推入对应
  modal，可选触发一次 SwiftData Exercise 表写入以驱动 T4（§4.1）的 `@Query` refresh 路径。
- Release build 通过 `#if DEBUG` 编译时剔除，无 App Store 审核风险。

**Public API contract**：本 bug 不改 Packages / 不改公共接口——`Packages/VitalModels.Exercise`、
`Packages/HealthKitService.*`、`Packages/AIService.*`、`Packages/VitalUI.*` 全部零改动。

---

## 9. Acceptance criteria

- [ ] AC1 — §4.1 的 5 个 XCUITest（T1-T5，含 T4 `@Query` refresh 与 T5d keyboard Return）全部
  绿；fix 前 T1-T3 中至少 2 个红，T4 期望红（若 fix 前 `@Query` 变动确实丢焦；若绿则作为
  回归护栏）。T5 是回归护栏，fix 前后应始终绿（round-3 R3：T5d 依赖 SwiftUI 平台默认 return
  行为，不依赖不存在的 `.onSubmit`）。
- [ ] AC2 — §4.2 的 4 个 unit test **仅在 FS 采用 Step 1 状态机路径时** required；否则标记 N/A
  并在 PR 描述里说明。**不作为 RED gate 替代品**——XCUITest 是唯一 mandatory RED signal
  （Reviewer B4 resolved）。
- [ ] AC3 — 逐字输入「bench」在单选入口不失焦、键盘不收起（手动 QA 附一段录屏 or GIF）。
- [ ] AC4 — 逐字输入「bench」在多选入口不失焦、键盘不收起（手动 QA 附一段录屏 or GIF）。
- [ ] AC5 — iOS 26 iPhone 16 Simulator **与** iOS 18 iPhone 15 Simulator 均通过 AC1/AC3/AC4；
  两条 `-scheme VitalStride` `xcodebuild test` 命令 output 必须都贴 PR（两条都覆盖 unit +
  XCUITest，因 round-3 R1 已把 `VitalStrideUITests` 加入 `VitalStride` scheme 的 test.targets；
  Reviewer B3 + round-3 R1 resolved）。
- [ ] AC6 — 主动 dismiss 路径回归全绿：取消 / 清除 / 下滑 / 键盘 return（T5a-T5d 全绿 + 手动
  QA）。
- [ ] AC7 — `xcodebuild test` 全绿（含新增 XCUITest 与可选 unit test），`swift build && swift test`
  在六个 Packages 内均无回归（VitalModels / HealthKitService / AIService / VitalUI /
  TelemetryKit / DesignKit — 本改动不涉及 Packages，只需 sanity check）。
- [ ] AC8 — `grep -n "logger.*searchText\|os_log.*searchText\|print.*searchText"
  VitalStride/Sources/ExercisePickerView.swift VitalStride/Sources/VitalStrideApp.swift` 无匹配
  （红线 §I 守护）。
- [ ] AC9 — 无新增 UIKit dependency（除非 §6.4 last-resort 情形并附加证据 comment）。
- [ ] AC10 — Preview / snapshot 无视觉变化（若 repo 有 snapshot test，跑一次 diff = 0）。
- [ ] AC11 — `xcodegen generate` 后 `git diff --exit-code VitalStride.xcodeproj/` 为空（XcodeGen
  一致性 — Reviewer B1 resolved）。

---

## 10. Design references / prior art

- MY-1272：Floating search + filter panel 初版（本 bug 根源）。
- MY-1277：Search on top / chips on bottom 反转（无关但共同宿主）。
- MY-1249 / MY-1250：Scroll reset / index bar sync（共用 `scrollResetToken` 路径——不改）。
- MY-1338：Index bar drag scrub（无关）。
- 参考：Apple SwiftUI FocusState 官方文档 + WWDC24 "What's new in SwiftUI" 的
  `.safeAreaBar` 章节（iOS 26+ 提示 sibling identity 稳定性）。

---

## 11. 不确定 / 待 FS 用红测试收敛

| # | 不确定项 | 收敛方式 |
|---|---|---|
| U1 | A/B/C 中哪个是主因？ | §4.1 的 XCUITest 变红后，FS 用 `os_signpost` 或 `print` 临时打点定位（**临时打点必须删除**，不进 commit）。 |
| U2 | `scrollDismissesKeyboard(.immediately)` 对程序化 `scrollTo` 是否触发？ | FS 用一个最小复现 sample 或直接读 SwiftUI runtime 行为文档；若触发，采 C 修方向。 |
| U3 | ~~UI test target 是否已存在？~~ **已解决**（Reviewer 已确认 `project.yml` 不含 `VitalStrideUITests`；FS 必须新增，见 §6.2）。 |
| U4 | ~~是否有必要为 XCUITest 加 launch argument？~~ **已解决**（Reviewer B2 要求测试入口路径落在 Files in scope；已在 §4.1 定型为唯一路径：`-ExercisePickerTestMode single|multi` 通过 `VitalStrideApp.swift` `#if DEBUG` 门禁实现）。 |

---

**Ready for planning review**. 已具备 DoR：Files in scope（§6.2）、Files NOT to touch（§6.3）、
Public signatures（§8）、Functional acceptance（§9，10 条）、Verification command（§7）、
Out of scope（§6.4）。红测试策略（§4）落在 XCUITest 主 + unit test 辅——因涉及 `@FocusState`
runtime 状态，`swift test` 不能直接观测。
