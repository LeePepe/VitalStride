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
| TEMP-PRELAUNCH 扫描 | `scripts/ci/scan-temp-prelaunch.sh`(ci.yml「Lint & policy」用 `enforce`;testflight.yml 用 `audit`) | PR + 发布 | 否 |
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
(宪法 I)没有任何自动化强制。现在扫描逻辑落在 `scripts/ci/scan-temp-prelaunch.sh`,
覆盖 app targets + `Packages` 的 `.swift`。

**两种模式,因为「发布前」在本项目里有两个含义:**

| 模式 | 命中时行为 | 用在哪 |
|---|---|---|
| `audit`(默认) | 打印清单 + workflow warning,**exit 0** | `testflight.yml`(内测分发) |
| `enforce` | 打印清单 + **exit 1** | `ci.yml`「Lint & policy」(每个 PR,2026-08-16 起) |

TestFlight 内测跑 `audit`:spec.md:144 界定例外成立的前提是「未发布、单用户(项目
owner 自用)」,而 **TestFlight 内测就是该阶段的分发方式**。在内测路径上硬阻塞等于
在例外窗口内禁止一切分发,恰好废掉例外本身的用途。命中仍然全量打印,不会悄悄堆积。

### 2026-08-16:PR 路径由 audit 升为 enforce(MY-1390 / Stage 6e)

升级依据:Stage 6c-6e 已把受控例外**清零** —— `RoutingSignalEntry` 的 raw 调试字段
连同 AIService 侧全部 raw 承载类型与写入点一并移除,`SCAN_PATHS` 内 `TEMP-PRELAUNCH`
命中数 = 0,FR-018 永久态达成。**例外窗口关闭之后,「不挡 PR」的理由随之消失**:此前
挡 PR 会拦住正在合入的、spec 逐字批准的 raw 字段;现在没有合法的待合入例外了,任何
新出现的命中都只可能是回归。

因此 `ci.yml` 的「Lint & policy」job 新增一个 `enforce` step,**每个 PR 都跑**。这是
清零之后唯一的防回归护栏 —— 否则红线只剩文档,下一个 PR 就能悄悄把 raw 字段加回来。

`testflight.yml` 第 122 行**保持 `audit` 不变**:内测分发路径的语义没有变,那里的
阻塞代价与本门无关(且真有残留时 PR 门早就先红了)。同一脚本、两种模式、两条路径,
不要合并。

FR-017 说的「上架」= App Store 提交。`fastlane/Fastfile` 目前只有 `beta` lane
(`upload_to_testflight`),没有提交 lane;提交 lane 落地时同样要在其之前接上
`enforce`,与 PR 门形成前后两道。

两种模式都**不 fail-open**:扫描路径缺失(目录改名 / checkout 布局变化)或 grep
执行出错(rc >= 2)一律 `exit 1`,拒绝在扫描范围残缺的情况下继续。

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
