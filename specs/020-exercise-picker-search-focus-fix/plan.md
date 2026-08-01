# Plan: ExercisePicker 搜索框输入时保持 focus

**Spec**: `specs/020-exercise-picker-search-focus-fix/spec.md`
**Origin**: Multica MY-1368 (bug) → planning gate MY-1369
**Layer**: app target only（无 Packages 改动）
**Estimated LOC**: ≤ 300（含新增测试；产品代码变化预计 ≤ 60 行）
**Estimated review rounds**: 1-2（bug fix，非架构性改动）
**Round-2 revision**: Reviewer B1-B5 blockers addressed（见每节末 `Reviewer resolved` 标注）
**Round-3 revision**: Reviewer round-2 R1/R2/R3 blockers addressed（scheme 归属 / T4 post-focus 触发 / T5d 平台默认 return）

---

## 1. 分层结构

单层。本 bug 完全在 app target 内（`VitalStride/Sources/ExercisePickerView.swift` +
`VitalStride/Sources/VitalStrideApp.swift` `#if DEBUG` 测试入口），无 Packages 依赖翻动。因此
**不拆多 issue**、**不分 Stage**——一个 fix sub-issue 即可，测试与产品代码同 PR。

理由：
- Files in scope 只有 2 个产品代码文件 + 1-2 个测试文件 + `project.yml` + `xcodegen generate`
  产生的 pbxproj/scheme diff；
- 无接口切割点（`SelectionMode`、Packages 均不改）；
- fix 三个候选方向（A/B/C）均属"最小改动"级别，若组合两个方向仍在同 view 内；
- 强行拆「测试 sub-issue → 修复 sub-issue」会破坏 spec §4「先红后绿」的 TDD 节奏——同一 FS
  必须先看到红测试再改代码。

---

## 2. 修复策略路由（决策树）

FS 按此顺序尝试，每一步失败留 signpost 证据在 PR：

```
Step 0. 先落 XCUITest（§4.1 spec — T1-T5 共 5 个用例）+
        VitalStrideApp.swift #if DEBUG 门禁下的 -ExercisePickerTestMode 入口 +
        DEBUG-only seed 按钮（accessibility id = ExercisePickerTestSeedTrigger，round-3 R2）+
        project.yml 加 VitalStrideUITests target **并把 VitalStrideUITests 加入 VitalStride
        scheme 的 test.targets**（round-3 R1）+ xcodegen generate。
        跑一次 `xcodebuild test -scheme VitalStride` 拿到 baseline —— 期望 T1-T3 中至少 2 个红、
        T4 红（若 fix 前 focus 也真的丢），T5 全绿。
        (可选) 若准备走 Step 1 状态机路径，同时补 §4.2 unit test。

Step 1. 尝试根因假设 A（子树切换）：
        - 把 searchSurface 的 if/else 改为同一子树 + .opacity/.disabled 切换；
          或给 .onChange(of: isSearchFocused) 的 collapse 路径加保护条件。
        - 跑 XCUITest。全绿 → 提交。

Step 2. 若 A 未全绿，尝试根因假设 B（宿主 identity 稳定性）：
        - 把 floatingSearchAndFilterPanel 从 exerciseCardGrid.modifier(FloatingPanelAttachment(...))
          提到 NavigationStack 层 .safeAreaBar / .overlay。
        - 跑 XCUITest。全绿 → 提交。

Step 3. 若 B 未全绿，尝试根因假设 C（scrollDismissesKeyboard）：
        - .scrollDismissesKeyboard(.immediately) → .interactively
        - 或 gridProxy.scrollTo 外面用 UITextView-friendly transaction。
        - 补上"用户下滑仍能 dismiss"XCUITest。
        - 跑 XCUITest。全绿 → 提交。

Step 4. 若 A/B/C 全部尝试仍未全绿：
        - 在 issue MY-1369 / MY-1368 上 comment 附完整 signpost 证据 + 已尝试改动 diff；
        - 触发 last-resort：UIViewRepresentable 包装 UITextField。
        - 需 planner + reviewer 追加评审——不要静默切换。
```

**边界条件**：
- 每个 Step 的改动必须在自己的 commit 里，PR 保留完整历史（不要 squash 到单 commit）——方便
  reviewer 看到哪一步是主因；
