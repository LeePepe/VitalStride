# ADR-0016：按任务类型路由 AI，并用反馈动态调权

**状态**：Proposed（待审）
**日期**：2026-07-29
**决策人**：tianpli（项目 owner）
**关联**：[ADR-0005](0005-ai-provider-chain.md)（扩展其 provider chain；并纠正其隐私姿态的记录）

## 背景（Context）

VitalStride 目前有两个 AI provider，藏在 `AIProviderChain` 后面（端侧 `AppleIntelligenceProvider` → 云端 `ZhipuProvider`，见 ADR-0005）。2026-07-28 的审计（`docs/reports/ai-audit-and-apple-models-2026-07-28.md`）暴露了两个问题：

1. **chain 被绕过。** 11 个 AI 调用点里有 10 个直接 `ZhipuProvider(apiKey:)`；只有换动作（`ActiveWorkoutView.swift:986`）走 `AIProviderChain.makeDefault`。也就是说「端侧优先」实际只在一个功能生效，违背了 `AIService/CONTEXT.md` 的红线「chain 顺序不得反转」。
2. **一个 chain 顺序套所有任务——但任务负担不同。** 聊天要低延迟流式 + 强中文长文（云端的强项）；换动作要快、要结构化、不含健康数据（端侧的强项）。单一全局顺序不可能对两者都合适。

Owner 的诉求：**按任务负担路由，但不让调用方决定 provider 或权重**，并且**根据反馈随时间调整这套路由**。最朴素的「同一 prompt 两边都跑、记 log、人工看升/降级」缺一个具体的奖励信号，也缺一个落脚处。

ADR-0005「隐私姿态」一节声称的脱敏（健康值发云端前「分桶、剥离标识符」）**在代码里根本不存在**——原始 `weight×reps`/心率明文发出（`AIPromptBuilder.swift:108`）。修这个脱敏**明确不在本 ADR 范围内**（owner：「先有，再解决脱敏」）；本 ADR 只纠正记录，并保留那条**确实生效**的红线（健康值禁进日志）。

## 决策（Decision）

在 `AIService` 包里引入一个 **`AIRouter`**，坐在 `AIProviderChain` 前面。路由是一个函数：**任务身份 → 需求画像 → provider 能力**，外加一条**反馈回路**随时间调整这套映射。

### 1. 调用方声明「身份」，绝不声明 provider 或权重

```swift
enum AITaskKind: Sendable { case chat, overviewInsights, trainingAdvice, dataTrend, substitute /* … */ }

// 调用方只写这一行。不碰 provider、不碰权重、不碰 chain。
try await aiRouter.execute(.trainingAdvice, messages: msgs)
```

`AITaskKind` 是功能固有的身份（它本来就是那张训练建议卡），不是运行时选择。仅这一步就把 11 个调用点全部收编到同一条路径上，直接关掉问题（1）。

### 2. 一张中央策略表拥有路由（kind → 需求）

由 router（而非调用方）把每个 kind 映射到一个**多维需求画像**，再把画像匹配到 provider 的**能力**。负担不是一个标量：

| Kind | 延迟 | 质量 | 结构化 | 健康数据 |
|------|------|------|--------|---------|
| `substitute` | 交互式 | 低 | 是 | 无 |
| `chat` | 交互式 | 高（中文长文） | 否 | 有 |
| `trainingAdvice` | 后台 | 高 | 是 | 有 |
| `dataTrend` / `overviewInsights` | 后台 | 中 | 是 | 有（聚合） |

能力对比：端侧赢在延迟/结构化（`@Generable` 不会 schema 漂移）/成本/离线；云端赢在中文长文质量。于是 `substitute` → 端侧、`chat` → 云端，是**能力匹配**的结果，而非固定顺序。

### 3. 权重按 **(kind, 设备档)** 分，不是全局

Apple Intelligence 只在 A17 Pro / M1+ 上有，旧设备是 `.unavailable`。所以路由权重必须**按设备能力条件化**，并**存在设备本地**（那个 `cloudKitDatabase: .none` 的库）。同一个 kind，在 15 Pro 上走端侧，在旧机上只能走云端。

### 4. 反馈驱动的权重（一个 per-(kind, 档) 的 bandit）

把每个 `(kind, provider)` 当一个 bandit 臂；臂的选择概率**就是**动态权重。奖励（reward）= 以下信号的加权，从便宜到贵：

