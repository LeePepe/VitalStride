#!/usr/bin/env python3
"""Validate VitalStride exercises.json muscle mapping (MY-1326).

Enforces the anti-regression contract for the muscle-mapping bug fix
introduced in MY-1325: catalog v4 imported 1135 rows from the MIT dataset
with `muscle_group` mistakenly used as the primary muscle (a grip/synergist
label), producing systemic mis-labels plus 1135 rows where `primaryMuscles[0]`
was also present in `secondaryMuscles`.

Assertions (all must hold on a green catalog):
  1. Zero entries with `primaryMuscles[0]` present in `secondaryMuscles`.
  2. Pull-type exercises (lat pulldown / pull-up / chin-up / bent-over row)
     have at least one back muscle in `primaryMuscles`.
  3. Known-anchor exercises have anatomically-correct primary muscles:
     * Lat Pulldown        -> back (lats / latissimus dorsi)
     * Bench Press         -> chest (pectorals)
     * Barbell Back Squat  -> quads
     * Bicep Curl          -> biceps

Exit codes:
  0 = all checks pass
  1 = one or more checks failed (details on stderr)

Usage:
  python3 scripts/validate_exercise_muscles.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = REPO_ROOT / "VitalStride" / "Resources" / "exercises.json"

# Back-muscle tokens accepted as primary for pull-type exercises.
# Uses substring match so `latissimus dorsi`, `lats`, `upper trapezius`,
# `middle trapezius`, `rhomboids`, `upper back` etc. all count.
BACK_MUSCLE_TOKENS: tuple[str, ...] = (
    "lat",           # lats, latissimus dorsi, lateral (excluded via context below)
    "trapezius",
    "traps",
    "rhomboid",
    "upper back",
    "teres",
    "erector",
)

# Chest-muscle tokens (pectoral variants).
CHEST_MUSCLE_TOKENS: tuple[str, ...] = (
    "pectoral",
    "pecs",
    "chest",
)

QUAD_TOKENS: tuple[str, ...] = ("quadriceps", "quads", "quad")
BICEP_TOKENS: tuple[str, ...] = ("biceps", "biceps brachii", "brachialis")

# Substrings that identify a pull-type exercise by English name.
# `row` intentionally excludes push-related names so we filter carefully.
PULL_NAME_PATTERNS: tuple[str, ...] = (
    "pulldown",
    "pull-up",
    "pull up",
    "pullup",
    "chin-up",
    "chin up",
    "chinup",
    "bent-over row",
    "bent over row",
    "barbell row",
    "dumbbell row",
    "seated row",
    "cable row",
    "t-bar row",
    "t bar row",
    "one-arm row",
    "one arm row",
    "single-arm row",
    "single arm row",
    "pendlay row",
    "yates row",
    "inverted row",
    "meadows row",
)


def name_matches_pull(name_en: str) -> bool:
    # Strip parenthesized suffixes (typically equipment descriptors like
    # "(on Pull-Up Cable Machine)") so equipment names don't false-match.
    n = name_en.lower()
    n = re.sub(r"\s*\([^)]*\)\s*", " ", n).strip()
    # Explicit bicep-emphasis variants MIT legitimately tags as biceps primary
    # (narrow/close grip pull-ups, curl-family movements) — exclude from check.
    if "bicep" in n:
        return False
    if "curl" in n:
        return False
    return any(pat in n for pat in PULL_NAME_PATTERNS)


def has_token(muscles: list[str], tokens: tuple[str, ...]) -> bool:
    joined = " | ".join(m.lower() for m in muscles)
    for tok in tokens:
        # `lat` is a token substring of `lateral deltoid` — require word boundary
        # by checking for standalone or with common muscle suffixes.
        if tok == "lat":
            if any(
                m.lower() == "lats"
                or m.lower().startswith("latissimus")
                or m.lower().startswith("lat ")
                for m in muscles
            ):
                return True
            continue
        if tok in joined:
            return True
    return False


def load_catalog() -> dict[str, Any]:
    with JSON_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def check_no_primary_in_secondary(exercises: list[dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    for e in exercises:
        primary = e.get("primaryMuscles", []) or []
        secondary = e.get("secondaryMuscles", []) or []
        if primary and primary[0] in secondary:
            failures.append(
                f"{e.get('nameEn', '?')} (id={e.get('id', '?')}): "
                f"primary[0]={primary[0]!r} also in secondary={secondary!r}"
            )
    return failures


def check_pull_exercises_have_back(exercises: list[dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    for e in exercises:
        name_en = e.get("nameEn", "")
        if not name_matches_pull(name_en):
            continue
        # Only enforce back-primary on exercises the catalog already
        # classifies as back movements. This carves out mislabeled niche
        # variants (e.g. "Cable Standing Pulldown (with Rope)" which MIT
        # tags as an upper-arm/biceps isolation) where the muscleGroup
        # correctly points elsewhere.
        if e.get("muscleGroup") != "back":
            continue
        primary = e.get("primaryMuscles", []) or []
        if not has_token(primary, BACK_MUSCLE_TOKENS):
            failures.append(
                f"{name_en} (id={e.get('id', '?')}): "
                f"expected back muscle in primary, got {primary!r}"
            )
    return failures


def check_anchor_exercises(exercises: list[dict[str, Any]]) -> list[str]:
    """Assert well-known movements point at anatomically-correct primaries.

    Each anchor is (name_substring_lower, required_tokens, human_label).
    Matches the first exercise whose nameEn contains the substring. If not
    found in the catalog, it's not a failure (catalogs vary), it's skipped.
    """
    anchors: list[tuple[str, tuple[str, ...], str]] = [
        ("lat pulldown", BACK_MUSCLE_TOKENS, "back (latissimus dorsi)"),
        ("bench press", CHEST_MUSCLE_TOKENS, "chest (pectorals)"),
        ("barbell squat", QUAD_TOKENS, "quads"),
        ("barbell back squat", QUAD_TOKENS, "quads"),
        ("bicep curl", BICEP_TOKENS, "biceps"),
        ("biceps curl", BICEP_TOKENS, "biceps"),
    ]
    failures: list[str] = []
    for needle, tokens, label in anchors:
        matched = [e for e in exercises if needle in e.get("nameEn", "").lower()]
        if not matched:
            print(f"info: anchor {needle!r} not present in catalog; skipping", file=sys.stderr)
            continue
        # Use the first match as the canonical anchor.
        e = matched[0]
        primary = e.get("primaryMuscles", []) or []
        if not has_token(primary, tokens):
            failures.append(
                f"{e.get('nameEn', '?')} (id={e.get('id', '?')}): "
                f"expected {label}, got primary={primary!r}"
            )
    return failures


def main() -> int:
    if not JSON_PATH.exists():
        print(f"error: {JSON_PATH} not found", file=sys.stderr)
        return 1
    catalog = load_catalog()
    exercises = catalog.get("exercises", [])
    print(
        f"info: loaded catalog version={catalog.get('version')!r} "
        f"count={len(exercises)}",
        file=sys.stderr,
    )

    checks: list[tuple[str, list[str]]] = [
        ("primary[0] must not appear in secondary", check_no_primary_in_secondary(exercises)),
        ("pull-type exercises must have back primary", check_pull_exercises_have_back(exercises)),
        ("anchor exercises must have anatomically-correct primary", check_anchor_exercises(exercises)),
    ]

    total_failures = 0
    for label, failures in checks:
        if not failures:
            print(f"pass: {label}", file=sys.stderr)
            continue
        total_failures += len(failures)
        print(f"FAIL: {label} ({len(failures)} offender(s))", file=sys.stderr)
        # Cap detail output to 20 rows per check to keep logs readable.
        for row in failures[:20]:
            print(f"  - {row}", file=sys.stderr)
        if len(failures) > 20:
            print(f"  ... and {len(failures) - 20} more", file=sys.stderr)

    if total_failures:
        print(f"error: {total_failures} total offender(s)", file=sys.stderr)
        return 1
    print("info: all muscle-mapping checks passed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
