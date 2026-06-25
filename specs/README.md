# specs/

VitalStride 使用 [spec-kit](https://github.com/github/spec-kit) Spec-Driven Development 流程。

## 目录约定

| 目录 | 用途 |
|------|------|
| `000-baseline-existing-codebase/` | 现有代码库的 audit baseline（spec as documentation + plan as gap analysis）。**不要修改**，作为后续 feature 的回归基线。 |
| `001-*` / `002-*` / ... | 新 feature。每个 feature 一个目录，编号自增。 |

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

## 参考

- Constitution: [.specify/memory/constitution.md](../.specify/memory/constitution.md)
- spec-kit skill: `~/.hermes/skills/software-development/spec-kit/SKILL.md`
- ADR archive: [docs/adr/](../docs/adr/)
