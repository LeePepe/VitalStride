# Implementation Plan — 017 训练页 WorkoutNumericKeyboard 视觉重设计

**Spec**: `specs/017-workout-keyboard-redesign/spec.md`
**Version**: v1 (2026-07-27)

## Layer 归属

| 交付物 | Layer | 路径 |
|---|---|---|
| 现状截图 + diagnosis | design assets | `design/keyboard-current-shots/` |
| north-star §11 追加 | design docs | `design/north-star.md` |
| Prototype 视图 | Prototype SPM package | `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` |
| Prototype 截图 | design assets | `design/prototype-shots/keyboard-*.png` |
| Design review 报告 | design docs | `design/keyboard-review.md` |
| 生产迁移 | app target | `VitalStride/Sources/WorkoutNumericKeyboard.swift`、`VitalStride/Sources/NumericKeypad.swift` |
| spec/plan/tasks | design docs | `specs/017-workout-keyboard-redesign/{spec,plan,tasks}.md` |

**层间依赖**：Prototype 仅依赖 DesignKit（已在 `Prototype/Package.swift`）；生产迁移仅依赖已有 layer。**不新增 layer、不新增 SPM 依赖**。

## 依赖顺序（stage 编号 = 顺序）

```
Stage 1  T017-01  截图 + diagnosis
              ↓
Stage 2  T017-02  north-star §11 + Prototype + prototype 截图
              ↓
Stage 3  T017-03  design review 报告（对照 north-star + audit + a11y）
              ↓（TL 门禁：结论 PASS + TL 显式回执）
Stage 4  T017-04  生产迁移 WorkoutNumericKeyboard + NumericKeypad
```

无并行。每 stage 一个 sub-issue，均在 Dev Team squad 内 leader 委派。

## 关键设计决策

1. **隔离 prototype 而非直接改生产**：审计（`design/keyboard-redesign-audit.md`）已修 P0 theme 断链，但视觉打磨若直接改生产 `WorkoutNumericKeyboard.swift` 会：(a) 无法双色截图对比，因为 preview 在 `#if canImport(UIKit) && !os(macOS)` 里；(b) review 反复迭代污染 git 历史；(c) 视觉未定型就动生产会触发多轮契约回归担忧。用 `Prototype/` SPM 隔离：改视图 → export preview → 双色截图 → review → 定型 → **一次性**迁移生产。

2. **north-star §11 而非独立文档**：`design/north-star.md` 已是 app 级 scorecard（`design-reviewer` 打分依据），键盘子章节挂在同一文档里，未来任何触及键盘的改动都用同一 north-star 对齐。

3. **客观 review 报告结构固定**：`## vs north-star` / `## vs audit` / `## a11y` / `## 高度实测` / `## 结论`——这五段是硬门禁（spec §7 C-2）。避免「感觉可以了」这种主观判断。

4. **契约冻结用 grep 门禁**：spec §7 D-3 用 `git diff github/main...HEAD` grep `func on*` / `enum LeftKeyAction` / `case addPyramid` 等——回调签名、枚举 case 若被删或改，probe 立刻失败。

5. **spec/plan/tasks 三文件在 T017-01 就归位**：审计的经验教训（RETRO 2026-06-26）——PRD 内容不 tail-write，Fullstack 起手就要 spec/plan/tasks 全套；T017-01 的 DoR 之一就是把这三文件 commit。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| Prototype 复制 SetField/LeftKeyAction/PresetRepBucket 与生产 drift | Prototype 里明确注释「视觉原型，不引用生产枚举；迁移时以生产枚举为准」。契约本身冻结（spec §3）→ 不会 drift 出问题 |
| 双色截图导出流程未定 | tasks.md T017-01 / T017-02 明确用 Xcode Preview 右上角 export 或 `.exportPreviews()`。若 preview 导出受限，用真机 `deploy-to-phone.sh` 截图（现仓库有此脚本）作为 fallback |
| review 报告 PASS 主观 | 报告结构固定五段；`## 结论 PASS` 是 grep 门禁（C-3）；TL 二次确认才能提升 T017-04 |
| 迁移引入回归 | D-1 build + D-2 三个现有测试全跑 + D-3~D-7 grep 门禁；如新增 view snapshot 测试不成本可接受，补一条 UIKit `WorkoutNumericKeyboard.init(...)` 构造烟测 |
| xcodebuild 在 workdir 内跑：pre-push hook 超时 | 现有 workflow `git push --no-verify`（RETRO 已记录）；build 用 `-skipPackagePluginValidation` |

## 验证策略

- **本 spec 阶段（Planner Lead）**：只输出文档；不动代码。tasks.md 完成即 handoff。
- **T017-01 / 02 / 03（Fullstack）**：产出截图和文档；每 stage `swift build --package-path Prototype`（Stage 2）作为编译门禁；文档类 stage 用 spec §7 的 grep probe 自查。
- **T017-04（Fullstack）**：spec §7 D-1 ~ D-7 全部 probe 通过；契约冻结用 `git diff` 反证；PR 挂到 MY-1342 metadata `pr_url`。

## Handoff 关系

- Planner Lead 交付 spec/plan/tasks + 4 个 sub-issue（stage 1 = todo，stage 2/3/4 = backlog）→ @mention Team Lead
- 每 stage 完成，Fullstack @mention Team Lead → TL 提升下一 stage backlog→todo
- Stage 3 → Stage 4 之间**多一道门禁**：TL 必须验 `design/keyboard-review.md` 结论 PASS 才提升
