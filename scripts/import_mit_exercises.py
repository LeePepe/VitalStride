#!/usr/bin/env python3
"""Import hasaneyldrm/exercises-dataset (MIT) into VitalStride exercises.json.

Downloads the structured JSON (no images/GIFs), maps MIT enums to the project
schema (MuscleGroup / Equipment), deduplicates against the existing catalog by
normalized nameEn, assigns deterministic UUID presetIds to net-new entries, and
merges the result into VitalStride/Resources/exercises.json (version envelope "4").

Design mirrors scripts/backfill_exercise_defaults.py: deterministic, idempotent,
stderr-logged, root-relative paths.

Rules (T001 acceptance):
- Preserve all existing 300 entries verbatim (id/nameZh/defaultWeight* unchanged).
- Map MIT body_part -> MuscleGroup; equipment -> Equipment.
- Rows whose enums cannot be mapped are logged and dropped (no invalid enum
  values reach the JSON).
- New presetIds are UUIDv5 over a fixed namespace + MIT id, so rerunning yields
  the same UUIDs; the script asserts none collide with the existing 300.
- Deduplicate by normalized nameEn across (existing catalog ∪ MIT rows).
- Version envelope stays "4".

Muscle-mapping precedence (MY-1326 fix):
- primaryMuscles[0] uses MIT `target` (true prime mover — e.g. lats for pulldowns,
  pectorals for bench press) rather than `muscle_group`. The MIT `muscle_group`
  field encodes the grip / dominant synergist for many pull-type movements
  (biceps/forearms) and mis-labeling from that field caused the systemic bug
  described in MY-1325.
- secondaryMuscles is filtered to exclude any muscle already present in
  primaryMuscles (case-sensitive exact string match), preserving order and
  deduplicating internal repeats.

Related: MY-1235 / specs/014-exercise-library-expansion/tasks.md T001; MY-1325 / MY-1326.

Usage:
    python3 scripts/import_mit_exercises.py               # download + write
    python3 scripts/import_mit_exercises.py --dry-run     # log only, no write
    python3 scripts/import_mit_exercises.py --source PATH # use local JSON copy
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import uuid
from collections import Counter
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = REPO_ROOT / "VitalStride" / "Resources" / "exercises.json"
MIT_URL = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json"

# Deterministic UUIDv5 namespace so reruns produce the same presetId per MIT id.
MIT_NAMESPACE = uuid.UUID("5e2a1f2c-8b3d-4d67-9a2c-1e8f4b5c9a11")

TARGET_VERSION = "4"
NEW_NET_MIN = 600

# MIT equipment string -> project Equipment enum.
# Values not in this table are excluded (logged) rather than force-mapped.
EQUIPMENT_MAP: dict[str, str] = {
    "barbell": "barbell",
    "ez barbell": "barbell",
    "olympic barbell": "barbell",
    "trap bar": "barbell",
    "smith machine": "machine",
    "dumbbell": "dumbbell",
    "kettlebell": "kettlebell",
    "cable": "cable",
    "rope": "cable",
    "body weight": "bodyweight",
    "weighted": "bodyweight",
    "leverage machine": "machine",
    "sled machine": "machine",
    "stationary bike": "machine",
    "elliptical machine": "machine",
    "stepmill machine": "machine",
    "skierg machine": "machine",
    "upper body ergometer": "machine",
    "assisted": "machine",
}

# MIT body_part -> project MuscleGroup. `cardio` is disambiguated via target
# (see body_part_to_muscle_group below).
BODY_PART_MAP: dict[str, str | None] = {
    "back": "back",
    "chest": "chest",
    "shoulders": "shoulders",
    "upper arms": "arms",
    "lower arms": "arms",
    "upper legs": "legs",
    "lower legs": "legs",
    "waist": "core",
    "neck": None,
    "cardio": None,
}

# Fallback: MIT target (primary target muscle) -> project MuscleGroup, used
# when body_part is `cardio` or otherwise unmapped.
TARGET_TO_MUSCLE_GROUP: dict[str, str] = {
    "abs": "core",
    "obliques": "core",
    "spine": "core",
    "serratus anterior": "core",
    "pectorals": "chest",
    "delts": "shoulders",
    "traps": "back",
    "levator scapulae": "shoulders",
    "lats": "back",
    "upper back": "back",
    "biceps": "arms",
    "triceps": "arms",
    "forearms": "arms",
    "quads": "legs",
    "hamstrings": "legs",
    "glutes": "legs",
    "calves": "legs",
    "abductors": "legs",
    "adductors": "legs",
    "cardiovascular system": "fullBody",
}

# Baseline defaults (kg) reused from scripts/backfill_exercise_defaults.py so new
# entries get the same 3-tier weight suggestion existing entries already carry.
BASELINE: dict[tuple[str, str], tuple[float | None, float | None, float | None]] = {
    ("chest", "barbell"): (80.0, 60.0, 40.0),
    ("chest", "dumbbell"): (30.0, 22.5, 15.0),
    ("chest", "machine"): (70.0, 50.0, 35.0),
    ("chest", "cable"): (25.0, 18.0, 12.0),
    ("back", "barbell"): (80.0, 60.0, 40.0),
    ("back", "dumbbell"): (32.0, 24.0, 16.0),
    ("back", "machine"): (70.0, 55.0, 40.0),
    ("back", "cable"): (60.0, 45.0, 30.0),
    ("legs", "barbell"): (120.0, 90.0, 60.0),
    ("legs", "dumbbell"): (30.0, 22.5, 15.0),
    ("legs", "machine"): (100.0, 75.0, 50.0),
    ("legs", "cable"): (30.0, 22.0, 15.0),
    ("shoulders", "barbell"): (50.0, 40.0, 25.0),
    ("shoulders", "dumbbell"): (18.0, 14.0, 9.0),
    ("shoulders", "machine"): (50.0, 40.0, 30.0),
    ("shoulders", "cable"): (15.0, 11.0, 7.0),
    ("arms", "barbell"): (35.0, 25.0, 18.0),
    ("arms", "dumbbell"): (16.0, 12.0, 8.0),
    ("arms", "machine"): (30.0, 22.0, 15.0),
    ("arms", "cable"): (25.0, 18.0, 12.0),
    ("fullBody", "barbell"): (60.0, 45.0, 30.0),
    ("fullBody", "kettlebell"): (24.0, 16.0, 12.0),
}

KETTLEBELL_FALLBACK: tuple[float, float, float] = (20.0, 14.0, 10.0)


def default_weights(mg: str, eq: str) -> tuple[float | None, float | None, float | None]:
    if mg == "core" or eq == "bodyweight":
        return (None, None, None)
    if (mg, eq) in BASELINE:
        return BASELINE[(mg, eq)]
    if eq == "kettlebell":
        return KETTLEBELL_FALLBACK
    return (None, None, None)


def normalize_name(name: str) -> str:
    """Lowercase, strip punctuation and collapse whitespace for dedup keys."""
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def titleize(name: str) -> str:
    """Title-case a MIT lowercased exercise name for display parity with existing entries."""
    words = name.split()
    out: list[str] = []
    for w in words:
        if "/" in w:
            out.append("/".join(part.capitalize() if part else part for part in w.split("/")))
        elif "-" in w:
            out.append("-".join(part.capitalize() if part else part for part in w.split("-")))
        else:
            out.append(w.capitalize())
    return " ".join(out)


def body_part_to_muscle_group(body_part: str, target: str) -> str | None:
    mapped = BODY_PART_MAP.get(body_part)
    if mapped is not None:
        return mapped
    # body_part in {cardio, neck} or unknown: try target fallback.
    return TARGET_TO_MUSCLE_GROUP.get(target)


def map_equipment(equipment: str) -> str | None:
    return EQUIPMENT_MAP.get(equipment)


def new_preset_id(mit_id: str) -> str:
    return str(uuid.uuid5(MIT_NAMESPACE, mit_id))


def load_existing_catalog() -> dict[str, Any]:
    with JSON_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def fetch_mit_dataset(source: str | None) -> list[dict[str, Any]]:
    if source:
        p = Path(source)
        print(f"info: loading MIT dataset from local file {p}", file=sys.stderr)
        return json.loads(p.read_text(encoding="utf-8"))
    print(f"info: downloading MIT dataset from {MIT_URL}", file=sys.stderr)
    req = urllib.request.Request(MIT_URL, headers={"User-Agent": "VitalStride-import/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def compute_muscles(
    row: dict[str, Any],
) -> tuple[list[str], list[str]] | None:
    """Derive (primaryMuscles, secondaryMuscles) from an MIT row.

    Returns None if the row cannot be mapped (empty target and empty
    muscle_group AND unmappable body_part). Applies the MY-1326 precedence:
    primary = target > muscle_group > body-part-derived project MuscleGroup,
    with secondary filtered to exclude any muscle in primary.
    """
    body_part: str = row.get("body_part", "")
    target: str = row.get("target", "")
    muscle_group_raw: str = row.get("muscle_group", "")
    secondary_muscles_raw = row.get("secondary_muscles", []) or []

    muscle_group = body_part_to_muscle_group(body_part, target)
    if muscle_group is None:
        return None

    primary_muscles = (
        [target] if target
        else [muscle_group_raw] if muscle_group_raw
        else [muscle_group]
    )
    primary_set = set(primary_muscles)
    secondary_muscles: list[str] = []
    seen_secondary: set[str] = set()
    for m in secondary_muscles_raw:
        if not isinstance(m, str) or not m:
            continue
        if m in primary_set or m in seen_secondary:
            continue
        secondary_muscles.append(m)
        seen_secondary.add(m)
    return primary_muscles, secondary_muscles


def refresh_mit_muscles(
    existing: list[dict[str, Any]],
    mit_rows: list[dict[str, Any]],
) -> dict[str, int]:
    """Refresh primary/secondary muscle fields for previously-imported MIT rows
    (MY-1326).

    Matches entries by deterministic UUIDv5 id → MIT row, then rewrites
    primaryMuscles and secondaryMuscles in place. Preserves id, nameEn, nameZh,
    muscleGroup, equipment, defaultWeight* (per parent-issue red-lines: the
    hand-refined ~60 presets have UUIDv4 ids and are never touched here).

    Returns a counter dict with keys: refreshed, unchanged, no_mit_row.
    """
    counters: Counter[str] = Counter()
    mit_by_uuid: dict[str, dict[str, Any]] = {
        new_preset_id(str(row["id"])): row for row in mit_rows if row.get("id") is not None
    }
    for entry in existing:
        row = mit_by_uuid.get(entry.get("id", ""))
        if row is None:
            # UUIDv4 hand-refined preset OR unrecognized id — leave untouched.
            counters["no_mit_row"] += 1
            continue
        derived = compute_muscles(row)
        if derived is None:
            # MIT row exists but cannot be muscle-mapped: leave entry alone.
            counters["no_mit_row"] += 1
            continue
        new_primary, new_secondary = derived
        old_primary = entry.get("primaryMuscles", []) or []
        old_secondary = entry.get("secondaryMuscles", []) or []
        if new_primary == old_primary and new_secondary == old_secondary:
            counters["unchanged"] += 1
            continue
        entry["primaryMuscles"] = new_primary
        entry["secondaryMuscles"] = new_secondary
        counters["refreshed"] += 1
    return dict(counters)


def build_new_entries(
    mit_rows: list[dict[str, Any]],
    existing_norm_names: set[str],
    existing_ids: set[str],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """Map MIT rows -> project entries; dedup and log exclusions.

    Returns (new_entries, counters). counters keys:
        excl_equipment, excl_muscle_group, excl_dup_existing, excl_dup_internal, added
    """
    counters: Counter[str] = Counter()
    excl_equipment_by_kind: Counter[str] = Counter()
    excl_bp_by_kind: Counter[str] = Counter()
    added: list[dict[str, Any]] = []
    seen_this_run: set[str] = set()

    for row in mit_rows:
        mit_id: str = row["id"]
        name_raw: str = row["name"]
        body_part: str = row.get("body_part", "")
        equipment_raw: str = row.get("equipment", "")
        target: str = row.get("target", "")

        muscle_group = body_part_to_muscle_group(body_part, target)
        if muscle_group is None:
            counters["excl_muscle_group"] += 1
            excl_bp_by_kind[body_part or "(empty)"] += 1
            continue

        equipment = map_equipment(equipment_raw)
        if equipment is None:
            counters["excl_equipment"] += 1
            excl_equipment_by_kind[equipment_raw or "(empty)"] += 1
            continue

        name_en = titleize(name_raw)
        norm = normalize_name(name_en)
        if norm in existing_norm_names:
            counters["excl_dup_existing"] += 1
            continue
        if norm in seen_this_run:
            counters["excl_dup_internal"] += 1
            continue
        seen_this_run.add(norm)

        derived = compute_muscles(row)
        # compute_muscles only returns None when muscle_group is unmappable,
        # which we've already handled above; fall back defensively.
        primary_muscles, secondary_muscles = (
            derived if derived is not None else ([muscle_group], [])
        )

        preset_id = new_preset_id(mit_id)
        if preset_id in existing_ids:
            # UUIDv5 collision with an existing UUIDv4 is astronomically unlikely,
            # but guard against it explicitly rather than silently overwrite.
            print(f"error: presetId collision for MIT id={mit_id} name={name_en}", file=sys.stderr)
            counters["excl_id_collision"] += 1
            continue

        low, mid, high = default_weights(muscle_group, equipment)
        entry: dict[str, Any] = {
            "id": preset_id,
            "nameEn": name_en,
            "nameZh": name_en,  # No zh name in MIT dataset; fallback to English until precision translation is added.
            "muscleGroup": muscle_group,
            "equipment": equipment,
            "primaryMuscles": primary_muscles,
            "secondaryMuscles": secondary_muscles,
            "defaultWeightLow": low,
            "defaultWeightMid": mid,
            "defaultWeightHigh": high,
        }
        added.append(entry)
        counters["added"] += 1

    # Log summary of exclusion buckets.
    if excl_equipment_by_kind:
        print("info: equipment exclusions (kind -> count):", file=sys.stderr)
        for k, v in sorted(excl_equipment_by_kind.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {v:4d}  {k}", file=sys.stderr)
    if excl_bp_by_kind:
        print("info: body_part exclusions (kind -> count):", file=sys.stderr)
        for k, v in sorted(excl_bp_by_kind.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {v:4d}  {k}", file=sys.stderr)

    return added, dict(counters)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="log only, do not write JSON")
    parser.add_argument("--source", help="path to a local MIT exercises.json (skip download)")
    args = parser.parse_args()

    if not JSON_PATH.exists():
        print(f"error: exercises.json not found at {JSON_PATH}", file=sys.stderr)
        return 1

    catalog = load_existing_catalog()
    existing: list[dict[str, Any]] = catalog.get("exercises", [])
    existing_ids: set[str] = {e["id"] for e in existing}
    existing_norm_names: set[str] = {normalize_name(e["nameEn"]) for e in existing}
    print(f"info: existing catalog version={catalog.get('version')} count={len(existing)}", file=sys.stderr)

    mit_rows = fetch_mit_dataset(args.source)
    print(f"info: MIT dataset rows={len(mit_rows)}", file=sys.stderr)

    # MY-1326: refresh muscle fields on already-imported MIT rows before we
    # look for net-new additions. Matches by deterministic UUIDv5 id so the
    # ~60 hand-refined presets (UUIDv4) are never touched.
    refresh_counters = refresh_mit_muscles(existing, mit_rows)
    print(
        "info: MIT muscle refresh "
        f"refreshed={refresh_counters.get('refreshed', 0)} "
        f"unchanged={refresh_counters.get('unchanged', 0)} "
        f"no_mit_row={refresh_counters.get('no_mit_row', 0)}",
        file=sys.stderr,
    )

    added, counters = build_new_entries(mit_rows, existing_norm_names, existing_ids)
    total_after = len(existing) + len(added)
    print(
        "info: mapping summary "
        f"added={counters.get('added', 0)} "
        f"excl_equipment={counters.get('excl_equipment', 0)} "
        f"excl_muscle_group={counters.get('excl_muscle_group', 0)} "
        f"excl_dup_existing={counters.get('excl_dup_existing', 0)} "
        f"excl_dup_internal={counters.get('excl_dup_internal', 0)} "
        f"excl_id_collision={counters.get('excl_id_collision', 0)}",
        file=sys.stderr,
    )
    print(f"info: total after merge = {len(existing)} + {len(added)} = {total_after}", file=sys.stderr)

    # Idempotent rerun: if the on-disk catalog is already at TARGET_VERSION,
    # the MIT rerun yields zero net-new rows, AND the muscle refresh yielded
    # zero refreshed rows, treat as a verified no-op. Any refresh delta must
    # trigger a write so the JSON reflects the current mapping logic.
    already_imported = (
        catalog.get("version") == TARGET_VERSION
        and len(added) == 0
        and refresh_counters.get("refreshed", 0) == 0
    )
    if already_imported:
        print(
            f"info: catalog already at version={TARGET_VERSION} and MIT rerun yields "
            "no net-new rows or muscle refreshes; nothing to do (idempotent rerun)",
            file=sys.stderr,
        )
        return 0

    # Initial-import ≥600 guard only applies when the catalog has not yet been
    # bumped to TARGET_VERSION. After the first successful import, subsequent
    # runs (including muscle-refresh reruns like MY-1326) must be allowed to
    # write the delta without re-adding 600+ rows.
    if catalog.get("version") != TARGET_VERSION and len(added) < NEW_NET_MIN:
        print(
            f"error: net-new count {len(added)} < required minimum {NEW_NET_MIN}",
            file=sys.stderr,
        )
        return 2

    merged = {"version": TARGET_VERSION, "exercises": existing + added}

    # Guard: assert all ids remain unique in the merged catalog.
    all_ids = [e["id"] for e in merged["exercises"]]
    if len(all_ids) != len(set(all_ids)):
        print("error: duplicate ids after merge", file=sys.stderr)
        return 3

    if args.dry_run:
        print("info: --dry-run; not writing exercises.json", file=sys.stderr)
        return 0

    with JSON_PATH.open("w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"info: wrote {JSON_PATH} version={TARGET_VERSION} count={total_after}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
