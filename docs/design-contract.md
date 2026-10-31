# VitalStride ActiveWorkout List Cohesion Design Contract

## Authority and scope

- Surface: iOS ActiveWorkout multi-exercise list, including sticky exercise headers,
  `SetRow`, `SubSetRow`, numeric input pills, and the custom keyboard dock.
- Goal: `vs-list-cohesion-1101`; design revision `des-r1`; baseline
  `c4b72fc126ba8d60a13cfb0fd43ff86612498805`.
- Visual mode: **Strata-Core**. Content surfaces are solid; no glass on lists,
  rows, cards, inputs, or keyboard keys.
- This contract is upstream of implementation and tests. Existing assertions that
  conflict with this contract are deprecated and must be rewritten before they can
  block delivery.
- Constitutional alignment: privacy, strict concurrency, package boundaries,
  i18n, PR-required delivery, Quality Bars H/K, and spec-first workflow remain
  mandatory; this document does not relax them.

## Stage 1 — visual diagnosis

The list currently fragments into alternating card and background trenches, splits
drop-set identity between leading and trailing columns, wraps long exercise titles,
wastes header width around adjacent actions, and gives short numeric values oversized
inner fields. The target is a continuous base plane with self-contained row cards,
one leading identity slot, a dense single-line header, tightly clustered actions,
and content-hugging numeric fields inside independent hit targets.

## Stage 2 — token and geometry lock

| Area | Contract |
|---|---|
| Base plane (R28) | `theme.neutrals.bg` is the shared opaque plane for `List`, `ActiveExerciseSection` header, and every section/row `.listRowBackground`. No two-tone trench. |
| Row cards | Each `SetRow` and `SubSetRow` is a rounded solid `theme.neutrals.card` card on the base plane; radius `12–16pt`; spacing between exercises `10pt` normal / `14pt` large. |
| Sticky header | Opaque `theme.neutrals.bg`; dense single row, max height `44pt`, vertical padding `<=4pt`; it fully occludes rows while pinned. |
| Header title (R27) | `.lineLimit(1)`, `.minimumScaleFactor(0.85)`, `.truncationMode(.tail)` in every mode; no two-line title variant. |
| Header actions (R26) | `+` and `⋯` share one centered compact cluster, each visual frame is `28–30pt` wide × `>=44pt` high (`headerControlHeight`), container spacing is `0–2pt`, visual gap `<=6pt`; retain independent `>=44×44pt` hit targets and no overlap. |
| Shared row grid | One centered axis: leading identity/completion → weight → reps → actual metadata/actions. Inter-slot gap `6–8pt`; input-internal gap `2–4pt`. |
| Sub-set identity (R29) | `1.1`/`1.2` appears exactly once in `leadingControls`, beside completion, aligned with the parent index column. Remove the trailing metadata identity and its geometry capture. `↳` is not required when the hierarchical label is present. |
| Visual input | Solid `theme.neutrals.inset` pill, radius `8pt`, `36pt` normal / `42pt` large height; digits use body-equivalent typography and monospaced digits. |
| Inner numeric width (R26) | `WorkoutSetInput` hugs numeric content: `24–32pt` normal and `32–42pt` large, with a deterministic cap based on the displayed value/placeholder. Never assign the outer hit-target width to the inner field. |
| Outer numeric target | Composite weight/reps pill owns `minWidth/minHeight >=44pt` and `contentShape(Rectangle())`; taps anywhere on prefix, digits, unit, or padding focus the inner field. |
| Typography | Primary numerics `17pt` normal / `22pt` large; units/prefixes `11–12pt` / `14–15pt`; no text below `11pt`; accent ratios remain `<=1.8:1`. |
| Vertical rhythm | One vertical padding layer only; row minimum `48pt` normal / `56pt` large. No negative padding, hidden reserved slots, or zero-gap row compression. |
| Separators | Hide system row and section separators; do not add a competing divider or double containment. |

## Semantic token mapping

All implementation colors must resolve through existing theme/design tokens; no raw
Hex/RGB literals or app-local token tables are permitted.

| Meaning | Token |
|---|---|
| Continuous page/list plane | `theme.neutrals.bg` |
| Solid row card | `theme.neutrals.card` |
| Input visual surface | `theme.neutrals.inset` / `theme.surface` |
| Primary title and digits | semantic primary text token |
| Units, hints, progress | semantic secondary text token |
| Completion and hierarchical identity | semantic accent token |
| Filled interactive action | `interactiveAccent` + `onInteractiveAccent` |
| Disabled/loading content | semantic disabled token |

## State and appearance matrix

| State | Light | Dark | Invariant |
|---|---|---|---|
| Populated | Solid base plane, raised row cards, visible exercise grouping | Same geometry and token roles with dark neutral values | At least two exercises remain unmistakably grouped without trenches. |
| Empty | Opaque header, reason text, one add-set CTA | Same hierarchy and contrast | No hidden footer or inactive slot reserves height. |
| Loading | Geometry-matched skeleton for header and rows | Same skeleton geometry | CLS is zero; no title/action reflow. |
| Error | Inline reason and retry action preserving grid | Same hierarchy and contrast | Error copy does not displace numeric columns or hit targets. |

