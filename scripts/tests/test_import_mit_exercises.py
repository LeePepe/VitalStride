import hashlib
import importlib.util
import json
import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "import_mit_exercises.py"
CATALOG_PATH = REPO_ROOT / "VitalStride" / "Resources" / "exercises.json"
PROVENANCE_PATH = REPO_ROOT / "scripts" / "exercises_dataset_provenance.json"
REPORT_PATH = REPO_ROOT / "docs" / "data" / "exercise-catalog-reconciliation.json"

LANGUAGES = ("en", "es", "fr", "hi", "it", "ko", "pl", "ru", "tr", "zh")
EXPECTED_EQUIPMENT_MAP = {
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
EXPECTED_SOURCE_EQUIPMENT_VALUES = set(EXPECTED_EQUIPMENT_MAP)
APP_EQUIPMENT_VALUES = set(EXPECTED_EQUIPMENT_MAP.values())
EXPECTED_DUPLICATE_GROUPS = {
    "barbell seated calf raise": ["0088", "1371"],
    "dumbbell close grip press": ["0296", "1731"],
    "dumbbell standing one arm curl over incline bench": ["0422", "1680"],
    "ez barbell spider curl": ["0454", "1628"],
    "lever chest press": ["0576", "0577"],
    "push up on stability ball": ["0655", "0656"],
    "self assisted inverse leg curl": ["0697", "1766"],
    "smith reverse calf raises": ["0763", "1394"],
}


def load_module():
    spec = importlib.util.spec_from_file_location("import_mit_exercises", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def make_source_row(
    source_id: str,
    name: str,
    *,
    body_part: str = "back",
    category: str | None = None,
    equipment: str = "cable",
    target: str = "lats",
    muscle_group: str = "biceps",
    secondary_muscles: list[str] | None = None,
) -> dict[str, object]:
    category = category or body_part
    secondary_muscles = secondary_muscles or ["biceps", "forearms"]
    instructions = {lang: f"{name} instructions {lang}" for lang in LANGUAGES}
    instruction_steps = {
        lang: [f"{name} step 1 {lang}", f"{name} step 2 {lang}"] for lang in LANGUAGES
    }
    return {
        "id": source_id,
        "name": name,
        "category": category,
        "body_part": body_part,
        "equipment": equipment,
        "target": target,
        "muscle_group": muscle_group,
        "secondary_muscles": secondary_muscles,
        "instructions": instructions,
        "instruction_steps": instruction_steps,
        "media_id": f"media-{source_id}",
        "image": f"images/{source_id}.jpg",
        "gif_url": f"videos/{source_id}.gif",
        "attribution": "© Gym visual — https://gymvisual.com/",
        "created_at": "2026-03-18T12:31:32.875385+00:00",
    }


def make_existing_row(
    row_id: str,
    name_en: str,
    *,
    name_zh: str,
    muscle_group: str = "back",
    equipment: str = "cable",
    primary_muscles: list[str] | None = None,
    secondary_muscles: list[str] | None = None,
    weights: tuple[float | None, float | None, float | None] = (60.0, 45.0, 30.0),
    media_key: str | None = None,
) -> dict[str, object]:
    primary_muscles = primary_muscles or ["lats"]
    secondary_muscles = secondary_muscles or ["biceps", "forearms"]
    row = {
        "id": row_id,
        "nameEn": name_en,
        "nameZh": name_zh,
        "muscleGroup": muscle_group,
        "equipment": equipment,
        "primaryMuscles": primary_muscles,
        "secondaryMuscles": secondary_muscles,
        "defaultWeightLow": weights[0],
        "defaultWeightMid": weights[1],
        "defaultWeightHigh": weights[2],
    }
    if media_key is not None:
        row["mediaKey"] = media_key
    return row


def app_fields(row: dict[str, object]) -> dict[str, object]:
    return {k: v for k, v in row.items() if k not in {"source", "sourceData"}}


class ImportMITExercisesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = load_module()

    def test_verify_source_bytes_rejects_checksum_mismatch(self) -> None:
        provenance = {"sha256": "0" * 64}
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            self.module.verify_source_bytes(b"[]", provenance)

    def test_derive_muscles_rejects_whitespace_only_target(self) -> None:
        source_row = make_source_row(
            "missing-target",
            "invalid primary fallback",
            target="   ",
            muscle_group="biceps",
        )

        with self.assertRaisesRegex(ValueError, "missing target"):
            self.module.derive_muscles(source_row)

    def test_derive_muscles_preserves_ordered_non_primary_duplicates(self) -> None:
        source_row = make_source_row(
            "duplicate-secondaries",
            "duplicate secondary muscles",
            target="lats",
            secondary_muscles=["biceps", "biceps", "lats", "forearms", "biceps"],
        )

        _, primary, secondary = self.module.derive_muscles(source_row)

        self.assertEqual(primary, ["lats"])
        self.assertEqual(secondary, ["biceps", "biceps", "forearms", "biceps"])

    def test_equipment_map_covers_all_28_upstream_values(self) -> None:
        self.assertEqual(self.module.EQUIPMENT_MAP, EXPECTED_EQUIPMENT_MAP)
        self.assertEqual(set(self.module.EQUIPMENT_MAP.values()), APP_EQUIPMENT_VALUES)

    def test_reconcile_catalog_preserves_duplicates_and_is_byte_stable(self) -> None:
        source_existing = make_source_row("1001", "cable pulldown")
        source_name_match = make_source_row(
            "2001",
            "tire flip",
            body_part="upper legs",
            category="upper legs",
            equipment="tire",
            target="glutes",
            muscle_group="quads",
            secondary_muscles=["quads", "hamstrings"],
        )
        source_duplicate = make_source_row(
            "2002",
            "tire flip",
            body_part="upper legs",
            category="upper legs",
            equipment="tire",
            target="glutes",
            muscle_group="quads",
            secondary_muscles=["quads", "hamstrings"],
        )
        source_new = make_source_row(
            "3001",
            "band face pull",
            body_part="shoulders",
            category="shoulders",
            equipment="band",
            target="rear delts",
            muscle_group="traps",
            secondary_muscles=["traps", "upper back"],
        )
        verified_rows = [source_existing, source_name_match, source_duplicate, source_new]

        existing_catalog = {
            "version": "4",
            "exercises": [
                make_existing_row(
                    self.module.new_preset_id("1001"),
                    "Legacy Cable Pulldown",
                    name_zh="高位下拉",
                    muscle_group="arms",
                    equipment="machine",
                    primary_muscles=["biceps"],
                    secondary_muscles=["forearms"],
                    weights=(70.0, 55.0, 40.0),
                    media_key="legacy-cable",
                ),
                make_existing_row(
                    "550e8400-e29b-41d4-a716-446655440285",
                    "Tire Flip",
                    name_zh="轮胎翻转",
                    muscle_group="fullBody",
                    equipment="barbell",
                    primary_muscles=["legs"],
                    secondary_muscles=["back"],
                    weights=(110.0, 90.0, 70.0),
                    media_key="legacy-tire",
                ),
                make_existing_row(
                    "550e8400-e29b-41d4-a716-446655440999",
                    "VitalStride Original",
                    name_zh="VitalStride 原创动作",
                    muscle_group="core",
                    equipment="bodyweight",
                    primary_muscles=["abs"],
                    secondary_muscles=["obliques"],
                    weights=(None, None, None),
                    media_key="vital-only",
                ),
            ],
        }
        provenance = {
            "sha256": hashlib.sha256(json.dumps(verified_rows, ensure_ascii=False).encode("utf-8")).hexdigest(),
            "legacyImportedSourceIds": ["1001"],
        }

        catalog_one, report_one = self.module.reconcile_catalog(existing_catalog, verified_rows, provenance)
        catalog_two, report_two = self.module.reconcile_catalog(catalog_one, verified_rows, provenance)

        self.assertEqual(catalog_one["version"], "5")
        self.assertEqual(
            json.dumps(catalog_one, ensure_ascii=False, indent=2),
            json.dumps(catalog_two, ensure_ascii=False, indent=2),
        )
        self.assertEqual(
            json.dumps(report_one, ensure_ascii=False, indent=2),
            json.dumps(report_two, ensure_ascii=False, indent=2),
        )

        summary = report_one["summary"]
        self.assertEqual(summary["catalogExerciseCount"], 5)
        self.assertEqual(summary["upstreamBackedCount"], 4)
        self.assertEqual(summary["vitalStrideOnlyCount"], 1)
        self.assertEqual(summary["matchedByExistingUUIDCount"], 1)
        self.assertEqual(summary["matchedByOriginalNameCount"], 1)
        self.assertEqual(summary["newUpstreamCount"], 2)
        self.assertEqual(summary["ambiguityCount"], 0)
        self.assertEqual(summary["collisionCount"], 0)

        rows_by_source_id = {
            row["sourceData"]["id"]: row
            for row in catalog_one["exercises"]
            if row["source"] == "hasaneyldrm/exercises-dataset"
        }
        self.assertEqual(set(rows_by_source_id), {"1001", "2001", "2002", "3001"})

        cable = rows_by_source_id["1001"]
        self.assertEqual(cable["id"], self.module.new_preset_id("1001"))
        self.assertEqual(cable["nameEn"], "Cable Pulldown")
        self.assertEqual(cable["nameZh"], "高位下拉")
        self.assertEqual(cable["mediaKey"], "legacy-cable")
        self.assertEqual(cable["defaultWeightLow"], 70.0)
        self.assertEqual(cable["defaultWeightMid"], 55.0)
        self.assertEqual(cable["defaultWeightHigh"], 40.0)
        self.assertEqual(cable["muscleGroup"], "back")
        self.assertEqual(cable["equipment"], "cable")
        self.assertEqual(cable["primaryMuscles"], ["lats"])
        self.assertEqual(cable["secondaryMuscles"], ["biceps", "forearms"])
        self.assertEqual(cable["sourceData"], source_existing)
        self.assertEqual(set(cable["sourceData"]["instructions"].keys()), set(LANGUAGES))
        self.assertEqual(set(cable["sourceData"]["instruction_steps"].keys()), set(LANGUAGES))

        inherited = rows_by_source_id["2001"]
        self.assertEqual(inherited["id"], "550e8400-e29b-41d4-a716-446655440285")
        self.assertEqual(inherited["nameZh"], "轮胎翻转")
        self.assertEqual(inherited["mediaKey"], "legacy-tire")
        self.assertEqual(inherited["equipment"], "tire")
        self.assertEqual(inherited["sourceData"], source_name_match)
        duplicate = rows_by_source_id["2002"]
        self.assertEqual(duplicate["id"], self.module.new_preset_id("2002"))
        self.assertEqual(duplicate["nameZh"], "Tire Flip")
        self.assertEqual(duplicate["equipment"], "tire")
        self.assertEqual(duplicate["sourceData"], source_duplicate)
        self.assertIsNone(duplicate["defaultWeightLow"])
        self.assertIsNone(duplicate["defaultWeightMid"])
        self.assertIsNone(duplicate["defaultWeightHigh"])
        self.assertNotIn("mediaKey", duplicate)

        band = rows_by_source_id["3001"]
        self.assertEqual(band["equipment"], "band")
        self.assertEqual(band["sourceData"], source_new)

        vital_only = next(
            row for row in catalog_one["exercises"] if row["source"] == "vitalstride"
        )
        self.assertEqual(vital_only["id"], "550e8400-e29b-41d4-a716-446655440999")
        self.assertEqual(app_fields(vital_only), app_fields(existing_catalog["exercises"][2]))
        self.assertNotIn("sourceData", vital_only)

        duplicate_groups = {
            group["normalizedName"]: group["sourceIds"]
            for group in report_one["duplicateNameGroups"]
        }
        self.assertEqual(duplicate_groups, {"tire flip": ["2001", "2002"]})

    def test_reconcile_catalog_rejects_ambiguous_name_matches(self) -> None:
        source_row = make_source_row("4001", "close grip push up", body_part="chest", category="chest", equipment="body weight", target="pectorals")
        existing_catalog = {
            "version": "4",
            "exercises": [
                make_existing_row("legacy-1", "Close-Grip Push-Up", name_zh="窄距俯卧撑 A", muscle_group="chest", equipment="bodyweight"),
                make_existing_row("legacy-2", "Close Grip Push Up", name_zh="窄距俯卧撑 B", muscle_group="chest", equipment="bodyweight"),
            ],
        }
        provenance = {"sha256": "irrelevant", "legacyImportedSourceIds": []}
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.module.reconcile_catalog(existing_catalog, [source_row], provenance)

    def test_reconcile_catalog_rejects_catalog_id_collisions(self) -> None:
        existing_catalog = {
            "version": "4",
            "exercises": [
                make_existing_row("duplicate-id", "Legacy A", name_zh="旧动作 A"),
                make_existing_row("duplicate-id", "Legacy B", name_zh="旧动作 B"),
            ],
        }
        provenance = {"sha256": "irrelevant", "legacyImportedSourceIds": []}
        with self.assertRaisesRegex(ValueError, "collision"):
            self.module.reconcile_catalog(existing_catalog, [make_source_row("5001", "row")], provenance)


class CheckedInExerciseCatalogTests(unittest.TestCase):
    def test_provenance_manifest_is_pinned(self) -> None:
        manifest = json.loads(PROVENANCE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(manifest["commit"], "7455efae41b330c265e7cd4b78dfa848e7ce5ebd")
        self.assertEqual(
            manifest["sha256"],
            "656634224b8977b99a6d765470ee123260d4979715eaa4e7c0b7c8bb0d79f93d",
        )
        self.assertEqual(
            manifest["sourceSnapshotTimestamp"],
            "2026-07-16T06:50:40Z",
        )
        self.assertTrue(manifest["url"].endswith("/7455efae41b330c265e7cd4b78dfa848e7ce5ebd/data/exercises.json"))
        self.assertEqual(len(manifest["legacyImportedSourceIds"]), 1135)

    def test_checked_in_v5_catalog_and_report_are_consistent(self) -> None:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        report = json.loads(REPORT_PATH.read_text(encoding="utf-8"))

        self.assertEqual(catalog["version"], "5")
        self.assertEqual(len(catalog["exercises"]), 1558)

        upstream_rows = [row for row in catalog["exercises"] if row["source"] == "hasaneyldrm/exercises-dataset"]
        vital_rows = [row for row in catalog["exercises"] if row["source"] == "vitalstride"]
        self.assertEqual(len(upstream_rows), 1324)
        self.assertEqual(len(vital_rows), 234)

        source_ids = [row["sourceData"]["id"] for row in upstream_rows]
        self.assertEqual(len(source_ids), 1324)
        self.assertEqual(len(set(source_ids)), 1324)

        for row in upstream_rows:
            self.assertIn(row["equipment"], APP_EQUIPMENT_VALUES)
            self.assertEqual(set(row["sourceData"]["instructions"].keys()), set(LANGUAGES))
            self.assertEqual(set(row["sourceData"]["instruction_steps"].keys()), set(LANGUAGES))
            self.assertEqual(
                set(row["sourceData"].keys()),
                {
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
                },
            )

        source_equipment_values = {row["sourceData"]["equipment"] for row in upstream_rows}
        self.assertEqual(source_equipment_values, EXPECTED_SOURCE_EQUIPMENT_VALUES)

        cable = next(row for row in upstream_rows if row["sourceData"]["id"] == "0198")
        self.assertEqual(cable["primaryMuscles"], ["lats"])
        self.assertEqual(cable["secondaryMuscles"], ["biceps", "forearms"])

        duplicate_groups = {
            group["normalizedName"]: sorted(group["sourceIds"])
            for group in report["duplicateNameGroups"]
        }
        self.assertEqual(duplicate_groups, EXPECTED_DUPLICATE_GROUPS)

        self.assertEqual(
            report["summary"],
            {
                "catalogExerciseCount": 1558,
                "upstreamBackedCount": 1324,
                "vitalStrideOnlyCount": 234,
                "matchedByExistingUUIDCount": 1135,
                "matchedByOriginalNameCount": 66,
                "newUpstreamCount": 123,
                "ambiguityCount": 0,
                "collisionCount": 0,
            },
        )

    def test_no_media_binaries_are_vendored(self) -> None:
        forbidden = []
        for root in [REPO_ROOT / "docs", REPO_ROOT / "scripts", REPO_ROOT / "VitalStride" / "Resources"]:
            forbidden.extend(root.rglob("*.jpg"))
            forbidden.extend(root.rglob("*.gif"))
        self.assertEqual(forbidden, [])


if __name__ == "__main__":
    unittest.main()