- **结构有效性**（免费、客观）：输出能不能 decode 成目标 schema / 过不过 insight 白名单。端侧 `@Generable` 几乎总是有效；云端 JSON 偶尔失败——这个信号今天就能用。
- **用户隐式行为**（免费、真实、现在就可观测）：换动作 → 选了建议之一 vs 退回手动选；聊天 → regenerate/重试 ≈ 不满意。
- **LLM 当裁判**（贵）：夜间离线批处理给两边打分。绝不 inline。

选择用 ε-greedy / Thompson sampling，用一个**保守的静态先验 = 今天的策略**做种子，于是 Day-1 行为等于当前静态路由，再从那里开始学。

### 5. Shadow 评估：采样，别每次都双跑

为了在不付 2× 成本/延迟的前提下对比 provider：**对某 kind 抽样 N% 的请求**，**先**把主 provider 的结果返回给用户，**再** fire-and-forget 跑候选 provider。交互式请求绝不等 shadow。

### 6. 反馈数据的隐私护栏（保留的那条红线）

发云端前脱敏 → 推迟。但 **Constitution 原则 I（健康值禁进日志/持久化 telemetry）不推迟**——它是独立的，继续强制。Shadow/reward 记录只持久化 **metadata + 分数**：

```
task=trainingAdvice provider=apple latencyMs=340 schemaValid=true accepted=true
```

绝不持久化含 `weight×reps`、心率、睡眠等的 prompt/response。LLM 裁判在内存里判完，只落数值结论，进本地 `.none` 库——绝不进云端 telemetry。

### 分阶段落地（Phased rollout）

1. **Router + 静态表** —— 把 11 个调用点全部改到 `AIRouter`；权重先静态。关掉问题（1），并给下面所有东西造好接缝。调用点从此不再改。
2. **被动信号采集** —— 记录 `schemaValid` / 延迟 / `accepted`。不改路由。
3. **采样 shadow**（+ 可选的离线 LLM 裁判）。
4. **开启 bandit** —— 权重真正动起来。

## 后果（Consequences）

### 正面
- 端侧优先对**所有** AI 功能生效，不再只一个——兑现 CONTEXT.md 红线。
- 路由逻辑收进一张表，可独立测试；调用点从此与 provider 无关。
- per-(kind, 档) 权重 + bandit = 自调质量，无需手维护 if-else。
- 静态先验意味着 Day-1 零行为变化；风险靠后续阶段逐步 opt-in。
- `AIRouter` 这条接缝正是未来端侧 `@Generable` 路径（报告 Part 2）和 provider 无关的 `LanguageModelSession`（WWDC26）接入的地方。

### 负面
- 在现有 chain 之上多了一层间接（`AIRouter`）；活动部件更多。
- bandit/telemetry 必须严格无健康值——每次改 reward schema 都是一次真实的 review 负担。
- shadow 双跑即便 fire-and-forget 也增加采样成本。
- 静态需求表是人工维护的产物，可能与现实漂移；bandit 修的是权重，修不了「需求本身声明错了」。

### 接受的取舍
- **需求画像用手写静态表**，不从请求特征自动估算（token 数是弱负担代理）。静态表打底，bandit 在上面做动态修正。
- shadow 是**采样**而非穷举——用更慢的收敛换有界的成本。
- 发云端前脱敏继续推迟；本 ADR **不**声称它存在（不同于 ADR-0005 §Privacy）。

## 对 ADR-0005 的纠正

ADR-0005「隐私姿态」一节称健康值发云端前已脱敏/分桶。**这从未实现。** 本 ADR 把它记为一个已知 gap，且不修它。等脱敏真正落地时，另写一份 ADR 并更新 ADR-0005 的状态。在那之前，实际生效的隐私边界是：端侧优先路由 + 用户显式同意门（`aiPrivacyConsentKey`）+ 健康值禁进日志。

## 实现引用（待创建）

- `Packages/AIService/Sources/AIService/AIRouter.swift`（新 —— router + 策略表）
- `Packages/AIService/Sources/AIService/AITaskKind.swift`（新 —— kind 枚举 + 需求）
- `Packages/AIService/Sources/AIService/AIProviderChain.swift`（现有 —— router 委托给它）
- Reward 存储：`VitalModels` 里一个本地 `cloudKitDatabase: .none` 的 SwiftData 实体（新）
- 11 个现有调用点（迁移到 `AIRouter.execute`）：见报告 §1.2

## 重新审视的触发条件（Revisit triggers）

- 第三个 provider 落地（报告 Part 2 / roadmap US2-A）—— router 表加一列。
- 采用 WWDC26 provider 无关的 `LanguageModelSession` —— router 可能并进它。
- 脱敏实现 —— supersede ADR-0005 §Privacy。
- bandit 明显不如静态 —— 把权重钉死，保留接缝。
