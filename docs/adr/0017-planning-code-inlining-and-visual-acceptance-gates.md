# ADR-0017: Planner 不内联可编译代码 + 纯视觉验收走模拟器 snapshot

**Status**: Accepted
**Date**: 2026-07-31
**Amends**: Constitution §DoR 硬合同、§Cross-Cutting Quality Bars（新增 K）；AGENTS.md human 升级措辞 + Planner Lead 职责行

## Context

两个来自 pipeline 实跑的复盘，暴露了规划与验收环节的两处设计缺陷。

### 缺陷 1：Planner 在 DoR 文档内联可编译代码 → 规划审递归

MY-1369（[Planning] Produce executable breakdown for MY-1368）的 planning child 跑了 **6 轮 revision / 11 个有效 run**，撞上 run-count guard 后升级 human。逐轮看 AI Reviewer 的 blocker：

- **R1**（5 个）：结构性——XcodeGen scope 自相矛盾、UI-test 入口不在 scope、RED 阈值、验收覆盖、workflow。一次给全，合理。
- **R2/R3**：改了 scheme 才暴露 selector / 插入值问题。**真·内容依赖**，串行难免。
- **R4**：seed fixture 用了不存在的 `init` 标签 `primaryEquipment:` / `primaryMuscleGroup:`（真实是 `muscleGroup:` / `equipment:`）。
- **R5**：seed 又用了不存在的枚举 case `MuscleGroup.quads`（真实只有 `.chest/.back/.shoulders/.legs/.arms/.core/.fullBody`）。

R4/R5 的共性：Planner 在 spec/tasks 里**内联了"必须能编译"的 Swift seed 代码**，但这些编译级事实（`init` 标签、枚举 case）**在写下那一刻 `grep` 一次就能确认**。Planner 没查，把自查外包给 reviewer；reviewer 又做增量审（每轮只看上轮 findings + 新 HEAD），于是像"修一个 error 重编一次报下一个"一样递归。类比：好的编译器一次列出所有 error。

根因链：**计划越界写了实现代码 → 才需要编译级审查 → 才递归**。Planner Lead 职责本就写着"不写代码"（AGENTS.md），但没有明确禁止"内联可编译片段"，也没要求"引用符号前先核验源码"。

### 缺陷 2：纯视觉验收门写死真机 → runtime 无真机造出永久死结

MY-1352（键盘生产迁移，纯视觉 token 迁移）的 PR #368 已 **green CI auto-merge**（2026-07-27），但 issue 一直开着，卡在验收门要求的"真机 light/dark before/after 截图"。Fullstack Engineer 实证 runtime 无此能力：`xcrun devicectl list devices` 6 台全 `unavailable`、`libimobiledevice` 不在 PATH、无 deploy 脚本 / UDID。于是每次 rerun 都只能重复升级 human，形成**任何 agent 都过不去、只能永远等人**的死结。

矛盾点：同一 repo 的 `specs/017-add-set-button-redesign`（同类纯视觉改动）AC-M1 写的是"iPhone 16 **Simulator** before/after 截图"——正确做法。keyboard stage 写"真机"属标准不一致。而 AGENTS.md"只有本质需要人的任务（如物理设备验证）才升级 human"这句，给了"写死真机"一个看似合理的借口。

## Decision

### D1：DoR 硬合同新增两条红线

1. **Planner 不内联实现级代码**：spec/plan/tasks 只写契约级描述（seed 什么、触发什么、断言什么），禁止内联"必须能编译"的 Swift 片段（具体 `init` 标签、枚举 case、fixture 字面量）。实现细节留给 GREEN 阶段由编译器兜底。确需示意时用非编译伪码 + `// 示意，非最终签名`。
2. **写前核验源码**：引用任何具体符号（类型 / `init` 签名 / 枚举 case / 方法名）前，必须先 `grep`/`git show` 对着真实源码确认存在，不得凭记忆写。规划审对"符号是否存在"一次性全量核验，不做增量逐个抓。

### D2：新增 Quality Bar K — 纯视觉验收用模拟器 snapshot

纯视觉改动（token 迁移、配色 / 圆角 / 间距 / 字号、无逻辑变更）的 before/after 验收，默认标准 = iPhone Simulator（如 iPhone 16）light/dark 截图或 SnapshotTesting 用例，非真机。验收门禁止对纯视觉改动写死 real-device / 真机。真机验收仅保留给模拟器测不了的能力：触觉反馈、传感器、后台唤醒、真机性能 / 热。

### D3：同步收紧措辞

- AGENTS.md human 升级句：明确"物理设备验证"不是纯视觉改动的默认门。
- AGENTS.md Planner Lead 职责行：加"只写契约级描述，禁内联可编译片段，引用符号前先核验"。
- 修 `specs/017-workout-keyboard-redesign/tasks.md` Stage 4 门：真机 → 模拟器。

## Consequences

- **正向**：规划递归收敛（编译级错误在 Planner 侧一次自查掉，不再逐轮 reviewer 抓）；纯视觉 stage 能在无真机的 runtime 里自动收口，不再无谓升级 human。
- **代价**：Planner 需多花 `grep` 核验成本（但远低于多轮规划审往返）。
- **不影响**：真正需要真机的验收（如 spec-018 Apple Watch + HealthKit 真机复现——HK 授权 / Watch 配对模拟器测不了）仍走真机，Quality Bar K 明确豁免这类。
- **历史处置**：MY-1352 由 Workspace Owner 按 Quality Bar K 批准豁免真机门、收口 done。

## Alternatives Considered

- **给 runtime 接真机**：成本高、维护重，且对纯视觉改动是过度手段。模拟器 snapshot 对确定性像素比对已充分。
- **只改 keyboard spec 不改宪法**：治标不治本，下一个纯视觉 stage 会重犯。规则须升到 Quality Bar 层。
- **允许 Planner 内联代码但要求先本地编译**：Planner Lead 定义就是"不写代码 / 不 push"，给它加编译职责等于让它越界成 FS。契约级描述 + GREEN 兜底是更干净的边界。
