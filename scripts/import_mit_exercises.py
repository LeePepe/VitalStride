#!/usr/bin/env python3
"""Generate the pinned VitalStride exercise catalog v5.

Usage:
    python3 scripts/import_mit_exercises.py
    python3 scripts/import_mit_exercises.py --dry-run
    python3 scripts/import_mit_exercises.py --source PATH
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.request
import uuid
from collections import defaultdict
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = REPO_ROOT / "VitalStride" / "Resources" / "exercises.json"
PROVENANCE_PATH = REPO_ROOT / "scripts" / "exercises_dataset_provenance.json"
REPORT_PATH = REPO_ROOT / "docs" / "data" / "exercise-catalog-reconciliation.json"

UUID_NAMESPACE = uuid.UUID("5e2a1f2c-8b3d-4d67-9a2c-1e8f4b5c9a11")
TARGET_VERSION = "5"
SOURCE_NAME = "hasaneyldrm/exercises-dataset"
VITALSTRIDE_SOURCE = "vitalstride"
SOURCE_DATA_KEYS = (
    "id",
    "name",
    "category",
    "body_part",
    "equipment",
    "target",
    "muscle_group",
    "secondary_muscles",
    "instructions",
    "instruction_steps",
    "media_id",
    "image",
    "gif_url",
    "attribution",
    "created_at",
)
PRESERVED_OPTIONAL_FIELDS = ("mediaKey",)
APP_REQUIRED_FIELDS = (
    "id",
    "nameEn",
    "nameZh",
    "muscleGroup",
    "equipment",
    "primaryMuscles",
    "secondaryMuscles",
    "defaultWeightLow",
    "defaultWeightMid",
    "defaultWeightHigh",
)

# Keep these names stable for downstream callers and prior task contracts.
MIT_NAMESPACE = UUID_NAMESPACE

EQUIPMENT_MAP: dict[str, str] = {
    "assisted": "assisted",
    "band": "band",
    "barbell": "barbell",
    "body weight": "bodyweight",
    "bosu ball": "bosu_ball",
    "cable": "cable",
    "dumbbell": "dumbbell",
    "elliptical machine": "elliptical_machine",
    "ez barbell": "ez_barbell",
    "hammer": "hammer",
    "kettlebell": "kettlebell",
    "leverage machine": "leverage_machine",
    "medicine ball": "medicine_ball",
    "olympic barbell": "olympic_barbell",
    "resistance band": "resistance_band",
    "roller": "roller",
    "rope": "rope",
    "skierg machine": "skierg_machine",
    "sled machine": "sled_machine",
    "smith machine": "smith_machine",
    "stability ball": "stability_ball",
    "stationary bike": "stationary_bike",
    "stepmill machine": "stepmill_machine",
    "tire": "tire",
    "trap bar": "trap_bar",
    "upper body ergometer": "upper_body_ergometer",
    "weighted": "weighted",
    "wheel roller": "wheel_roller",
}

BODY_PART_MAP: dict[str, str | None] = {
    "back": "back",
    "cardio": None,
    "chest": "chest",
    "lower arms": "arms",
    "lower legs": "legs",
    "neck": None,
    "shoulders": "shoulders",
    "upper arms": "arms",
    "upper legs": "legs",
    "waist": "core",
}

TARGET_TO_MUSCLE_GROUP: dict[str, str] = {
    "abs": "core",
    "abductors": "legs",
    "adductors": "legs",
    "biceps": "arms",
    "calves": "legs",
    "cardiovascular system": "fullBody",
    "delts": "shoulders",
    "forearms": "arms",
    "glutes": "legs",
    "hamstrings": "legs",
    "lats": "back",
    "levator scapulae": "shoulders",
    "obliques": "core",
    "pectorals": "chest",
    "quads": "legs",
    "serratus anterior": "core",
    "spine": "core",
    "traps": "back",
    "triceps": "arms",
    "upper back": "back",
}


def normalize_name(name: str) -> str:
    """Lowercase, strip punctuation, and collapse whitespace for stable matching."""
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def titleize(name: str) -> str:
    """Title-case an upstream exercise name using the legacy importer rules."""
    words = name.split()
    out: list[str] = []
    for word in words:
        if "/" in word:
            out.append("/".join(part.capitalize() if part else part for part in word.split("/")))
        elif "-" in word:
            out.append("-".join(part.capitalize() if part else part for part in word.split("-")))
        else:
            out.append(word.capitalize())
    return " ".join(out)


def new_preset_id(mit_id: str) -> str:
    return str(uuid.uuid5(UUID_NAMESPACE, mit_id))


def body_part_to_muscle_group(body_part: str, target: str) -> str | None:
    mapped = BODY_PART_MAP.get(body_part)
    if mapped is not None:
        return mapped
    return TARGET_TO_MUSCLE_GROUP.get(target)


def map_equipment(equipment: str) -> str | None:
    return EQUIPMENT_MAP.get(equipment)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def render_json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_json(data), encoding="utf-8")


def load_provenance() -> dict[str, Any]:
    return load_json(PROVENANCE_PATH)


def load_existing_catalog() -> dict[str, Any]:
    return load_json(JSON_PATH)


def load_source_bytes(source: str | None, provenance: dict[str, Any]) -> bytes:
    if source:
        path = Path(source)
        print(f"info: loading source bytes from {path}", file=sys.stderr)
        return path.read_bytes()

    url = provenance["url"]
    print(f"info: downloading pinned source bytes from {url}", file=sys.stderr)
    req = urllib.request.Request(url, headers={"User-Agent": "VitalStride-import/2.0"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def verify_source_bytes(raw_bytes: bytes, provenance: dict[str, Any]) -> str:
    actual_sha = hashlib.sha256(raw_bytes).hexdigest()
    expected_sha = provenance["sha256"]
    if actual_sha != expected_sha:
        raise ValueError(
            f"SHA-256 mismatch for pinned source: expected {expected_sha}, got {actual_sha}"
        )
    return actual_sha


def decode_source_rows(raw_bytes: bytes) -> list[dict[str, Any]]:
    decoded = json.loads(raw_bytes.decode("utf-8"))
    if not isinstance(decoded, list):
        raise ValueError("Pinned source JSON must decode to a top-level array")
    return decoded


def source_data_for_row(row: dict[str, Any]) -> dict[str, Any]:
    return {key: row[key] for key in SOURCE_DATA_KEYS}


def derive_muscles(row: dict[str, Any]) -> tuple[str, list[str], list[str]]:
    target = row.get("target")
    if not isinstance(target, str) or not target.strip():
        raise ValueError(f"missing target for source id={row.get('id')}")

    body_part = row.get("body_part", "")
    derived_group = body_part_to_muscle_group(body_part, target)
    if derived_group is None:
        raise ValueError(
            f"Unmappable muscle group for source id={row.get('id')} body_part={body_part!r} target={target!r}"
        )

    primary = [target]

    secondary: list[str] = []
    for muscle in row.get("secondary_muscles", []) or []:
        if not isinstance(muscle, str) or not muscle:
            continue
        if muscle == target:
            continue
        secondary.append(muscle)
    return derived_group, primary, secondary


def build_upstream_row(
    existing_row: dict[str, Any] | None,
    source_row: dict[str, Any],
    row_id: str,
) -> dict[str, Any]:
    muscle_group, primary_muscles, secondary_muscles = derive_muscles(source_row)
    equipment = map_equipment(source_row.get("equipment", ""))
    if equipment is None:
        raise ValueError(
            f"Unsupported equipment for source id={source_row.get('id')}: {source_row.get('equipment')!r}"
        )

    name_en = titleize(source_row["name"])
    row: dict[str, Any] = {
        "id": row_id,
        "nameEn": name_en,
        "nameZh": existing_row.get("nameZh", name_en) if existing_row else name_en,
        "muscleGroup": muscle_group,
        "equipment": equipment,
        "primaryMuscles": primary_muscles,
        "secondaryMuscles": secondary_muscles,
        "defaultWeightLow": existing_row.get("defaultWeightLow") if existing_row else None,
        "defaultWeightMid": existing_row.get("defaultWeightMid") if existing_row else None,
        "defaultWeightHigh": existing_row.get("defaultWeightHigh") if existing_row else None,
    }
    if existing_row:
        for field in PRESERVED_OPTIONAL_FIELDS:
            if field in existing_row:
                row[field] = existing_row[field]
    row["source"] = SOURCE_NAME
    row["sourceData"] = source_data_for_row(source_row)
    return row


def build_vitalstride_only_row(existing_row: dict[str, Any]) -> dict[str, Any]:
    row = {key: existing_row[key] for key in existing_row if key not in {"source", "sourceData"}}
    row["source"] = VITALSTRIDE_SOURCE
    return row


def validate_existing_catalog(existing_rows: list[dict[str, Any]], source_id_by_derived_id: dict[str, str], legacy_imported_source_ids: set[str]) -> None:
    seen_ids: set[str] = set()
    for row in existing_rows:
        row_id = row.get("id")
        if not isinstance(row_id, str) or not row_id:
            raise ValueError("Existing catalog contains a blank preset id")
        if row_id in seen_ids:
            raise ValueError(f"catalog id collision: duplicate preset id {row_id}")
        seen_ids.add(row_id)

        source_id = source_id_by_derived_id.get(row_id)
        if source_id is None:
            continue

        if source_id in legacy_imported_source_ids:
            continue

        if row.get("source") == SOURCE_NAME and row.get("sourceData", {}).get("id") == source_id:
            continue

        raise ValueError(
            f"catalog id collision: existing row {row_id} occupies derived UUID space for source id {source_id}"
        )


def duplicate_name_groups(source_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in source_rows:
        grouped[normalize_name(titleize(row["name"]))].append(row)

    duplicates: list[dict[str, Any]] = []
    for normalized_name, rows in sorted(grouped.items()):
        if len(rows) < 2:
            continue
        duplicates.append(
            {
                "normalizedName": normalized_name,
                "sourceIds": [row["id"] for row in rows],
            }
        )
    return duplicates


def reconcile_catalog(
    existing_catalog: dict[str, Any],
    verified_rows: list[dict[str, Any]],
    provenance: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    existing_rows = existing_catalog.get("exercises", [])
    if not isinstance(existing_rows, list):
        raise ValueError("Existing catalog must contain an exercises array")

    legacy_imported_source_ids = set(provenance.get("legacyImportedSourceIds", []))
    source_id_by_derived_id = {new_preset_id(row["id"]): row["id"] for row in verified_rows}
    validate_existing_catalog(existing_rows, source_id_by_derived_id, legacy_imported_source_ids)

    existing_by_id = {row["id"]: row for row in existing_rows}
    remaining_existing = [row for row in existing_rows if row["id"] not in source_id_by_derived_id]
    remaining_by_normalized_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in remaining_existing:
        remaining_by_normalized_name[normalize_name(row["nameEn"])].append(row)

    matched_by_existing_uuid: list[dict[str, Any]] = []
    matched_by_original_name: list[dict[str, Any]] = []
    new_upstream: list[dict[str, Any]] = []
    ambiguities: list[dict[str, Any]] = []
    collisions: list[dict[str, Any]] = []
    upstream_rows: list[dict[str, Any]] = []
    final_ids: set[str] = set()
    consumed_original_ids: set[str] = set()

    for source_row in verified_rows:
        source_id = source_row["id"]
        derived_id = new_preset_id(source_id)
        normalized_name = normalize_name(titleize(source_row["name"]))

        if source_id in legacy_imported_source_ids:
            existing_row = existing_by_id.get(derived_id)
            upstream_row = build_upstream_row(existing_row, source_row, derived_id)
            matched_by_existing_uuid.append(
                {
                    "sourceId": source_id,
                    "catalogId": derived_id,
                    "normalizedName": normalized_name,
                }
            )
        else:
            candidates = remaining_by_normalized_name.get(normalized_name, [])
            if len(candidates) > 1:
                ambiguities.append(
                    {
                        "sourceId": source_id,
                        "normalizedName": normalized_name,
                        "candidateCatalogIds": [candidate["id"] for candidate in candidates],
                    }
                )
                continue

            if len(candidates) == 1:
                existing_row = candidates.pop()
                if not candidates:
                    remaining_by_normalized_name.pop(normalized_name, None)
                consumed_original_ids.add(existing_row["id"])
                upstream_row = build_upstream_row(existing_row, source_row, existing_row["id"])
                matched_by_original_name.append(
                    {
                        "sourceId": source_id,
                        "catalogId": existing_row["id"],
                        "normalizedName": normalized_name,
                    }
                )
            else:
                upstream_row = build_upstream_row(None, source_row, derived_id)
                new_upstream.append(
                    {
                        "sourceId": source_id,
                        "catalogId": derived_id,
                        "normalizedName": normalized_name,
                    }
                )

        if upstream_row["id"] in final_ids:
            collisions.append(
                {
                    "sourceId": source_id,
                    "catalogId": upstream_row["id"],
                }
            )
        final_ids.add(upstream_row["id"])
        upstream_rows.append(upstream_row)

    if ambiguities:
        raise ValueError(f"ambiguous VitalStride name matches: {ambiguities}")
    if collisions:
        raise ValueError(f"catalog id collision during reconciliation: {collisions}")

    vitalstride_only_rows = [
        build_vitalstride_only_row(row)
        for row in remaining_existing
        if row["id"] not in consumed_original_ids
    ]
    for row in vitalstride_only_rows:
        if row["id"] in final_ids:
            raise ValueError(f"catalog id collision after preserving VitalStride-only row {row['id']}")
        final_ids.add(row["id"])

    catalog = {
        "version": TARGET_VERSION,
        "exercises": upstream_rows + vitalstride_only_rows,
    }
    report = {
        "provenance": {
            "commit": provenance.get("commit"),
            "sha256": provenance.get("sha256"),
            "url": provenance.get("url"),
        },
        "summary": {
            "catalogExerciseCount": len(catalog["exercises"]),
            "upstreamBackedCount": len(upstream_rows),
            "vitalStrideOnlyCount": len(vitalstride_only_rows),
            "matchedByExistingUUIDCount": len(matched_by_existing_uuid),
            "matchedByOriginalNameCount": len(matched_by_original_name),
            "newUpstreamCount": len(new_upstream),
            "ambiguityCount": 0,
            "collisionCount": 0,
        },
        "matchedByExistingUUID": matched_by_existing_uuid,
        "matchedByOriginalName": matched_by_original_name,
        "newUpstream": new_upstream,
        "vitalStrideOnly": [
            {
                "catalogId": row["id"],
                "nameEn": row["nameEn"],
            }
            for row in vitalstride_only_rows
        ],
        "duplicateNameGroups": duplicate_name_groups(verified_rows),
        "ambiguities": [],
        "collisions": [],
    }
    return catalog, report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="verify and reconcile without writing files")
    parser.add_argument("--source", help="path to a pinned exercises.json snapshot")
    args = parser.parse_args()

    provenance = load_provenance()
    raw_bytes = load_source_bytes(args.source, provenance)
    verify_source_bytes(raw_bytes, provenance)
    verified_rows = decode_source_rows(raw_bytes)
    existing_catalog = load_existing_catalog()

    catalog, report = reconcile_catalog(existing_catalog, verified_rows, provenance)

    print(
        "info: reconciliation summary "
        f"catalog={report['summary']['catalogExerciseCount']} "
        f"upstream={report['summary']['upstreamBackedCount']} "
        f"vitalstride={report['summary']['vitalStrideOnlyCount']} "
        f"uuid={report['summary']['matchedByExistingUUIDCount']} "
        f"name={report['summary']['matchedByOriginalNameCount']} "
        f"new={report['summary']['newUpstreamCount']}",
        file=sys.stderr,
    )

    if args.dry_run:
        print("info: --dry-run; not writing catalog or reconciliation report", file=sys.stderr)
        return 0

    write_json(JSON_PATH, catalog)
    write_json(REPORT_PATH, report)
    print(f"info: wrote {JSON_PATH}", file=sys.stderr)
    print(f"info: wrote {REPORT_PATH}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
