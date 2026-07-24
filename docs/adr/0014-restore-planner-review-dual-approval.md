# ADR-0014: 恢复 Planner Lead 规划审 + AI Reviewer/TL 双批准门

**Status**: Accepted
**Date**: 2026-07-24
**Supersedes**: 部分修正 AI Reviewer 的「Plan/Decomposition Review removed」内部决定

## Context

VitalStride 的 spec-driven 开发 pipeline 是 `TL → Planner → FS → Reviewer`（宪法 §Issue
Tracker）。此前某个阶段 **AI Reviewer 的 agent prompt 单方面写入**了一段「Plan Review 和
Decomposition Review 已移除，不再有 Planner Lead 产出规划可审」——理由是「拆分交给 spec-kit
设计期 `tasks.md` + `check-tasks-fresh` 防腐 + TL sync-check 就够了」。

这造成两个问题：

1. **与宪法/AGENTS.md 不一致**：宪法 §Issue Tracker 与 AGENTS.md 一直写着 pipeline 含 Planner
   Lead 环节，但 AI Reviewer 拒绝审规划，pipeline 描述与 agent 实际行为冲突。
2. **阻断了「spec 流程自动化」目标**：owner 的意图是让相似的 spec 流程由 agent 自动跑完整闭环
   （Planner 规划 → 独立 reviewer 审 → TL 审 → 双批准 → 派发）。AI Reviewer 退出规划审 =
   闭环缺一环，规划质量只剩 TL 单方把门，无独立第二视角。

触发事件：owner 复活 Planner Lead（加入 Dev Team squad、换 claude-opus-4.7），让其对 MY-1311
（spec 015 GlitchTip 崩溃上报）做规划复审 + DoR 补全。AI Reviewer 按旧 prompt 拒审，暴露此矛盾。

## Decision

1. **恢复 AI Reviewer 的规划 / DoR 复审能力**。AI Reviewer 承担两类 review：
   - **Code review**（默认，主体工作）——审 FS 产出的 PR。
   - **Planning / DoR review**——当 Planner Lead 产出或补全任务拆分并 @mention 时，按设计期 spec
     （`specs/NNN-*/spec.md` + `plan.md` + `tasks.md` on `github/main`）+ 宪法
     §Cross-Cutting Quality Bars 审 DoR 硬合同（Files in scope / Files NOT to touch /
     Public signatures / Functional acceptance criteria ≥3 / Verification command），产出与
     code review 同样的 verdict（✅ APPROVED / 🟡 CHANGES REQUESTED + 具体 blocker）。

2. **建立 AI Reviewer + Team Lead 双批准门**。Planner Lead 的规划 / DoR 补全产出后，**下游 stage
   派发前**须 AI Reviewer 与 Team Lead **两方都批准**。任一方 CHANGES REQUESTED → 回 Planner Lead
   修订，不派发。批准落地后由 **TL** 执行派发（reviewer 与 planner 均不自行派发）。

3. **设计期防腐机制保留**：`check-tasks-fresh` 防腐 check + TL sync-check 仍生效；规划审是**在其
   之上的额外质量 pass**，不是替代。

4. **TL 遇「缺可执行拆分」自动触发 Planner，不升级 human**（2026-07-24 补丁）。当一个 spec-driven
   issue 缺少可执行的 spec/plan/tasks，或有跨 layer scope 需要拆分时，Team Lead 的动作是
   **@mention Planner Lead** 产出 speckit 拆分 + DoR，而**不是**升级给 owner、也**不是** @Hermes
   （Hermes 不是本 workspace 成员）。Planner 产出再走 Decision 2 的双批准门。
   - **根因**：修复前 TL / AI Reviewer 的 agent prompt 都写死了「Planner Lead has been removed /
     no planner to @mention / @Hermes to re-run tasks」，导致缺 spec 的 issue（MY-1301 停滞 4 天、
     MY-1311）只能反复升级给 owner、pipeline 无法自主收口。此补丁把这三处反转为「@Planner Lead」。
   - 唯一仍需 human 的是**本质需要人的任务**（如 MY-1284 CloudKit 双设备物理验证），非「缺拆分」。

