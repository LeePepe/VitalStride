# Implementation Plan: VitalStride Future Roadmap (Sequencing & Reuse Map)

**Spec**: [`spec.md`](./spec.md)

**Created**: 2026-07-04

**Status**: Roadmap plan (planning-only — 非 build plan，非 gap analysis)

**Constitution Version**: 2.0.0

---

## Purpose

这**不是** gap analysis（`000-plan` 那种"已实现 vs 应实现"的差距分析）——roadmap 里的功能尚未启动，套 gap 模板会空转。本 plan 承担三件对 roadmap 有价值的事：

1. **Reuse/Extension Map** — 每个未来功能将扩展哪个文件、落在哪个 layer、是否需要新 package / ADR。
2. **Constitution Compliance Pre-Check** — 每个功能预判是否触碰红线（前瞻，非事后审计）。
3. **Fork Sequencing** — fork 出独立 spec 的建议顺序与依赖前置。

功能真正启动时从本 roadmap fork 出 `specs/00N-<name>/`（编号从 `002` 起），届时才写可执行 spec + tasks + Multica issue（见 spec §Roadmap Framing 的 fork 契约）。

---

## Reuse / Extension Map（未来将改哪里）

| 功能 | Story | 扩展点 / 落点 | Layer | 新 package / ADR? |
|------|-------|--------------|-------|-------------------|
| 手动补录 | US1 | `WorkoutSource.recorded`（复用）+ 新建录入 UI | VitalModels + app | 否 |
| 力竭组 Failure | US1 | `SetType` 加 `failure` case + 量统计规则 | VitalModels + app | 否（枚举扩展） |
| 超级组 Superset | US1 | 复用 dropSet/pyramid 子组关联模型 + UI 重构 | VitalModels + app | 否 |
| 多日 Routine | US1 | 扩展单层 `WorkoutTemplate` → 多日 | VitalModels + app | ⚠️ 若需新 `@Model` 则需 ADR（III/IV） |
| 多 AI Provider | US2 | 实现 `AIProvider` 协议接入 `AIProviderChain` | AIService | 否（协议扩展，禁新 SDK/新包） |
| 去重增强 | US2 | 扩展 `WorkoutListMerger`（叠时间窗口，不替换 UUID 去重） | app | 否 |
| 有氧发起 | US3 | 比照力量训练发起路径 + GPS 数据流 | app + HealthKitService | ⚠️ GPS 存储评估（比照 ADR-0003 降采样） |
| 社交/分享 | US3 | 新建分享 UI + 摘要生成（去健康数值） | app | 否 |

---

## Constitution Compliance Pre-Check（前瞻，非事后）

| 功能 | 红线 | 预判 |
|------|------|------|
| 多 AI Provider | **Principle V** | 只能走 OpenAI-compatible REST via URLSession，禁第三方 AI SDK；key 存 Keychain。fork 时须在 spec 显式挂约束。 |
| 社交/分享 | **Principle I** | 分享 payload 禁含原始 HealthKit 数值；生成路径须过隐私 review。 |
| 多日 Routine / 新数据模型 | **Principle III/IV** | 若引入新 SwiftData `@Model`，须走 ADR + 迁移评估 + 更新 `project.yml`。 |
| 有氧发起 GPS 存储 | **Principle I + ADR-0003** | GPS 轨迹入 CloudKit 须降采样控制配额；轨迹数据隐私约束比照健康数据。 |
| Failure / Superset | — | 纯枚举/关联模型扩展，内聚 VitalModels，无红线。 |
| 手动补录 / 去重增强 | — | 复用现有实体，无红线。 |
| 所有 packages 改动 | **Principle II** | Swift 6 strict concurrency，新类型须 Sendable。 |

---

## Fork Sequencing（建议顺序与前置）

启动无强制排期（由产品决策驱动），但存在**技术前置依赖**：

1. **可即刻 fork（零前置）**：Failure Set、手动补录 —— 纯扩展现有实体，最低风险，适合作首批 fork 验证 roadmap→spec 流程。
2. **有软前置**：
   - **多日 Routine** 依赖现有 `WorkoutTemplate` 结构稳定；若同期有 Template 相关改动，先让其落定。
   - **去重增强** 有**硬前置**：需先拿真实 Apple Watch + 码表双记录数据，验证 HealthKit `startDate/endDate` 与 FIT 时间戳精度差异，再定 ±5min 窗口阈值。数据验证未完成前不 fork 实现。
   - **超级组** 需 UI 重构（组间交替节奏），比 Failure/dropSet 重，建议在训练录入 UI 稳定期做。
3. **最大范围、最可能重估**：有氧发起（新 GPS 数据流）、社交分享（新出域面）—— 建议最后 fork，且 fork 前重新评估是否仍符合"个人健康数据收集"产品定位。
4. **多 AI Provider**：无技术前置，但每加一个 provider 是独立小 fork（可 `002-provider-deepseek` / `003-provider-openai` 分开），不必一次性做完。

---

## Not Doing

- 不跑 `/speckit-tasks`（功能未启动，无 implementation tasks）。
- **不入 Multica**（fork 出独立 spec 时才录 issue —— 见 spec §Roadmap Framing）。
- 不跑 `/speckit-implement`。
- 不重做已实现部分（UUID 去重、dropSet/pyramid、Zhipu+AppleIntelligence —— 见 spec §Out-of-Scope）。

---

## References

- Spec: [spec.md](./spec.md)
- Constitution: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)（Principle I / III / IV / V）
- Baseline（已实现基线）: [specs/000-baseline-existing-codebase/](../000-baseline-existing-codebase/)
- 双数据源 / CloudKit 降采样: [docs/adr/0003-healthkit-swiftdata-dual-data-source.md](../../docs/adr/0003-healthkit-swiftdata-dual-data-source.md)
- AI provider chain: [docs/adr/0005-ai-provider-chain.md](../../docs/adr/0005-ai-provider-chain.md)
