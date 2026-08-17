# Exercise Catalog Full Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every overlapping preset with the complete pinned upstream record, add every missing upstream record, and migrate existing preset objects in place without changing VitalStride-only or custom exercises.

**Architecture:** A deterministic Python generator pins and verifies the upstream snapshot, reconciles source IDs to stable VitalStride UUIDs, and emits catalog v5 plus a reconciliation report. `Equipment` gains intentional cases for all 28 upstream values while retaining every legacy raw value. `ExerciseSeeder` validates catalog v5 and updates canonical fields on existing upstream-backed SwiftData objects without copying multilingual content into CloudKit.

**Tech Stack:** Python 3 standard library, JSON/SHA-256/UUIDv5, Swift 6.1, SwiftData, Swift Testing, XcodeGen project, GitHub Actions.

## Global Constraints

- Follow `.specify/memory/constitution.md`, top-level `CONTEXT.md`, and `Packages/VitalModels/CONTEXT.md`.
- Pin upstream commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd` and JSON SHA-256 `656634224b8977b99a6d765470ee123260d4979715eaa4e7c0b7c8bb0d79f93d`; never read moving `main`.
- Represent all 1,324 unique upstream IDs and preserve all eight pairs of same-normalized-name upstream rows.
- Produce exactly 1,558 catalog rows for the pinned inputs: 1,324 upstream-backed plus 234 VitalStride-only presets.
- Reconciliation totals must be 1,135 UUIDv5 matches, 66 original-preset name matches, 123 new upstream rows, 234 VitalStride-only rows, zero ambiguity, and zero identifier collisions.
- Use upstream `target` as the only primary-muscle source and ordered `secondary_muscles` as secondary muscles after removing exact primary duplicates. Preserve upstream `muscle_group` inside the source mirror only.
- Preserve matched preset UUID, `nameZh`, all default weight/repetition fields, `mediaKey`, SwiftData identity, workout relationships, and template relationships.
- Do not modify custom exercises or VitalStride-only presets during catalog v5 canonical migration.
- Store complete `en`, `es`, `fr`, `hi`, `it`, `ko`, `pl`, `ru`, `tr`, and `zh` instructions and step arrays in the bundled catalog only.
- Store media paths, media ID, creation time, and attribution as metadata; do not download, bundle, or display images or GIFs.
- Do not add instruction UI or alter the workout flow.
- Keep all existing `Equipment` raw values decodable. New raw values must remain canonical ASCII identifiers for telemetry.
- Do not modify `Exercise.swift`, `project.yml`, or the generated `.xcodeproj`.
- Per ADR-0017 / Constitution DoR, this plan specifies contracts and verified signatures but deliberately contains no inline compilable Swift implementation.

---

## File Structure

### Modified

- `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift` — enum cases, localized labels, and symbols for legacy plus pinned-upstream equipment.
- `Packages/VitalModels/Sources/VitalModels/Resources/Localizable.xcstrings` — English and Simplified Chinese equipment labels.
- `Packages/VitalModels/Tests/VitalModelsTests/EnumLocalizationTests.swift` — localization, symbol, Codable, and legacy raw-value contracts.
- `VitalStrideTests/Sources/EnumTests.swift` — app integration expectation for the expanded case set.
- `scripts/import_mit_exercises.py` — pinned-source verification and full ordered reconciliation generator.
- `VitalStride/Resources/exercises.json` — generated catalog v5 containing 1,558 rows and complete source mirrors.
- `VitalStride/Sources/ExerciseSeeder.swift` — v5 validation, in-place canonical updates, atomic save boundary, and rollback.
- `VitalStrideTests/Sources/ExercisesJSONTests.swift` — full bundled-catalog source-schema validation.
- `VitalStrideTests/Sources/ExerciseSeederTests.swift` — v4-to-v5 preservation, update, recovery, relationship, and idempotence tests.
- `VitalStrideTests/Sources/ExercisePickerIndexSyncTests.swift` — remove the obsolete six-equipment assumption while retaining telemetry validation across all cases.
- `.github/workflows/ci.yml` — run deterministic generator contract tests and muscle validation in the required policy job.

### Created

- `scripts/exercises_dataset_provenance.json` — pinned commit, raw URL, checksum, source-snapshot timestamp, and license/notice references.
- `scripts/tests/test_import_mit_exercises.py` — standard-library unit and reconciliation tests.
- `docs/data/exercise-catalog-reconciliation.json` — deterministic counts, match classes, duplicate-name groups, and zero-error results.
- `docs/licenses/hasaneyldrm-exercises-dataset-LICENSE` — upstream dataset license notice retained with the data.
- `docs/licenses/hasaneyldrm-exercises-dataset-NOTICE.md` — upstream attribution and media-rights boundary retained with the data.

### Explicitly Unchanged

- `Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift`
- `project.yml`
- `VitalStride.xcodeproj/**`
- user-owned untracked `Prototype/Sources/Prototype/**` files

---

### Task 1: Expand the Equipment taxonomy in VitalModels

**Layer:** VitalModels

**Files:**

- Modify: `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift`
- Modify: `Packages/VitalModels/Sources/VitalModels/Resources/Localizable.xcstrings`
- Modify: `Packages/VitalModels/Tests/VitalModelsTests/EnumLocalizationTests.swift`
- Modify: `VitalStrideTests/Sources/EnumTests.swift`
- Modify: `VitalStrideTests/Sources/ExercisePickerIndexSyncTests.swift`

**Interfaces:**

- Preserve `public enum Equipment: String, Codable, CaseIterable, Sendable`.
- Preserve legacy cases/raw values: `barbell`, `dumbbell`, `machine`, `bodyweight`, `cable`, `kettlebell`.
- Add explicit cases with snake-case raw values for `assisted`, `band`, `bosu ball`, `elliptical machine`, `ez barbell`, `hammer`, `leverage machine`, `medicine ball`, `olympic barbell`, `resistance band`, `roller`, `rope`, `skierg machine`, `sled machine`, `smith machine`, `stability ball`, `stationary bike`, `stepmill machine`, `tire`, `trap bar`, `upper body ergometer`, `weighted`, and `wheel roller`.
- `Equipment.allCases` must contain 29 cases: 28 source distinctions plus legacy `.machine`; upstream `body weight` maps to existing `.bodyweight`.
- Every case must return a nonempty `localizedName` and `sfSymbol`; every new localization key must have English and Simplified Chinese values.

- [ ] **Step 1: Add failing taxonomy tests**

  Extend package tests to assert all 29 raw values, round-trip every case with `JSONEncoder`/`JSONDecoder`, explicitly decode the six legacy raw strings, and verify nonempty localized names/symbols. Update app tests to require 29 cases and to run telemetry identifier construction for every case.

- [ ] **Step 2: Run the focused tests and confirm RED**

  Run from the repository root:

  `swift test --package-path Packages/VitalModels`

  Expected result: failure because the 23 new cases/localization keys do not exist.

- [ ] **Step 3: Implement the minimal enum and localization expansion**

  Add only the cases and exhaustive switch branches required by the pinned 28-value equipment vocabulary. Use canonical snake-case raw strings and reuse appropriate existing SF Symbols; do not add UI layout changes.

- [ ] **Step 4: Run package tests and app compile-sensitive enum tests**

  Run:

  `swift build --package-path Packages/VitalModels && swift test --package-path Packages/VitalModels`

  Then run:

  `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation -only-testing:VitalStrideTests/EnumTests -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests`

  Expected result: both commands pass; no exhaustive-switch compiler failures remain.

- [ ] **Step 5: Commit the independently verified layer change**

  Stage only the five Task 1 files and commit with the Multica issue key in the message.

---

### Task 2: Replace the importer with a pinned full-catalog generator

**Layer:** app target resources / tooling

**Files:**

- Modify: `scripts/import_mit_exercises.py`
- Create: `scripts/exercises_dataset_provenance.json`
- Create: `scripts/tests/test_import_mit_exercises.py`
- Create: `docs/data/exercise-catalog-reconciliation.json`
- Create: `docs/licenses/hasaneyldrm-exercises-dataset-LICENSE`
- Create: `docs/licenses/hasaneyldrm-exercises-dataset-NOTICE.md`
- Modify: `VitalStride/Resources/exercises.json`
- Modify: `VitalStrideTests/Sources/ExercisesJSONTests.swift`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Keep CLI entry point `python3 scripts/import_mit_exercises.py` and `--source PATH`; make the default URL point to the pinned raw commit.
- Keep `normalize_name`, `titleize`, `new_preset_id`, `body_part_to_muscle_group`, and the UUID namespace unchanged so existing imported identities remain stable.
- Replace append/deduplicate behavior with a pure reconciliation boundary accepting the current catalog plus verified upstream rows and returning a generated catalog plus deterministic report.
- Catalog envelope version is exactly `"5"`.
- Every row keeps existing app fields and adds `source`.
- Every upstream-backed row has `source = "hasaneyldrm/exercises-dataset"` and a `sourceData` object that mirrors all upstream fields without dropping or renaming information: `id`, `name`, `category`, `body_part`, `equipment`, `target`, `muscle_group`, `secondary_muscles`, `instructions`, `instruction_steps`, `media_id`, `image`, `gif_url`, `attribution`, and `created_at`.
- Every VitalStride-only row has `source = "vitalstride"` and no fabricated `sourceData`.
- The report records the exact reconciliation totals in Global Constraints plus all eight duplicate-name groups.

- [ ] **Step 1: Add failing Python generator tests**

  Cover checksum rejection, target/secondary mapping, all 28 equipment mappings, duplicate upstream names retained by source ID, deterministic UUID allocation, VitalStride-only byte preservation, ambiguity/collision rejection, ten-language preservation, and byte-identical second generation using compact in-test fixtures. Separately validate the checked-in v5 catalog and reconciliation report, whose 1,324 `sourceData` objects form the pinned source mirror without vendoring a second raw-data copy.

- [ ] **Step 2: Run generator tests and confirm RED**

  Run:

  `python3 -m unittest discover -s scripts/tests -p 'test_import_mit_exercises.py'`

  Expected result: failure because pinned provenance and full reconciliation interfaces are absent.

- [ ] **Step 3: Implement pinned provenance and ordered reconciliation**

  Verify source bytes before JSON decoding. Match 1,135 existing UUIDv5 rows first, match 66 original presets by normalized name second, allocate stable UUIDv5 IDs for 123 remaining source rows, and append the 234 untouched VitalStride-only rows. Never deduplicate distinct upstream IDs by name. Preserve matched `nameZh`, weights, `mediaKey`, and stable UUID while replacing app canonical fields from source.

- [ ] **Step 4: Generate catalog v5 and deterministic artifacts**

  Run the generator with the pinned source file, write `exercises.json` and the reconciliation report, then run it a second time against identical inputs.

  Expected result: catalog and report are byte-identical after the second run; report totals are 1,558/1,324/234 with zero ambiguity and collision.

- [ ] **Step 5: Add failing bundled-catalog tests**

  Expand `PresetExercise` test decoding to validate `source` and the complete optional `sourceData` mirror. Assert catalog version 5, total 1,558, exactly 1,324 unique upstream source IDs, exactly 234 VitalStride-only rows, ten languages per upstream row, all 28 exact source equipment strings, source/app muscle mapping, and the Cable Pulldown regression (`target=lats`, secondary `biceps, forearms`). The Python repository test, rather than the bundle decoder, asserts that no `.jpg` or `.gif` assets are introduced.

- [ ] **Step 6: Run focused generator and catalog tests**

  Run:

  `python3 -m unittest discover -s scripts/tests -p 'test_import_mit_exercises.py'`

  `python3 scripts/validate_exercise_muscles.py`

  `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation -only-testing:VitalStrideTests/ExercisesJSONTests`

  Expected result: all commands pass.

- [ ] **Step 7: Add CI enforcement**

  Add generator unit tests and `validate_exercise_muscles.py` to the required `Lint & policy` job after checkout and before review-contract tests. The CI commands must be identical to the local commands above and require no network access.

- [ ] **Step 8: Commit the generated data/tooling unit**

  Stage only Task 2 files and commit with the Multica issue key. Confirm the commit contains metadata paths only and no upstream image/GIF binaries.

---

### Task 3: Migrate upstream-backed presets in place

**Layer:** app target

**Files:**

- Modify: `VitalStride/Sources/ExerciseSeeder.swift`
- Modify: `VitalStrideTests/Sources/ExerciseSeederTests.swift`

**Interfaces:**

- Preserve `seedIfNeeded(context:userDefaults:bundle:)`, `findByPresetId(_:context:)`, and `backfillDefaults(context:dtos:)` for existing callers/tests.
- Extend `ExerciseCatalog`/`ExerciseDTO` with optional provenance/source DTOs so v1-v4 fixtures continue decoding; catalog v5 validation requires every row to have a recognized source and every upstream row to contain the complete source mirror and ten languages.
- Extend internal `seed(context:userDefaults:catalogData:)` with an injectable throwing save boundary that defaults to `ModelContext.save()`. Tests use it to force save failure without changing production callers.
- Add a pre-mutation catalog validator for unique stable IDs, unique upstream source IDs, recognized provenance, complete upstream fields/languages, and primary/secondary contracts.
- Add an in-place canonical update phase for rows with `source = "hasaneyldrm/exercises-dataset"`; update only `nameEn`, `muscleGroup`, `equipment`, `primaryMuscles`, and `secondaryMuscles`.
- For catalog v5, do not run the legacy nil-only name/default/media backfill. Preserve `nameZh`, all weights/repetitions, and `mediaKey` exactly, including `nil`.
- Remove the intermediate save from `migrateExistingPresets`; perform one final save. On any thrown error call `ModelContext.rollback()`, leave `seedVersionKey` unchanged, and rethrow.
- Same-version recovery compares the complete catalog ID set/count instead of returning when any preset exists.

- [ ] **Step 1: Replace the old overwrite assumption with failing v5 migration tests**

  Add a v4-to-v5 fixture whose upstream-backed preset changes English name, group, equipment, primary, and secondary fields. Assert those canonical fields change while Chinese name, nil/non-nil defaults, repetitions, `mediaKey`, persistent object identity, workout relationship, and template relationship remain unchanged. Assert VitalStride-only and custom rows remain byte-equivalent.

- [ ] **Step 2: Add failing recovery and validation tests**

  Add tests for duplicate catalog IDs, duplicate upstream IDs, incomplete language maps, unknown source, missing preset recovery under the same version, repeated v5 seeding, and an injected save failure. The save-failure test must assert rollback and that `seedVersionKey` remains at v4.

- [ ] **Step 3: Run focused seeder tests and confirm RED**

  Run:

  `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation -only-testing:VitalStrideTests/ExerciseSeederTests`

  Expected result: the existing seeder fails canonical-update, strict-preservation, validation, completeness, and rollback assertions.

- [ ] **Step 4: Implement validation and atomic in-place migration**

  Decode and validate before fetching/mutating. Update existing upstream-backed objects by stable preset ID; insert only missing IDs; skip canonical writes for `source=vitalstride` and all custom rows. Use one save boundary, update `UserDefaults` after successful save, and roll back every mutation on error.

- [ ] **Step 5: Run focused and bundled migration tests**

  Run:

  `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation -only-testing:VitalStrideTests/ExerciseSeederTests -only-testing:VitalStrideTests/ExerciseSeederFindTests -only-testing:VitalStrideTests/SubstituteRecommendationFilterTests`

  Expected result: all tests pass, including pre-v5 backward-compatibility fixtures.

- [ ] **Step 6: Commit the app migration unit**

  Stage only `ExerciseSeeder.swift` and `ExerciseSeederTests.swift` and commit with the Multica issue key.

---

### Task 4: Verify the complete delivery and prepare the PR

**Layer:** integration / delivery

**Files:** No new production files; only fix failures inside the task/layer that introduced them.

- [ ] **Step 1: Run deterministic data gates**

  Run:

  `python3 -m unittest discover -s scripts/tests -p 'test_import_mit_exercises.py'`

  `python3 scripts/validate_exercise_muscles.py`

  `python3 scripts/i18n_check_lproj_parity.py`

  Expected result: all commands exit zero.

- [ ] **Step 2: Run VitalModels gates**

  Run:

  `swift build --package-path Packages/VitalModels && swift test --package-path Packages/VitalModels`

  Expected result: build and tests pass.

- [ ] **Step 3: Run the full app gate**

  Run:

  `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation`

  Expected result: the VitalStride scheme builds and the complete test suite passes.

- [ ] **Step 4: Audit scope and generated assets**

  Verify `git diff --check`, confirm the final catalog/report counts, confirm no image/GIF binaries entered the diff, confirm the user-owned untracked Prototype files are untouched, and confirm no file outside the declared scope changed.

- [ ] **Step 5: Request code review and open the protected PR**

  Push the `agent/<issue-key>-<task-id>` branch to `github`, open one PR referencing the Multica issue, and enable auto-merge only after required checks are registered.

- [ ] **Step 6: Supervise CI, both review bots, merge, and issue closure**

  Monitor `Lint & policy`, six SPM jobs, `App target`, `claude-review`, and `codex-review`. Fix failures only in their owning layer, re-run affected gates, and confirm the PR is `MERGED` before marking the Multica issue done.