5. **auto-merge 收尾盲区：TL 在 review PASS 后主动检查 PR 是否已被机器合并并收尾**（2026-07-24 补丁）。
   本 repo 用 GitHub auto-merge，PR 由**机器**在 required check 全绿后自动合并——**没有 agent 被这个
   merge 事件触发**。TL 的旧逻辑假设"自己 `gh pr merge`"，于是 review PASS 后干等、PR 被 auto-merge
   悄悄合掉、issue 永远卡 `in_review`（MY-1316 卡 55min、MY-1327 同病）。修复：TL 在 🟢 PASS 后
   **主动**执行：`gh pr view <PR#> --json state` → 若 `MERGED` 则立即收尾（issue 转 `done` + promote
   下一 stage backlog→todo），不等自己 merge；startup scan 也要捞"PR 已 merged 但 issue 仍 in_review"
   的收尾遗漏。配套 `.github/workflows/auto-merge.yml` 的 `enable-auto-merge` step 加 retry 消化
   GitHub 5xx 瞬时故障（504 曾让 PR #334 卡 43min）。

6. **派发 FS 用 assign+todo，不靠裸 @mention**（2026-07-24 补丁）。TL 派实现给 Fullstack Engineer 时，
   若只 @mention 而 issue `assignee_type=none`，**不会 enqueue FS run**——issue 停在 `todo`、零 run
   （MY-1314 裸 @mention 后跨 3 轮 sweep 零 run）。可靠派发 = `multica issue assign <key> --to "Dev
   Team"`（或 Fullstack Engineer）+ `multica issue status <key> todo`，再 `issue runs` 验证有
   queued/running，零 run 则 `rerun` 兜底。裸 @mention 只作人读备注，不是触发器。
   - **全局铁律（2026-07-24 强化）**：此规则**适用所有分支**——普通 stage、repair/follow-up、
     re-dispatch。MY-1330（review 后 P0 补救 issue）暴露 TL 的 repair 分支仍走裸 @mention，导致
     FS 跨 3+ 次 TL 尝试零 run、反复升级 owner。TL prompt 已在 §Agent Identity 顶部加**全局派发铁律**
     覆盖所有 "@mention Fullstack Engineer" 场景：一律 assign+todo+验证 runs，未见 queued/running
     不算派发成功、不得因此升级 owner。（实测：owner 直接 assign FS→FS 秒起，证明 FS 可触发，卡点
     纯粹是 TL 用了不 enqueue 的裸 @mention。）

## Consequences

**正面**：
- pipeline 行为与宪法/AGENTS.md 一致；规划质量有独立第二视角（本轮 TL 已抓出 spec FR-4 的 DSN
  硬编码矛盾 + §V narrow 例外被验收越界，证明双审有效）。
- spec 流程可由 agent 跑完整闭环，达成 owner 的自动化目标。

**负面 / 成本**：
- 每个走规划审的 feature 多一次 AI Reviewer run（token + 时延）。对 bug-fix fast-path（TL 直接拆）
  不强制走规划审，仅 spec-driven feature 的 Planner Lead 产出才触发。
- 双批准门增加一次往返；但换来的是派发前的质量收敛，避免 FS 拿到有矛盾的 DoR 返工。

**红线不变**：§I 健康隐私、§V narrow 例外等仍是规划审与 code review 的权威 finding 源
（§Cross-Cutting Quality Bars）。

## Alternatives considered

- **维持现状（TL 单方把门）**：规划质量无独立第二视角，且与文档冲突。否决——不满足自动化闭环目标。
- **让 Planner Lead 自审**：自己审自己无独立性。否决。
- **新建专门的 plan-reviewer agent**：增加 agent 数与维护面；AI Reviewer 已有宪法 finding 源上下文，
  扩展其职责更内聚。否决新建，选择扩展 AI Reviewer。