- Step 1-3 任一成功后，其它 Step 的临时改动**必须 revert**——不要"以防万一"叠加多个 fix，那会
  让根因不清且引入其它 regression；
- Step 4 触发前必须先在 issue 上 comment；不要跳过 planner。

---

## 3. Test-first 节奏（Reviewer B4 resolved — RED 契约单一化）

严格按 TDD 三阶段：

| Phase | 动作 | 期望 |
|---|---|---|
| RED | Step 0 提交 XCUITest（T1-T5）+ `VitalStrideApp.swift` 测试入口 + DEBUG-only seed 按钮（round-3 R2）+ `project.yml` UI test target 且加入 `VitalStride` scheme test.targets（round-3 R1）+ xcodegen generate 产物；产品代码零改动 | T1-T3 中至少 2 个 fail、T4 fail（若 fix 前 `@Query` 路径确实触发失焦；若绿则作为回归护栏）；**T5 应全绿（包括 T5d，其依赖平台默认 return 行为，round-3 R3）**；unit test 仅在 Step 1 路径下**可选**新增 |
| GREEN | 按 §2 决策树尝试修复，每一步跑 test | XCUITest 全绿（T1-T5）+ iOS 26 与 iOS 18 两条 xcodebuild test 都绿 |
| REFACTOR | Step 5 review：清理 signpost、临时注释、TODO | Diff 只留产品必要改动 |

**RED gate 契约（三份文档同步）**：
- **XCUITest（§4.1 spec）是唯一 mandatory RED signal**——因 `@FocusState` 是 SwiftUI runtime
  状态，纯 unit test 不能证明其在真实 UI 生命周期下不掉。
- **Unit test（§4.2 spec）是 optional**——仅在 FS 选定 Step 1 方案 A2（状态机保护条件）
  或抽取 `nextIsSearchExpanded(...)` 作为 fix 主体时才 required；若选 Step 2 / Step 3 / Step 4，
  unit test 可跳过（AC2 标记 N/A 并在 PR 描述里说明）。

**不允许**：
- 先写产品代码再补测试（"事后 assertion"）；
- 只加 assertion 不构造复现场景（例如只断言 `isSearchFocused == true` 但不真的输入字符——那种
  test 永远绿，无守护价值）；
- 用 `XCTSkip` 或 `try XCTSkipIf` 绕过 iOS 26 / iOS 18 分支（Reviewer B3 resolved — iOS 18
  必须无条件跑）。
- 用 unit test 替代 XCUITest 作为 RED gate（Reviewer B4 resolved）。

---

## 4. Concurrency / Swift 6

- `nextIsSearchExpanded(...)` 若采用，是 `static nonisolated`（纯函数）；
- 新增测试 `@MainActor`（`XCTestCase` + SwiftUI runtime 交互均 MainActor）；
- 无新 `Task { }` / `Task.detached` / actor 引入（`VitalStrideApp.swift` 里的 `#if DEBUG`
  测试入口 SwiftData 写 seed 用 `Task { @MainActor in ... }`，仅 DEBUG build 编译）；
- 不改 `.task(id: searchText) { ... }` 的 debounce 结构。

---

## 5. Privacy & red lines

| Red line | 落地机制 |
|---|---|
| §I 隐私：不 log 用户输入内容 | AC8 的 grep 断言（`logger.*searchText\|os_log.*searchText\|print.*searchText`）扩到 `ExercisePickerView.swift` + `VitalStrideApp.swift`；Reviewer 目视 diff |
| §V DesignKit token | 视觉不改（AC10 snapshot / 手动） |
| §H 44pt hit target | 清除按钮已 44×44、collapsed pill 已 44×44——不动 |
| §IV pbxproj 不手改 | 只允许 `xcodegen generate` 生成；AC11 `git diff --exit-code` 守护 |
| Swift 6 strict concurrency | `xcodebuild test` 编译门槛守护 |

---

## 6. Verification pipeline（Reviewer B3 resolved / round-3 R1 resolved — iOS 18 无条件必跑，且 XCUITest 归属 VitalStride scheme）

FS 提交前跑（**全部 mandatory**）：

