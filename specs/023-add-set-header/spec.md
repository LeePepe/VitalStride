# Feature Specification: Add Set Action in Exercise Header

**Feature Branch**: `023-add-set-header`

**Created**: 2026-08-25

**Status**: Candidate for planning review

**Input**: MY-1474 — move the “add set” action from `Section` content into the corresponding exercise header so it is not an editable/movable list row.

**Constitution refs**: Principles II, III, and VI; Cross-Cutting Quality Bars A, G, H, I, and K; ADR-0014 planning review gate.

## User Scenarios & Testing

### User Story 1 - Add a set without creating an editable row (Priority: P1)

During an active workout, the user adds a set from the exercise header. The action remains available beside the exercise title and action menu, while the list content contains only real set and sub-set rows.

**Why this priority**: The current action is treated as list data during edit mode, exposing a move affordance for something that is neither an exercise nor a set and consuming an unnecessary row.

**Independent Test**: Open an active workout with one exercise and at least two sets, enter edit mode, and confirm that only set rows participate in list editing. Activate the header action once and confirm exactly one main set is appended with the same defaults and continuous ordering as the existing add-set behavior.

**Acceptance Scenarios**:

1. **Given** an exercise section with set rows, **When** the active workout enters edit mode, **Then** the add-set action remains in the section header and has no row move affordance or drag behavior.
2. **Given** a last main set with existing input defaults, **When** the header add-set action is activated once, **Then** exactly one new main set is appended, it inherits the same default fields as the current behavior, and its order is continuous.
3. **Given** a long exercise name, Dynamic Type, or Large Mode, **When** the header renders, **Then** the exercise title, add-set action, and existing exercise menu remain usable without overlapping controls.
4. **Given** VoiceOver is enabled, **When** focus reaches the add-set action, **Then** it exposes the localized add-set label and insertion hint as one button with a hit target of at least 44 by 44 points.

### Edge Cases

- A long localized exercise name must yield layout space before either header control becomes clipped or overlapped.
- Repeated activations append one main set per activation; a single activation must never append more than one.
- Existing sub-sets do not change which main-set defaults are copied by the add operation.
- The exercise action menu and its replace, substitute, and delete behavior remain unchanged.

## Requirements

### Functional Requirements

- **FR-001**: The add-set action MUST be rendered inside the corresponding `ActiveExerciseSection` header.
- **FR-002**: The `Section` content closure MUST contain set and sub-set rows only; the add-set action MUST NOT be a list content row or participate in edit-mode movement.
- **FR-003**: Activating the header action MUST call the existing add-set behavior exactly once and preserve its main-set default-copy and continuous-order semantics.
- **FR-004**: The header MUST continue to contain the exercise title and existing exercise action menu without changing the menu’s behavior.
- **FR-005**: The add-set action MUST expose the existing localized VoiceOver label and hint and a minimum 44 by 44 point hit target.
- **FR-006**: The header MUST remain usable under Dynamic Type and Large Mode; controls MUST not overlap, and the title MUST adapt before control hit targets shrink.
- **FR-007**: The implementation MUST reuse existing localized strings; no localization catalog change is authorized for this slice.
- **FR-008**: The change MUST NOT alter public API, set/sub-set models, the `ActiveWorkoutView` exercise-reorder algorithm, or any package layer.
- **FR-009**: Regression coverage MUST fail on the current content-row structure before production changes, then cover header placement, absence from content rows, single-append semantics, copied defaults, and continuous order.
- **FR-010**: The moved action MUST discard list-row-only layout/background/separator behavior and retain the existing normal/large × light/dark preview matrix with header-accurate descriptions.

### Key Entities

- **Exercise section header**: The non-data container for the exercise title, add-set action, and existing exercise action menu.
- **Set content row**: A real main-set or sub-set row rendered inside the section content and eligible for list row behavior.
- **Add-set operation**: Existing internal mutation that appends one main set using the last main set’s defaults and the next continuous order.

## Success Criteria

### Measurable Outcomes

- **SC-001**: In edit mode, zero add-set controls appear as movable list rows; all real set rows remain present.
- **SC-002**: One activation appends exactly one main set with copied defaults and continuous order in automated AppUI regression coverage.
- **SC-003**: The MY-1474-declared iPhone 16 Simulator test and the formal AppUI iPhone 17 test gate both complete successfully after implementation.
- **SC-004**: iPhone 16 Simulator before/after light and dark evidence shows the header controls do not crowd or overlap and the set list no longer spends a full row on the add action.
- **SC-005**: Accessibility evidence demonstrates a minimum 44-point target, Dynamic Type usability, and the expected VoiceOver label and hint.

## Scope Boundaries

### In scope

- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`
- This feature’s Spec Kit planning artifacts under `specs/023-add-set-header/`

### Out of scope

- `ActiveWorkoutView` exercise reordering
- `Packages/**`
- Set or sub-set data models and defaulting policy
- Exercise action-menu redesign
- New localization copy or catalog changes
- macOS/watchOS-specific UI work

## Assumptions

- MY-1474 intentionally supersedes only the placement contract from historical spec `017-add-set-button-redesign`; that earlier visual-design record remains unchanged.
- The iOS app target already includes both production and test paths through `project.yml`; no XcodeGen change is needed.
- The current add-set behavior is the source of truth for copied defaults and ordering; this feature changes placement, not policy.
