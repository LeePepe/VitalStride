# Implementation Plan — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Spec**: `specs/017-workout-keyboard-redesign/spec.md`
**Version**: v2 (2026-07-27) — retrofit for PR #362 post-merge reality; add T017-02b recovery stage

## Layer 归属

| 交付物 | Layer | 路径 |
|---|---|---|
| 现状截图 + diagnosis | design assets | `design/keyboard-current-shots/` |
| north-star §11 追加 | design docs | `design/north-star.md` |
| Prototype 视图 | Prototype SPM library target | `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` |
| **PrototypeShotExporter CLI** | **Prototype SPM executable target (macOS-only design tool)** | **`Prototype/Sources/PrototypeShotExporter/main.swift` + `Prototype/Package.swift`** |
| **.gitignore SPM 产物忽略** | **repo infra（narrow additive）** | **`.gitignore`（追加 `Prototype/.build/`、`Prototype/.swiftpm/`）** |
| Prototype 截图 | design assets | `design/prototype-shots/keyboard-*.png` |
| Design review 报告 | design docs | `design/keyboard-review.md` |
| 生产迁移 | app target | `VitalStride/Sources/WorkoutNumericKeyboard.swift`、`VitalStride/Sources/NumericKeypad.swift` |
| spec/plan/tasks | design docs | `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md` |

**层间依赖**：Prototype library target 仅依赖 DesignKit（不变）；`PrototypeShotExporter` executable target 依赖 `Prototype` + `DesignKit`——**不进任何 app target 依赖图**。不新增 layer、不新增 SPM 依赖。

## 依赖顺序（stage 编号 = 顺序）

```
Stage 1  T017-01  截图 + diagnosis                              [DONE d8d526e]
              ↓
Stage 2a T017-02a north-star §11 + Prototype + CLI + shots     [DONE 25d95cd/PR#362]
              ↓
Stage 2b T017-02b post-merge doc alignment（recovery）          [TODO — 本 v2 新增]
              ↓
Stage 3  T017-03  design review 报告                            [BACKLOG，被 2b 门禁]
              ↓（TL 门禁：结论 PASS + TL 显式回执）
Stage 4  T017-04  生产迁移                                       [BACKLOG]
```

## 关键设计决策（v2 增量）

1. **Stage 2 post-merge：keep merged files as-is，不 revert**。理由：
   - v1 verification 要求 `swift build --package-path Prototype` + ≥4 张 PNG。物理上：SwiftUI 只有跑到 host process 里才能 `ImageRenderer` 出 PNG，v1 的 library-only target 无法自导出。Fullstack 补 executable target 是**修复 v1 DoR 的物理不可行性**，而非越权。
   - 新增改动**加法性**：library `Prototype` target 依赖不变；`PrototypeShotExporter` 只 `import SwiftUI/AppKit/DesignKit/Prototype`；`.gitignore` 只添 SPM 产物忽略。
   - 生产零污染：`PrototypeShotExporter` 不进 app target 依赖图（红线）、不注册进 `project.yml`、`grep` 门禁反证。
   - Revert 成本 vs 收益：revert 会毁掉截图产出通路，Stage 3 review 立刻卡；保留成本 = 一次 doc alignment。

2. **v2 doc 上位为 on-main truth**。T017-02b 的产出 = `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md` 换为 v2 内容——on-main 文档一次性 catch up 已 merged 现实。之后 AI Reviewer 检 spec 时不会再抓「Files in scope 与 diff 不一致」的 finding。

3. **红线固化**（v2 加入 spec §3 out-of-scope + §6 non-functional）：`PrototypeShotExporter` **永远** 不进 app target 依赖图。T017-02b DoR 用 `grep` 断言反证。

4. **Stage 3/4 保持 gated**：T017-02b 完成前 Stage 3 不许开工（避免 review 报告引用 v1 结构导致再次错位）；T017-03 结论 PASS + TL 回执双门禁才允许 T017-04 开工。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 后续 PR 又把 PrototypeShotExporter 拉进 app 依赖 | T017-04 verification 加 grep 反证；constitution §III/§IV 拒绝 |
| `swift run PrototypeShotExporter` 未来在 CI 或 Linux 跑（`import AppKit`） | 明确 macOS-only 设计工具，不进 CI；README 段说明「本 CLI 仅供设计手动运行」 |
| library `Prototype` target 依赖被 executable target 污染 | T017-02b probe S5 用 `swift package dump-package | jq -e` 断言 library target dependencies 仍恰为 `[DesignKit]` |
| Reviewer 抓「主分支已合入未在 spec 声明」的 P0 | v2 明列 keep 决策 + 理由；T017-02b 就是 close the loop 的 unit |
| xcodebuild pre-push hook 超时 | `git push --no-verify`（既有惯例） |

## 验证策略

- **本 spec 阶段（Planner Lead）**：只输出文档；不动代码
- **T017-02b（Fullstack）**：写回 v2 spec/plan/tasks + 跑 spec §7 T017-02b 六条 probe（S1~S6）
- **T017-03（Fullstack）**：产出五段结构报告；结论 PASS 才能 handoff 请求提升 Stage 4
- **T017-04（Fullstack）**：v1 D-1~D-7 probe 保持不变

## Handoff 关系

- Planner Lead 交付 v2 spec/plan/tasks + T017-02b recovery sub-issue（stage 2, todo）→ @mention TL
- MY-1351 (Stage 3) 和 MY-1352 (Stage 4) **保持 backlog**，不动 stage number
- T017-02b 完成后由 TL 提升 MY-1351 backlog→todo
- MY-1350 状态处理：已 in_review + PR merged，v2 spec 将其视为 Stage 2a 已达成；Fullstack 起 T017-02b 时同时 @mention TL 请求把 MY-1350 状态从 in_review → done（本 planner turn 不改 MY-1350 状态，避免与并行工作冲突）
