# Research: Reliable Editable Sub-Set Rows

## Decision 1 — Start from current `main`; retain the stopped delivery only as evidence

**Decision**: Base the successor on `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`. Do not reuse or repair candidate `bf66f046a810a368f317e386d7c0504ba41cf2c0` or Draft PR #422.

**Evidence**: Owner-delegated Lead decision `01a138db-f9f3-7bb0-b4da-f8820e91559d` stops MY-1484 after two rounds and authorizes a separately planned version with a normal review budget.

**Alternatives rejected**:

- Third repair round: superseded by the Owner decision.
- Rename the stopped task: would conceal the exhausted review history and violate the successor boundary.
- Use MY-1485: it is an old dependent verification task, not the successor.

## Decision 2 — Reuse the actual `SetRow` composition

**Decision**: Feed pyramid/drop-set identity into the existing standard editable composition. Keep `SubSetRow` only as a thin adapter if retaining it reduces safe call-site churn.

**Evidence**: Current `SetRow` owns real weight/reps inputs, complete menu, completion, smart progression, previous hints, and numeric-keyboard actions. Current `SubSetRow` duplicates row positions with read-only text, a delete-only menu, and separate completion code.

**Alternatives rejected**:

- Restyle `SubSetRow`: leaves two behavior trees and cannot prove shared editable composition.
- Copy editable fields into `SubSetRow`: creates long-term drift and only appearance parity.
- Move the row to `VitalUI`: expands layer/public scope without reuse outside the active-workout app surface.

## Decision 3 — Deepen deletion behind one app-internal request module

**Decision**: Add one app-internal module beginning before policy dispatch and ending after success effects/result construction. `requestDelete(_:)` delegates once; the view applies returned confirmation/focus presentation only.

**Evidence**: Today the section privately spreads policy, mutation, undo, announcement, focus, and callback behavior across request and execution methods. Existing tests can pass by exercising those pieces separately while production wiring remains wrong.

**Alternatives rejected**:

- Call only `performDelete` from tests: skips request policy and does not prove the production contract.
- Put deletion in a row callback: bypasses confirmation, undo, and package ownership.
- Reimplement package cascade/refusal rules: violates the layer boundary.
- Pass focus/confirmation setter callbacks into the seam: hides view mutation inside the service and prevents return-only ownership proof.

## Decision 4 — Use production-hosted XCUITest for menu and committed full swipe

**Decision**: Launch the real app with a DEBUG-only in-memory fixture that renders `ActiveExerciseSection`. Open the actual menu and tap its destructive item; perform a real trailing drag far enough to commit full swipe. Observe an instrumentation decorator around the real seam.

**Evidence**: The stopped recovery tests called stored closures and therefore proved only that a closure could call a spy. They did not prove SwiftUI's production menu/swipe configuration reached `requestDelete` or the real seam.

**Alternatives rejected**:

- Directly invoke a captured callback: repeats the failed evidence pattern.
- Add a hidden test delete button: introduces a non-production route.
- Source-text inspection: does not execute SwiftUI configuration or side effects.
- Unit-host only the row: cannot reliably activate the system menu/full-swipe behavior or provide the same app accessibility space.

## Decision 5 — Measure actual frames in one app coordinate space

**Decision**: Query each actual production action-menu trigger for adjacent standard, pyramid, and drop-set rows using `XCUIElement.frame` after one shared layout pass. The destructive menu items remain separate activation/identity evidence because all three cannot be open simultaneously.

**Evidence**: Existing tests pin a 44-point constant, and stopped recovery evidence used synthesized sequential rectangles or whole-row proxies. Neither detects overhang or neighboring hit/accessibility intersections.

**Alternatives rejected**:

- Reconstruct CGRect values from row height/order: synthetic evidence.
- Host rows in separate controllers: no shared coordinate space or neighboring intersection.
- Measure the whole row: does not identify the actual interactive action-menu trigger.
- Screenshot-only validation: useful visual evidence but not exact hit/accessibility geometry.

## Decision 6 — Compose only cataloged production labels

**Decision**: Build the actual destructive entry from the translated `删除` and `第 %lld 组` app-catalog values plus `SetType.displayName` from the VitalModels catalog. Compose localized fragments directly; do not feed the result back into localization lookup. Keep both catalogs unchanged.

**Evidence**: `删除` and `第 %lld 组` are translated in English and Simplified Chinese, and the package catalog translates pyramid/drop-set type names. The combined `第 %lld 组%@子组，%@` app entry exists but its English value is still untranslated, so it is explicitly not sufficient. Current `SubSetRow` also contains derived interpolated accessibility strings absent from the catalog; production label/value composition—not helper-only string testing—must be acceptance evidence.

**Alternatives rejected**:

- Use interpolation as a localization key: creates an uncataloged runtime key.
- Use the untranslated combined catalog entry: fails the English identity contract.
- Add new keys: unnecessary expansion under the accepted no-catalog-change boundary.
- Assert a standalone helper string: does not prove the production menu entry uses it.

## Decision 7 — Make shared actions explicit without inventing nested children

**Decision**: The one row implementation exposes delete, SetType and RPE menu controls for every row. The child SetType picker is constrained to pyramid/drop-set, and acceptance exercises RPE plus switching between those child types. The same numeric keyboard keeps unilateral editing and copy for children, but add-pyramid/add-drop remain main-row-only.

**Evidence**: This gives children the requested shared editable/menu/completion experience while preserving the repository's flat main-plus-consecutive-children model. Calling the existing add-child path with a child as if it were a parent would introduce an undefined nested-child product behavior outside the Owner decision.

**Alternatives rejected**:

- Offer add-pyramid/add-drop on children: invents nested/sibling semantics not authorized by the package model or Owner decision.
- Remove SetType/RPE from the child menu: retains a behaviorally separate menu and fails shared-menu acceptance.
- Offer working/warmup in the child picker: can promote/detach a child and split the parent run; any promotion workflow is outside this Owner decision.

## Decision 8 — Keep one vertical task

**Decision**: One T001 owns RED, implementation, focused/full verification, and visual evidence.

**Evidence**: The Owner asked for exactly one successor spec/plan/task slice. Row composition, route ownership, and production acceptance are one indivisible user outcome.

**Alternatives rejected**:

- Separate implementation and verification issues: recreates the old dependent MY-1485 shape and allows non-probative implementation evidence to advance.
- Split seam and row tasks: both edit `ActiveExerciseSection` and neither independently delivers the goal.
