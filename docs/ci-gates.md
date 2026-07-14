# CI 门禁与自动化(gates & automation)

本仓库的合并门禁分三层:**本地 hooks**(快、可绕)、**GitHub Actions**(服务端、
不可绕)、**GitHub ruleset**(把关键 check 变成合并硬门)。

## 一图

```
建 PR ──► auto-merge.yml     → 立即挂上 squash auto-merge(draft 除外)
       └►        → 现有 CI(构建/测试等)
       └► claude-review      → self-hosted 本机跑 claude,发 review;critical→红
                                      │
        ruleset「main protection」要求:上面这些 check 全绿 + 分支与 base 同步
                                      ▼
                            门皆绿 → 自动 squash 合并 + 删分支
```

## 门层

| 层 | 文件 | 触发 | 可绕? |
|---|---|---|---|
| 自动 review | `.github/workflows/claude-review.yml` + `scripts/ci/claude-review.sh` | PR | 否 |
| 自动合并 | `.github/workflows/auto-merge.yml` | PR | — |
| ruleset(硬门) | `scripts/rulesets/main-protection.json` | 默认分支 | admin 可 bypass |

## 自动 review 是怎么工作的

- 跑在**维护者本机的 self-hosted runner**(标签 `vitalstride-mac`)。
- 用你**已登录订阅**的本地 `claude` CLI,**不需要 ANTHROPIC_API_KEY**。
- `claude -p --json-schema` 产出确定性 verdict:发现 **critical/high** → 脚本 `exit 1`
  → 该 check 变红 → auto-merge 被 ruleset 挡住。仅 notes → 通过。
- **runner 离线 = 该 check 不上报 = PR 卡住不合并**(设计如此:没机器 review 过就不合)。

### 首次安装 runner
```bash
./scripts/ci/setup-runner.sh
cd $HOME/actions-runner-vitalstride-mac && ./svc.sh install && ./svc.sh start
```

### 安全(public repo + self-hosted 的高危组合)
self-hosted runner + `pull_request` + checkout PR head = 公认高危:step 执行的是 PR 版本的代码。
本仓库的**信任边界放在 workflow YAML**(`pull_request` 事件下 YAML 由 base 分支评估,fork 改不到),
**不放在被 checkout 的脚本里**:
- `claude-review` job 有 `if: head.repo.full_name == github.repository` —— fork PR 的代码**一行都不在本机执行**。
- fork PR 改由 `claude-review-fork` job(GitHub 托管 runner)只发提示 + 上报同名 check,留人工。
- 仓库设置把 outside collaborators 的 workflow 设为需人工批准
  (`actions/permissions/fork-pr-contributor-approval = all_external_contributors`)。
- review prompt 显式声明 diff 为**不可信数据**,防止 PR 内对抗性文本诱导 `verdict=pass`。

## ruleset 即代码
`scripts/rulesets/main-protection.json` 是唯一真相,改后重跑 `scripts/rulesets/apply`
(幂等 create-or-update)同步到服务端。**先让 `claude-review` check 至少成功上报过一次,
再把它加进 required 并 apply**,否则新门会把所有 PR 卡死。
