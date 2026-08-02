# Ruflo 在 VitalStride 的评估（2026-08-02）

评估对象：ruflo v3.32.9（homebrew global），`ruflo init --no-signup --no-skills-sh`。

## 结论

**保留，与 Multica dev team 共存**（用户决定，2026-08-02）。分两条车道：

- **ruflo = 直接手下** — 日常对话、`/deep-research`、语义 memory
- **Multica dev team = 外包团队** — `/multica-issue` → issue → PR，流程不变

理由：唯一不重叠的能力（语义 memory）确有价值，用车道隔离换取它，而不是二选一。
代价（190+ command 常驻 context）先接受，观察实际使用习惯后再裁剪。

## 实测到的事实

### 有效的部分

- **语义检索是真的**：存入「ADR-0005 声称的健康数据脱敏未实现…」，用措辞完全不同的
  「健康隐私合规风险」查询，命中，score 0.49，**4ms**。384 维向量，HNSW。
  这确实是当前文件式 `memory/*.md` + 手写 MEMORY.md 索引做不到的。

### 代价

| 项 | 实测 |
|---|---|
| 创建文件 | 107（init 报告）/ git 可见新增 259 |
| skills | 30 个，568K |
| commands | **148 个**，728K |
| agents | 17 个，336K |
| 磁盘 | `.claude` 2.1M + `.swarm` 3.0M + `ruvector.db` 1.5M + `.claude-flow` 64K |
| context | init 后一次性向 session 注入 190+ 条 skill/command 定义 |

### 三个具体问题

1. **`.mcp.json` 没被创建**
   init 输出明确写 `MCP: .mcp.json`，但文件不存在，`claude mcp list` 里也没有 ruflo。
   即"装了 = 能用 MCP 工具"不成立，必须手动补：
   ```bash
   claude mcp add ruflo -s local -- npx ruflo@latest mcp start
   ```
   补完确实 ✔ Connected。

2. **`.gitignore` 没被更新**
   `.claude-flow/`、`.swarm/`、`ruvector.db` 全部裸露在 `git status`。
   在一个禁止直接 commit main、走 PR 的 repo 里，这是每次 `git status` 的持续噪音。

3. **agent 命名冲突：`planner`**
   ruflo 的 `.claude/agents/core/planner.md`（type: coordinator，"AI-powered resource optimization"）
   与已有的 `~/.claude/agents/planner.md`（与 codex plan-reviewer 协作、写 plan 文件）同名。
   project 级优先于 user 级 → **本 repo 的 planner 被静默换掉**。
   这个 planner 是 team-lead pipeline 的一环，替换后 pipeline 行为改变且无提示。

   **已处理**：改名为 `ruflo-planner.md`（frontmatter `name:` 同步改）。
   ruflo 升级或 `init --force` 后需重查此冲突。

4. **route hook 不是调度器**
   `UserPromptSubmit` 的 route hook 对每条 prompt 都跑（matcher 为空）。但
   `.claude/helpers/router.js` 只有 105 行，头注释明确写：

   > `Static keyword router... NOTE: This is *not* a learned model. It is a heuristic
   > table; "confidence" is reported as a heuristic prior, not a calibrated probability.`

   `confidence: 0.6` 是硬编码常量。它只 `console.log`、不 block、**输出无人消费**。
   推荐的 8 个 agent（coder/tester/reviewer/researcher/architect/backend-dev/
   frontend-dev/devops）**不含 Multica 或 dev team**，结构上无法做车道分流。
   关键词表全英文，中文 prompt 基本走默认分支（实测「好」→ `coder / 0.3`）。

   用户选择保留（当人肉提醒）。**其输出应忽略，不作为车道判断依据。**

### 未改动的（好消息）

- `CLAUDE.md` — 未改（init 的 "Skipped: 2" 之一）
- `.gitignore` — 内容未改
- `~/.claude/CLAUDE.md` — 未改
- `.claude/settings.local.json` — 保留

## 与现有编排的重叠

VitalStride 已有：AGENTS.md（24K）+ 分层文档 + 三段门禁 + Multica dev team + speckit +
30 余个 subagent。ruflo 带来的 swarm / hive-mind / SPARC / topology / consensus 与之
**功能重叠而非互补**，且两者都想当编排层。

真正不重叠的只有 memory 向量检索一项。

## 采取的措施（共存方案）

1. **`.gitignore`** — 加入 `.claude/`、`.claude-flow/`、`.swarm/`、`ruvector.db`。
   ruflo 配置纯本地，换机器重跑 `ruflo init`。不入 repo 的理由：每次 ruflo 升级会产生
   190+ 文件的巨大 diff，且 CI 的 lint/policy 可能扫到。
2. **`planner` 改名** — `ruflo-planner.md`，解除与 team-lead pipeline 的静默覆盖。
3. **MCP 手动注册** — `claude mcp add ruflo -s local -- npx ruflo@latest mcp start`。
4. **route hook 保留** — 但其输出忽略（见上文第 4 点）。
5. **148 command + 30 skill 全留** — 观察实际使用习惯后再裁剪。

### 待办

- 全局 `~/.claude/CLAUDE.md` 的 Ruflo Integration 段落提到的 MCP 工具，在**其他未 init 的
  项目**里依然不可用。该段落是全局的，但 ruflo 只在 VitalStride init 了。
- ruflo 升级 / `init --force` 后需重查 `planner` 冲突（改名会被覆盖回去）。

备份在 `/tmp/ruflo-eval-backup/`（CLAUDE.md、.gitignore、global-CLAUDE.md、settings.json）。
