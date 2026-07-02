#!/usr/bin/env python3
"""One-shot script to backfill defaultWeight{Low,Mid,High} fields
into VitalStride/Resources/exercises.json.

Reads (muscleGroup, equipment) baseline table defined below, writes the
three defaultWeight fields onto every exercise. Deterministic and
idempotent — running twice produces the same output. Reps defaults
(5/10/15) stay on the Exercise model default and are NOT written into
JSON.

Rules:
- muscleGroup == core          → all three weights null
- equipment  == bodyweight     → all three weights null
- otherwise                    → lookup baseline table
- (mg, kettlebell)             → per-mg fallback if not in table
- WARN (do not silently drop)  → if a combination truly has no mapping,
                                 emit a stderr warning and record null.

Run from repo root:
    python3 scripts/backfill_exercise_defaults.py

Related issue: MY-1071
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = REPO_ROOT / "VitalStride" / "Resources" / "exercises.json"

# Baseline (kg). For single-side movements, values represent single-side load.
# core / bodyweight already forced to null before this table is consulted.
BASELINE: dict[tuple[str, str], tuple[float | None, float | None, float | None]] = {
    ("chest", "barbell"):     (80.0, 60.0, 40.0),
    ("chest", "dumbbell"):    (30.0, 22.5, 15.0),
    ("chest", "machine"):     (70.0, 50.0, 35.0),
    ("chest", "cable"):       (25.0, 18.0, 12.0),
    ("back", "barbell"):      (80.0, 60.0, 40.0),
    ("back", "dumbbell"):     (32.0, 24.0, 16.0),
    ("back", "machine"):      (70.0, 55.0, 40.0),
    ("back", "cable"):        (60.0, 45.0, 30.0),
    ("legs", "barbell"):      (120.0, 90.0, 60.0),
    ("legs", "dumbbell"):     (30.0, 22.5, 15.0),
    ("legs", "machine"):      (100.0, 75.0, 50.0),
    ("legs", "cable"):        (30.0, 22.0, 15.0),
    ("shoulders", "barbell"): (50.0, 40.0, 25.0),
    ("shoulders", "dumbbell"):(18.0, 14.0, 9.0),
    ("shoulders", "machine"): (50.0, 40.0, 30.0),
    ("shoulders", "cable"):   (15.0, 11.0, 7.0),
    ("arms", "barbell"):      (35.0, 25.0, 18.0),
    ("arms", "dumbbell"):     (16.0, 12.0, 8.0),
    ("arms", "machine"):      (30.0, 22.0, 15.0),
    ("arms", "cable"):        (25.0, 18.0, 12.0),
    ("fullBody", "barbell"):  (60.0, 45.0, 30.0),
    ("fullBody", "kettlebell"):(24.0, 16.0, 12.0),
}

# kettlebell fallback for any (mg, kettlebell) not covered explicitly
KETTLEBELL_FALLBACK: tuple[float, float, float] = (20.0, 14.0, 10.0)


def lookup(mg: str, eq: str) -> tuple[float | None, float | None, float | None, bool]:
    """Return (low, mid, high, warned). warned=True means we had to emit a warning."""
    if mg == "core":
        return (None, None, None, False)
    if eq == "bodyweight":
        return (None, None, None, False)
    key = (mg, eq)
    if key in BASELINE:
        return (*BASELINE[key], False)
    if eq == "kettlebell":
        return (*KETTLEBELL_FALLBACK, False)
    return (None, None, None, True)


def main() -> int:
    if not JSON_PATH.exists():
        print(f"error: exercises.json not found at {JSON_PATH}", file=sys.stderr)
        return 1

    with JSON_PATH.open("r", encoding="utf-8") as f:
        catalog = json.load(f)

    if "exercises" not in catalog:
        print("error: catalog missing 'exercises' key", file=sys.stderr)
        return 1

    warnings = 0
    updated = 0
    for ex in catalog["exercises"]:
        mg = ex.get("muscleGroup", "")
        eq = ex.get("equipment", "")
        low, mid, high, warned = lookup(mg, eq)
        if warned:
            warnings += 1
            print(
                f"warn: no baseline for muscleGroup={mg!r} equipment={eq!r} "
                f"exercise={ex.get('nameEn')!r}; wrote nulls",
                file=sys.stderr,
            )
        ex["defaultWeightLow"] = low
        ex["defaultWeightMid"] = mid
        ex["defaultWeightHigh"] = high
        updated += 1

    # bump catalog version to "2"
    catalog["version"] = "2"

    with JSON_PATH.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"updated {updated} exercises; {warnings} warning(s); version now {catalog['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