Review all states in Normal/Large Dynamic Type and LTR/RTL where applicable.

## Container-driven width and text rules

Derive available single-line width as container width minus outer insets, inter-slot
gaps, fixed controls, icon visual widths, and hit-target reservations. Do not size
from an ideal short title.

1. **Compact schema labels:** CJK `<=4` characters; English `<=6–8`; longer
   explanations move to a dedicated row, hint, or semantic icon.
2. **Metric readouts:** deterministic maximum digits/precision/unit template,
   `.layoutPriority(1)`, and zero numeric truncation; never emit `…`.
3. **Dynamic titles:** isolate unbounded titles in a dedicated row or
   `ViewThatFits`; this surface specifically locks the exercise header to
   `1-line`, tail truncation, and `minimumScaleFactor(0.85)` rather than allowing
   a second header line.

## Scenario → component and motion mapping

| Scenario | Component | Motion |
|---|---|---|
| Live telemetry/progression hint | Input placeholder, keyboard action, or compact metadata slot | Numeric text transition only; no inline suggestion chip. |
| Dense single-hand entry | Outer composite numeric pill + focused inner field | Pointer-down `scale(0.97)`, `100–120ms`, no spatial travel. |
| Expand/collapse sub-rows | Shared-grid `SubSetRow` with leading `1.1` identity | Spring `response 0.28–0.32`, damping `0.84–0.86`; Reduce Motion uses crossfade. |
| Sticky multi-exercise scrolling | Opaque `exerciseHeader` on unified base plane | No background color jump; header remains stable while pinned. |
| Bottom inset arbitration | Single ordered safe-area stack: content → toast → dock → keyboard/system safe area | Inactive slots collapse to zero height; no overlay collision. |
| Filter/substitute sheets | Native sheet/popover using injected theme and color scheme | Present from trigger; pause transient toast while modal is active. |

## Accessibility and device tiers

- Tier 1 compact portrait: one column, thumb-reachable actions, every interactive
  target `>=44×44pt`.
- Tier 2 wide touch: preserve the shared grid; do not stretch a full-width bottom
  action across landscape/iPad.
- Tier 3 desktop pointer: preserve semantic order and use pointer/keyboard focus
  affordances; no bottom floating primary action.
- Numeric input and header actions expose accessible labels and follow visual order.
- Reduce Motion removes spatial insertion animation while retaining state clarity.

## Deprecated Test Assertions to Remove/Rewrite

The following legacy assertions are explicitly superseded by this contract:

| Exact citation from `receipts/explore-r1.md` | Required disposition |
|---|---|
| `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift:15-75` — card header background, 44pt action frames, and two-line title assumptions | Rewrite for unified `theme.neutrals.bg`, compact adjacent action cluster, opaque single-line title, and independent hit targets. |
| `VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift:68-84` — `ActiveWorkoutHitTarget.numericInputSide == 45` / fixed inner field width | Replace with content-hugging inner width plus outer composite pill `>=44×44pt` and tap-to-focus behavior. |
| `VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift:50-64` — independent visual pill and hit-target assertion | Retain and adapt; this is aligned with the new contract. |
| `VitalStrideTests/Sources/ActiveWorkoutRowLargeModeTests.swift:179-275,449-505,636-680,1023-1190` — fixed inner widths, header wrapping, card row-background assumptions | Rewrite around the unified base plane, single-line title, content-hugging inputs, and container-driven budgets. |
| `VitalStrideTests/Sources/ActiveWorkoutRowLargeModeTests.swift:697-805` — `drop1Controls["footer"]` / footer-era geometry | Remove footer assertions; assert shared parent grid and leading hierarchical identity. |
| `VitalStrideTests/Sources/ActiveWorkoutRowLargeModeTests.swift:810-950` — `frames["suggestion"]`, descriptor ordering, and fixed 44pt frames | Remove chip/descriptor geometry; retain only four-slot layout, text budgets, and independent target checks. |
| `VitalStrideTests/Sources/SubSetReadOnlyTests.swift:43-60` — shared-grid/no-footer contract | Retain and update naming if needed; add the single leading `1.1`/`1.2` identity invariant. |
| `VitalStrideTests/Sources/SubSetReadOnlyTests.swift:43-60` — any `↳`-only or inner `numericInputSide` assumptions | Rewrite to permit a cohesive `1.1`/`1.2` leading label and content-hugging inner fields. |
| `VitalStrideTests/Sources/DesignEcoSnapshotTests.swift:318,366` — legacy `add-set`/`menu` width `>=44pt` assertions | Rewrite to the compact header contract: visual width `>=28pt` and height `>=44pt` (`headerControlHeight`), preserving independent hit-target coverage. |

## Acceptance and evidence

Implementation must produce simulator snapshots with at least two exercises visible
in light/dark and Normal/Large modes, including the sticky header and expanded
sub-set. The reviewer must confirm: no two-tone trenches, no duplicate identity,
no title wrap, no oversized action gap, no numeric ellipsis, and no lost hit target.
Pure visual acceptance uses iPhone Simulator light/dark snapshots, not a physical
device requirement. The design-contract static checker must report zero raw color
violations and all required sections present.
