# Exercise Catalog Full Replacement Design

**Date:** 2026-08-17

**Status:** Approved for implementation planning

**Upstream:** `hasaneyldrm/exercises-dataset` at commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`

## Goal

Replace every VitalStride exercise that corresponds to the pinned upstream dataset with the upstream record, import every upstream record that is currently absent, and leave VitalStride-only exercises unchanged.

The replacement is data-only in this delivery. The ten-language instructions are stored in the bundled catalog for later product use; no exercise-detail UI is added.

## Confirmed Product Rules

1. All 1,324 records from the pinned upstream snapshot are represented in the generated catalog.
2. An existing matching preset keeps its VitalStride stable UUID, Chinese exercise name, default weight values, repetition defaults, and `mediaKey` because upstream does not provide equivalent values.
3. Upstream-owned fields replace their VitalStride equivalents: English name, category/body part, equipment, primary target, secondary muscles, instructions, instruction steps, source identity, timestamps, and media attribution metadata.
4. VitalStride-only presets and all custom exercises remain unchanged.
5. Upstream records missing from VitalStride are added with deterministic UUIDv5 identifiers. Because upstream has no translated exercise names, their Chinese display name falls back to the English name.
6. Media paths, media ID, and attribution are retained as metadata. Image and GIF files are not downloaded, bundled, or displayed.
7. `target` is the primary muscle. `secondary_muscles` is the secondary list. `muscle_group` is preserved as the upstream primary-synergist field and is never promoted to the primary muscle.

## Why This Approach

### Selected: pinned snapshot plus generated complete catalog

The repository records an upstream commit and SHA-256 digest, transforms the snapshot deterministically, and bundles the complete result. This provides offline behavior, reviewable diffs, reproducible builds, and an explicit migration boundary.

### Rejected: runtime upstream loading

Fetching upstream JSON at runtime would make seeding network-dependent and allow the catalog to change without an app release. It also complicates migration recovery and provenance.

### Rejected: retain the reduced VitalStride schema only

Keeping only the existing fields would discard the ten-language instructions, upstream taxonomy, and attribution. It would not constitute the requested full replacement.

## Catalog Architecture

The bundled catalog is the complete, immutable source of truth for preset metadata. SwiftData `Exercise` remains the compact, CloudKit-synced training index used by workouts, templates, searching, and filtering.

Each generated catalog row contains:

- VitalStride stable UUID
- upstream source ID and pinned-source marker
- English name and preserved/fallback Chinese display name
- upstream `category` and `body_part`
- exact upstream equipment value plus its supported `Equipment` mapping
- upstream `target`, `muscle_group`, and `secondary_muscles`
- derived `primaryMuscles = [target]`
- derived `secondaryMuscles = secondary_muscles`, with only exact duplicates of the primary removed
- full `instructions` and `instruction_steps` maps for `en`, `es`, `fr`, `hi`, `it`, `ko`, `pl`, `ru`, `tr`, and `zh`
- `media_id`, relative image/GIF paths, attribution, and upstream creation timestamp
- preserved VitalStride defaults and `mediaKey`
- provenance identifying whether the row is upstream-backed or VitalStride-only

The multilingual maps live only in the bundled catalog in this delivery. They are not copied into every CloudKit-synced `Exercise`, avoiding database bloat and duplicate cross-device synchronization.

## Matching and Reconciliation

Matching is deterministic and ordered:

1. Match current imported presets by their existing UUIDv5 derived from upstream ID.
2. Match the original hand-maintained presets by normalized English name.
3. When distinct upstream IDs share a normalized name, retain every record; at most one may inherit a matching VitalStride UUID and every additional source ID receives its deterministic UUIDv5.
4. Reject ambiguous VitalStride-side matches and identifier collisions instead of guessing.
5. Allocate a deterministic UUIDv5 for every remaining upstream ID.
6. Append unchanged VitalStride-only presets.

The importer emits a reconciliation report containing matched imported presets, matched original presets, new upstream presets, preserved VitalStride-only presets, ambiguous matches, and collisions. Generation fails unless ambiguous matches and collisions are both zero and all 1,324 upstream IDs appear exactly once.

With the pinned inputs currently inspected, the expected result is 1,558 catalog rows: 1,324 upstream-backed rows plus 234 VitalStride-only presets. This includes all eight pairs of same-normalized-name upstream records and the previously excluded `Tire Flip` match. The generator verifies the reconciliation from source IDs rather than silently forcing the number.

## Equipment Compatibility

`Equipment` retains all existing raw values so persisted exercises remain decodable. It gains representations and localized labels for every distinct upstream equipment value not already represented.

The catalog preserves the exact upstream equipment string separately from the app enum mapping. Semantically equivalent spellings such as upstream body-weight terminology may map to the existing `.bodyweight` case, while distinct equipment such as bands, stability balls, medicine balls, rollers, and specialized machines receives an explicit supported case. Unknown future values fail generation and require an intentional mapping change.

## Runtime Migration

The catalog version is advanced. On upgrade, `ExerciseSeeder` performs the following transaction-like sequence:

1. Decode and validate the complete catalog.
2. Fetch existing presets by stable UUID.
3. Insert missing upstream presets.
4. For upstream-backed presets, overwrite canonical fields used by the app: English name, coarse group, equipment, primary muscles, and secondary muscles.
5. Preserve UUID, Chinese name, default weights/repetitions, `mediaKey`, workout/template relationships, VitalStride-only presets, and custom exercises.
6. Save the model context.
7. Write the catalog version to `UserDefaults` only after the save succeeds.

If decoding, validation, or saving fails, the context is rolled back, the stored version is not advanced, and the next launch retries. Re-running the same catalog is idempotent.

## Import Reproducibility and Provenance

The import command accepts or fetches only the configured pinned upstream commit. It records and checks the source JSON SHA-256 before transformation. The repository stores the upstream commit, checksum, source URL, license/notice reference, and deterministic source-snapshot timestamp in a small provenance manifest.

Running the generator twice from the same inputs must produce byte-identical catalog and reconciliation output. Key ordering and row ordering are deterministic. The importer never reads the moving upstream `main` branch.

## Validation and Tests

### Generator validation

- pinned source checksum matches
- exactly 1,324 unique upstream IDs are represented
- all ten required instruction languages and step arrays exist per upstream-backed row
- every upstream equipment value has an intentional mapping
- every upstream-backed row has `primaryMuscles == [target]`
- secondary muscles preserve upstream order after removing exact primary duplication
- stable UUIDs and upstream IDs are unique
- ambiguous matches and collisions are zero
- VitalStride-only rows are byte-equivalent in all pre-existing fields
- a second generation is byte-identical

### VitalModels tests

- every supported equipment case round-trips through Codable
- every case has a localized name and SF Symbol
- legacy equipment raw values remain decodable
- every pinned upstream equipment value maps successfully

### App and migration tests

- bundled catalog decodes and has the computed expected count
- representative records, including Cable Pulldown, use `target` as primary and retain upstream secondary muscles
- a v4 database upgrades without changing stable identity or workout/template relationships
- an original hand-maintained matching preset is updated while retaining its Chinese name and defaults
- a newly supported upstream record is inserted
- custom and VitalStride-only exercises remain unchanged
- repeated seeding makes no further changes
- failed save does not advance the catalog version
- multilingual catalog fields survive decoding exactly
- no media asset files are introduced

### Required verification

- targeted generator tests
- `swift build && swift test` in `Packages/VitalModels`
- full app test suite using the project-prescribed `xcodebuild test` command
- repository i18n parity checks for new equipment labels

## Scope Boundaries

Included:

- importer and pinned provenance
- complete catalog regeneration
- all upstream equipment compatibility
- preset migration and regression tests
- ten-language instruction storage

Excluded:

- exercise-detail or instruction UI
- localized exercise names beyond the preserved VitalStride Chinese names
- downloading, bundling, or displaying upstream image/GIF files
- anatomical re-audit beyond faithfully applying upstream `target` and secondary fields
- deleting or filtering VitalStride-only exercises

## Delivery

The implementation is tracked by one Multica umbrella issue containing the full contract. Because it crosses the VitalModels package and app-target catalog/seeder code, execution is split into independently verifiable layer-scoped tasks and commits while remaining one product delivery. All changes reach `main` through a protected GitHub PR. Merge requires the repository's full CI and both required review-bot checks to pass.