```
cd <repo root>

# 1. VitalStride scheme（含 unit + XCUITest，round-3 R1 resolved）— iOS 26 iPhone 16（baseline）
xcodebuild test \
  -project VitalStride.xcodeproj \
  -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# 2. VitalStride scheme（含 unit + XCUITest）— iOS 18 iPhone 15（legacy .overlay 分支）
xcodebuild test \
  -project VitalStride.xcodeproj \
  -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' \
  -skipPackagePluginValidation

# 3. Packages sanity（六个 SPM 包；本 bug 不改 Packages，跑一次确认没有意外污染）
for pkg in VitalModels HealthKitService AIService VitalUI TelemetryKit DesignKit; do
  (cd Packages/$pkg && swift build && swift test) || exit 1
done

# 4. XcodeGen 一致性（改了 project.yml + pbxproj 生成物）
xcodegen generate
git diff --exit-code VitalStride.xcodeproj/  # 应为空 = 已同步
```

（Optional — 定向调 XCUITest 时可单独跑，非 mandatory：
`xcodebuild test -project VitalStride.xcodeproj -scheme VitalStrideUITests -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation`）

PR 描述贴出四段 output 摘要 + 说明落地在 Step 几（A/B/C）+ 附一段真机/simulator 录屏 GIF。

---

## 7. Rollout

- 无 feature flag——bug fix，直接 ship。
- 无数据迁移。
- 无 App Store 审核相关的用户可见改动（视觉不变；`#if DEBUG` 测试入口不进 Release build）。

---

## 8. Risks & mitigations

| Risk | 概率 | 影响 | Mitigation |
|---|---|---|---|
| Step 2 把 panel 提到 NavigationStack 后打乱 `.contentMargins(.bottom, panelHeight, ...)` 的静态 margin 链 → iOS 18 上出现 CPU 100% relayout 回归（MY-XXXX 记录的历史） | 中 | 高 | Step 2 之前先跑一次 iOS 18 simulator baseline（§6 pipeline 已强制）；Step 2 之后必跑；若 CPU 高负载出现，回退到 Step 1 或 Step 3 |
| Step 3 改 `.scrollDismissesKeyboard` 破坏"用户下滑收键盘"体验 | 中 | 中 | AC6 已在 XCUITest T5c 里守护下滑路径；发现回归立即回退 |
| XCUITest flakey（键盘弹出/收起时机） | 中 | 低 | 用 `waitForExistence(timeout: 1.0)`；不用固定 sleep；单次 fail 允许 retry 一次，两次都 fail 视为红 |
| iOS 26 / iOS 18 分支只在一个跑 | 高 | 中 | AC5 明确要求两个 simulator 都跑；§6 pipeline 把两条 xcodebuild test 都标为 mandatory；FS 在 PR 描述贴两段 output |
| 引入 UIKit `UIViewRepresentable`（Step 4）→ Preview 兼容性 / 未来 SwiftUI 升级负担 | 低（Step 4 才触发） | 高 | Step 4 触发前必须 planner + reviewer 评审 |
| `#if DEBUG` 测试入口意外进 Release build → App Store 审核显示 modal | 低 | 高 | `#if DEBUG` 编译时剔除；FS 可选在 PR 描述附一段 Release scheme build 后 `strings` 或 `nm` 检查 `-ExercisePickerTestMode` 字符串不存在的证据 |

---

## 9. Handoff

- 本 planning task（MY-1369）不写产品代码；产出即 `spec.md` / `plan.md` / `tasks.md`。
- Handoff 目标：Team Lead 收到 planning 完成 → assign 一个 sub-issue 给 Dev Team squad
  做实施（**squad 模式**：squad leader 会用 @mention 委派给 Fullstack Engineer）。
- 实施 sub-issue 的 description 已在 `tasks.md` 的 T020-01 完整给出，Team Lead 直接抄进
  `multica issue create --description-file <t020-01-body.md>` 即可。
- **不在 tasks.md 里写 branch 命名/push 指令**（Reviewer B5 resolved）——AGENTS.md
  的 daemon-provided branch + `agent/<issue-key>-<task-id>` 约定是唯一真相源。

---

**Ready for planning review (round 2)**. Estimated 1-2 review rounds. Diff size ≤ 300 LOC.
单层单 sub-issue。所有 5 项 Reviewer 阻断点已在 spec/plan/tasks 中同步解决。
