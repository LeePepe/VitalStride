# ADR-0020: Codex required，Kimi advisory，暂停 Claude review

**Status**: Accepted
**Date**: 2026-08-26
**Supersedes**: ADR-0009 中关于 Claude + Codex 双 required review 的门禁组合

## Context

owner 决定暂停当前 Claude review，保留一个强制 AI review，并增加不阻塞合并的第二视角。
现有 Claude CLI 通过本机代理运行，模型路由与仓库注释不一致；此前在小型 diff 上也反复耗尽
900 秒。继续把它设为 required 会让模型供应和 runner 故障直接冻结 shipping。

同时审计发现，现有 Codex workflow 使用 `pull_request`。虽然 job checkout base script，
同仓库 PR 仍可修改 workflow YAML 和 run steps；当 Codex 成为唯一 required AI check 时，
该控制面必须迁移到由默认分支评估的 `pull_request_target`。

## Decision

1. 暂停 Claude PR workflow，并从 required status checks 移除 `claude-review`。
2. Codex 是唯一 required AI review。构建、测试、lint、policy gates 继续独立 required。
3. Kimi Code K3 作为 advisory review：
   - 使用显式 tool-less agent（`tools: []`、`subagents: []`）；
   - 只读取 trusted base context 与围栏内 PR diff；
   - findings、timeout、CLI/parse failure 都只留 sticky comment，不满足或阻塞 required gate；
   - `kimi-review` 永不进入 ruleset required checks。
4. Codex 控制面按两阶段迁移，避免 required check 自锁：
   - Stage A：保留旧 `codex-review` 以审并合入新的 `codex-review-target`
     `pull_request_target` workflow；
   - Stage B：新 workflow 至少成功上报一次后，ruleset 改 require
     `codex-review-target`，再停用旧 `pull_request` workflow。
5. repo 内 ruleset policy、AGENTS 和线上 ruleset 必须同步；advisory workflow 的存在不产生
   required 身份。

## Consequences

- Claude 或 Kimi 不可用不会冻结 shipping；Codex 和确定性 CI 仍会阻止不合格改动。
- Kimi findings 是给 TL/owner 的第二视角，不能被 PR Manager 当作强制失败。
- Stage A 期间旧 Codex 控制面仍存在已知风险，时间只覆盖 target workflow 的 bootstrap；
  Stage B 是本 ADR 的必做收尾，不是可选 follow-up。

