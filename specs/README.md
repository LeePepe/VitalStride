# specs/

VitalStride 使用 [spec-kit](https://github.com/github/spec-kit) Spec-Driven Development 流程。

## 目录约定

| 目录 | 用途 |
|------|------|
| `000-baseline-existing-codebase/` | 现有代码库的 audit baseline（spec as documentation + plan as gap analysis）。**不要修改**，作为后续 feature 的回归基线。 |
| `001-future-roadmap/` | V2+ 未来功能 roadmap（**umbrella / planning-only**，承接已删除的 `docs/DESIGN.md`）。不入 Multica；功能启动时 fork 出 `002+` 独立 spec。 |
| `002-*` / `003-*` / ... | 具体 feature（可从 `001` roadmap fork）。每个 feature 一个目录，编号自增。 |

## 一个新 feature 的标准流程

1. `/speckit-specify <feature description>` → 生成 `specs/NNN-name/spec.md`
2. `/speckit-clarify`（可选）→ 与用户确认模糊点
3. `/speckit-plan` → `plan.md`
4. `/speckit-tasks` → `tasks.md`（每个 task ID 形如 `[T### ] [Story] Brief`）
5. **不跑 `/speckit-implement`** — VitalStride 走 Multica TL → FS → Reviewer pipeline（Constitution §Development Workflow）。
6. 用 `multica-quick-issue` 把 tasks.md 批量入 Multica project `7adf8b88`。

## 关键约束

- 任何 spec / plan / tasks **必须** reference Constitution 章节（不要重述规则）。
- 任何与 Constitution 冲突的内容 → 先改 Constitution（走 ADR + 版本 bump），再写 spec。
- Issue 标题：`[T###] [Story] Brief description` —— spec-kit handoff 约定。
- AI Reviewer / TL 唯一权威 finding 源是 Constitution §Cross-Cutting Quality Bars。

## Spec 写作规则（防返工）

> 来源：spec 015（GlitchTip 崩溃上报）规划走了 6 轮双批准，事后复盘——6 轮里约 4 轮在补
> spec 本可一次写清的东西。以下规则直接针对那些病根，写 spec / tasks 时照做，减少 Planner ↔
> Reviewer 往返。

1. **消灭"如 / 或 / 评估 / 按需 / 可选"——每个决策落一个确定值。** spec 是决策记录，不是选项菜单。
   留一个"或"给下游 = 留一轮 blocker。
   - ❌ "放 Info.plist 键（**如** `GlitchTipDSN`）**或** xcconfig"
   - ✅ "Info.plist 键 `GlitchTipDSN`，值 `$(GLITCHTIP_DSN)`；`GLITCHTIP_DSN` 由 CI 从 GitHub
     secret 注入 `fastlane beta`"

2. **验收手段本身必须合宪。** 写验收前自问"这个验证动作违红线吗"。
   - ❌ 用 `SentrySDK.capture(message:)` 验证——它是通用消息事件，越过 §V "仅 crash/hang" 红线。
   - ✅ 用受控 crash/hang 验证。

3. **易变的具体值（密钥 / DSN / URL / 绝对路径）不进 spec 正文**，用占位符 + 指向来源。
   完整 DSN 贴 spec 里既是隐私问题，又制造"不硬编码"自相矛盾。

4. **写 tasks 时预先分层，一个 task 不跨 layer。** 跨了当场拆，别等 TL 打回。
   spec 015 因 DSN 供值（CI/fastlane）与 app 接线混在一个 child，被 TL 打回拆出独立 CI child。

5. **spec / plan / tasks 必须 reference 宪法章节**（见上），且 acceptance ≥3 条、可测。

6. **规划粒度线：精确算法 / 数据契约类需求 → 规划到"接口契约 + 测试矩阵齐全"就派发，逐字段实现
   交 FS 用 TDD。** 不要在 DoR 文字里把脱敏算法抠到编译级——spec 015 的 Round 3-5 就是在文字上
   逐字段对 sentry-cocoa header 打磨，这类精度用"代码 + 测试驱动"收敛比用"规划文字"收敛更快更准。
   - **例外**：§I 健康隐私 / §V 等**红线相关**的契约，规划阶段就要把"必须清空/拒绝哪些字段"的
     **意图和测试用例**写死（错了是 P0 事故）；但**具体逐字段映射**仍可留给 FS 按真实 API TDD 落地。


## 参考

- Constitution: [.specify/memory/constitution.md](../.specify/memory/constitution.md)
- spec-kit skill: `~/.hermes/skills/software-development/spec-kit/SKILL.md`
- ADR archive: [docs/adr/](../docs/adr/)
