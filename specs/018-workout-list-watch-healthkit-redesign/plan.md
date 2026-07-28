# Implementation Plan: WorkoutListView redesign (spec 018)

**Spec**: `specs/018-workout-list-watch-healthkit-redesign/spec.md`
**Parent issue**: MY-1356
**Planning gate**: MY-1357
**Sub-tasks**: MY-1358 (HealthKitService layer), MY-1359 (App target UI + design gate)

---

## Layer boundaries and dependency chain

| Stage | Task | Layer | depends_on | Verification pack | Owner |
|---|---|---|---|---|---|
| 1 | MY-1358 | `Packages/HealthKitService/*` | — | `swift build && swift test` (Working directory: `Packages/HealthKitService`) | Fullstack |
| 2 | MY-1359 | `VitalStride/Sources/*` app target + `docs/reports/018-*-screenshots.md` | MY-1358 merged | `xcodebuild build` + `xcodebuild test` (Working directory: repo root) + design review comment on T2 PR | Fullstack + design reviewer |

Stage 1 → Stage 2 是**强串行**（Stage 2 消费 Stage 1 引入的 `averageHeartRate` / `sourceDeviceKind` 字段）。
两阶段间不引入 shim / feature flag —— 允许一层一 commit 的直接演进。

## Why merged into two layers (not three)

原 round-1 拆分为 T1 (Service) → T2 (UI) → T3 (design review) 三阶段，AI Reviewer 判定
T3 gating T2 的先后逻辑矛盾（截图需要 T2 已实现；T2 PR 又要靠 T3 通过 design gate）。
Round 2 **将 design review 折入 T2 的 pre-merge 验收**：

- Design gate 作为 T2 PR 的一部分：截图 + report 文件 + reviewer comment 都必须在 T2 PR merge 前完成。
- 好处：单一 PR 承载「代码 + 截图 + design decision」；无跨 PR gating 悖论；
  与 §Cross-cutting 规范里「一层一 PR」的一致性冲突降到最低。
- 代价：T2 PR 体积略增（+1 markdown 文件、+PR 描述贴截图）；可接受。

MY-1360 因此**改为 cancelled**，其内容进入 MY-1359 的 acceptance criteria + Files in scope。

## Files in scope (per layer)

### Layer 1 — `Packages/HealthKitService`
- `Sources/HealthKitService/HealthWorkoutRecord.swift` — 三字段 + `SourceDeviceKind` enum
- `Sources/HealthKitService/HealthKitService.swift` — `convertToWorkoutRecord` 增采集；`averageHeartRate(for:)` 新增
- `Tests/HealthKitServiceTests/HealthWorkoutRecordTests.swift` — Codable 向后兼容 + sourceDeviceKind case 覆盖
- `Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift` — L2 cache 回归
- 新增 `Tests/HealthKitServiceTests/HealthWorkoutAvgHRTests.swift`

### Layer 2 — App target
- `VitalStride/Sources/WorkoutListView.swift` — 单 Section 合并；四态银台；authState 分支
- `VitalStride/Sources/HealthKitWorkoutRowView.swift` — avg HR + source badge 消费
- `VitalStride/Sources/WorkoutRowView.swift`（现有）— 挂 App source badge（若已存在源标 diff 最小）
- `VitalStride/Sources/Models/UnifiedWorkout.swift` — 派生 `sourceDeviceKind` 属性
- `VitalStride/Sources/WorkoutListMerger.swift` — 移除 `partitionBySource` **使用点**（函数保留，做既存测试兼容，加 `@available(*, deprecated)` 注释或直接删）
- 新增 `VitalStride/Sources/WorkoutSourceBadge.swift`
- 新增 `VitalStride/Sources/WorkoutListStateBanner.swift`
- `VitalStrideTests/WorkoutListMergerTests.swift` — dedup + 单 Section 断言
- 新增 `VitalStrideTests/WorkoutListRenderingTests.swift` — fixture 复现证据 + 单 Section 断言
- 新增 `VitalStrideTests/WorkoutListStateBannerTests.swift` — 四态断言
- 新增 `docs/reports/018-workout-list-redesign-screenshots.md` — before/after 图 + design review 摘要

## Files NOT to touch

- `Packages/VitalModels/*`, `Packages/AIService/*`, `Packages/VitalUI/*`, `Packages/TelemetryKit/*`,
  `Packages/DesignKit/*` — 稳定层
- `VitalStrideMac/*`, `VitalStrideWatch Watch App/*`, `VitalStrideWidgets/*`
- `VitalStride/Sources/WorkoutCalendarView.swift`（日历模式不动）
- `VitalStride/Sources/HealthKitWorkoutDetailView.swift`（详情页不动）
- `VitalStride/Sources/ActiveWorkout/*`, `WorkoutSessionManager.swift`（实时训练）
- `VitalStride.xcodeproj/project.pbxproj` — §IV，走 `xcodegen generate`

## Cross-cutting bars (必须挂进 acceptance)

- **§I 隐私红线**：健康数值禁进 log / telemetry；新增 test 断言。
- **§V DesignKit token**：徽标背景、心形图标着色、banner 背景全部走 token。
- **G L10n**：新字符串走 `String(localized:)` + `Localizable.xcstrings`；SwiftLint `no_hardcoded_chinese` 硬要求。
- **H Dynamic Type + hit target**：Preview 覆盖 `.large` 与 `.accessibility3`；banner 按钮 ≥44pt。
- **I a11y**：装饰图标 `.accessibilityHidden(true)`；combined label 含 badge 文本 + avg HR。
- **Previews**：每个新 View ≥2 preview；WorkoutListView 覆盖 5 场景（4 状态 + 1 正常混合）。

## Rollout

- Layer 1 独立 PR，merge → Layer 2 rebase 起手。
- Layer 2 PR 描述贴 before/after 截图 + 引用 `docs/reports/018-*.md`；design reviewer 在 PR 上留 comment。
- 无 feature flag（改动前后 UX 差异明确，且用户明确要求呈现改进）。

## Risk & mitigation

| Risk | Mitigation |
|---|---|
| 混合单 Section 后老用户 mental model 断层 | 来源徽标每行清晰可见；design review 抓一次视觉可辨性 |
| avg HR fetch 慢 → HK 载入变慢 | `averageHeartRate(for:)` 与 workout fetch 并发 (`TaskGroup`)，失败/超时 → nil 不阻塞 record 生成 |
| Codable 反解老 payload 失败 → 缓存全部失效 | 三字段 `decodeIfPresent`；`HealthWorkoutCacheTests` 加旧 payload 反解 case |
| Design review 变 blocker → PR 长期挂起 | Design gate 作为 T2 pre-merge 的 acceptance，reviewer 给 direction 而非 pixel-perfect；不通过时回 T2 修，不新开 issue |

## Not planned as separate task

- 用户抱怨的**根因判定**（呈现问题非数据缺失）已在 spec §2 落地，不单独拉 spike 任务。
- `partitionBySource` 函数删除留给 T2；若既有单测仍引用，则保留函数 + 加 `@available(*, deprecated)`，
  由后续 cleanup PR 移除。
