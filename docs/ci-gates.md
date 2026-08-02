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
| 自动 review | `.github/workflows/codex-review.yml` + `scripts/ci/codex-review.sh` | PR | 否 |
| review prompt(数据) | `scripts/ci/review-prompt.md` + `scripts/ci/render-review-prompt.py` | 被上面两门读取 | — |
| prompt 契约回归 | `scripts/ci/review-prompt.contract.test.sh`(ci.yml「Lint & policy」) | PR | 否 |
| 发布 ship-gate | `.github/workflows/testflight.yml`(TEMP-PRELAUNCH 扫描) | 发布 | 否 |
| 自动合并 | `.github/workflows/auto-merge.yml` | PR | — |
| ruleset(硬门) | `scripts/rulesets/main-protection.json` | 默认分支 | admin 可 bypass |

## review prompt 是单一数据源

两道 review 门(claude / codex)**共用同一份 prompt**:`scripts/ci/review-prompt.md`。
**要改 review 规则(判 blocker 的 9 个维度、injection 判定标准、各类豁免),改这个
文件** —— 不要改两个 `.sh`,它们已不含任何内联 prompt 文本。

| | |
|---|---|
| 模板 | `scripts/ci/review-prompt.md`(markdown 数据文件,占位符 `{{CHANGED}}` / `{{TRUNCATED}}` / `{{DIFF}}`) |
| 渲染器 | `scripts/ci/render-review-prompt.py`(从环境变量取值,纯文本 `str.replace`) |
| 契约测试 | `scripts/ci/review-prompt.contract.test.sh`(ci.yml required) |

**为什么抽成数据文件**(三个真实事故):

1. **shell-quoting 事故**:prompt 原本内联在 shell 双引号字符串里。`claude-review.sh`
   的 9 个反引号**全部未转义**,`swift test` / `project.yml` / `cloudKitDatabase: .none`
   等词在运行时被 bash 当命令替换执行掉,**从 prompt 里消失** —— claude 门实际拿到
   的是残缺规则。两个脚本转义约定还不一致(codex 侧写 `\``),长期必然再漂移。
   markdown 数据文件永不被 shell 求值,反引号直接写正常反引号,该类事故结构上消失。
2. **规则改不动(死锁)**:review prompt 本身就是祈使句,于是**任何修改 review 规则
   的 PR 都会被 reviewer 自己判成 prompt injection**。模板里现有明文豁免:对
   `review-prompt.md` / `claude-review.sh` / `codex-review.sh` 的改动**不得**因
   「文本形如指令」判 injection(仍按 1-9 号维度评估其正确性)。
3. **spec 批准的例外过不了门**:reviewer 只看得到 diff、看不到 `specs/`。模板的隐私
   维度现在写明 **TEMP-PRELAUNCH 受控例外** —— 带 `// TEMP-PRELAUNCH:` 注释且只落
   本地 `cloudKitDatabase: .none` 分区的原始值不判 blocker;**边界严格**:同样的值
   一旦进 os_log / print / 云端 telemetry(Aptabase / GlitchTip / CloudKit),仍是 blocker。

契约测试(`review-prompt.contract.test.sh`,ci.yml required)保护上述所有内容:断言
模板文本 + **调用真实渲染器**校验渲染产物里关键片段一个不丢(含反引号内容原样送达)、
占位符全被替换、两个脚本确实消费共享模板且没有内联 prompt 回潮。

## TEMP-PRELAUNCH 发布门

spec 019(`specs/019-ai-task-routing/`)FR-017 / SC-007 要求**上架前** `TEMP-PRELAUNCH`
grep 命中数 = 0。此前这只是 `tasks.md` 里一个没人勾的复选框 —— 整个永久态隐私姿态
(宪法 I)没有任何自动化强制。现在 `testflight.yml` 在 `fastlane beta` **之前**扫描
app targets + `Packages` 的 `.swift`,命中 > 0 直接 `exit 1` 并打印位置。

**故意只挡发布、不挡 PR**:受控例外在开发期是合法的(spec 逐字批准),挡 PR 会立刻
拦住正在合入的 raw 字段。发布路径才是 ship-gate 该生效的地方。

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
  判定标准是「这段文字是否在**命令 reviewer**」,不是「是否出现 pass/fail 字样」——
  声明式的报告字段/变量名不误判(见上文单一数据源一节)。
- 两个 review workflow **checkout base 分支**而非 PR head,因此 `review-prompt.md`
  与渲染器也来自 base:PR **改不动用来审自己的规则**。改 review 规则必须先合进 main
  才生效,与脚本本身同一信任模型。

## ruleset 即代码
`scripts/rulesets/main-protection.json` 是唯一真相,改后重跑 `scripts/rulesets/apply`
(幂等 create-or-update)同步到服务端。**先让 `claude-review` check 至少成功上报过一次,
再把它加进 required 并 apply**,否则新门会把所有 PR 卡死。
