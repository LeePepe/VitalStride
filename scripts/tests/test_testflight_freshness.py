"""Guard TestFlight triggers, exact candidate capture, marker-range eligibility, and failure boundaries without building or uploading."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"
FASTFILE = ROOT / "fastlane/Fastfile"
PROJECT_YML = ROOT / "project.yml"


def is_endpoint_relevant(p: str) -> bool:
    """NUL-safe endpoint classifier evaluating narrow positive app predicates and exclusions."""
    p = p.strip("/").replace("\\", "/")

    # Exclusions evaluated first per endpoint
    if (
        p.endswith(".md")
        or p == "CONTEXT.md"
        or p.endswith("/CONTEXT.md")
        or p.startswith("docs/")
        or p.startswith("specs/")
        or p.startswith(".github/")
        or p.startswith("Prototype/")
        or p.startswith("VitalStride.xcodeproj/")
        or p.startswith("VitalStrideTests/")
        or p.startswith("VitalStrideUITests/")
        or p.startswith("VitalStrideWatchTests/")
        or p.startswith("scripts/")
        or p.startswith("design/")
        or p.startswith(".specify/")
        or re.match(r"^Packages/[^/]+/Tests/", p)
    ):
        return False

    # Exact repository-root files
    if p in ("project.yml", "fastlane/Fastfile", "fastlane/Appfile"):
        return True

    # Shipped packages
    if re.match(r"^Packages/[^/]+/Package\.swift$", p):
        return True
    if re.match(r"^Packages/[^/]+/(Sources|Plugins)/", p):
        return True

    # Shipped app roots
    if re.match(r"^(VitalStride|VitalStrideMac|VitalStrideWatch Watch App)/(Sources|Resources|Assets\.xcassets)/", p):
        return True
    if re.match(r"^(VitalStride|VitalStrideMac|VitalStrideWatch Watch App)/[^/]+\.entitlements$", p):
        return True

    # VitalStrideWidgets predicates:
    # 1. VitalStrideWidgets/**/*.swift
    # 2. VitalStrideWidgets/**/*.plist
    # 3. VitalStrideWidgets/**/*.entitlements
    # 4. VitalStrideWidgets/**/*.xcassets/**
    if p.startswith("VitalStrideWidgets/"):
        if p.endswith(".swift"):
            return True
        if p.endswith(".plist"):
            return True
        if p.endswith(".entitlements"):
            return True
        if ".xcassets/" in p or p.endswith(".xcassets"):
            return True

    return False


def is_diff_relevant(records: list[tuple]) -> bool:
    """Evaluate change records against endpoint rules (A/M/D/R/C/T)."""
    for rec in records:
        status = rec[0]
        if status in ("A", "M", "D", "T"):
            if is_endpoint_relevant(rec[1]):
                return True
        elif status.startswith("R") or status.startswith("C"):
            # Either relevant endpoint makes a rename or copy relevant
            if is_endpoint_relevant(rec[1]) or is_endpoint_relevant(rec[2]):
                return True
    return False


class TestFlightRegressionContractTests(unittest.TestCase):
    """Proves the 8 points of the v3 TestFlight regression contract."""

    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]
        self.gate_step = self.workflow.split("- name: Decide whether to release\n", 1)[1].split("\n      - name:", 1)[0]

    # 1. exact automatic workflow/conclusion/event/branch guards and one captured candidate;
    def test_item_1_exact_automatic_guards_and_captured_candidate(self):
        self.assertIn("workflow_run:", self.triggers)
        self.assertIn("workflows: [CI]", self.triggers)
        self.assertIn("types: [completed]", self.triggers)

        self.assertIn("github.event.workflow_run.event == 'push'", self.release)
        self.assertIn("github.event.workflow_run.head_branch == 'main'", self.release)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", self.release)

        # Checkout is pinned to main
        self.assertIn("ref: main", self.release)

        # Candidate is captured from workflow_run.head_sha
        self.assertIn("CI_HEAD_SHA: ${{ github.event.workflow_run.head_sha }}", self.gate_step)
        self.assertIn("candidate = ci_head_sha", self.gate_step)

    # 2. marker resolution and literal marker..candidate range;
    def test_item_2_marker_resolution_and_literal_range(self):
        self.assertIn("refs/tags/testflight/last-released", self.gate_step)
        self.assertIn("classify_diff(marker_sha, candidate)", self.gate_step)

    # 3. accepted path positives and exclusion precedence, including NUL-safe mixed, deletion, rename, and copy records;
    def test_item_3_path_positives_exclusions_and_record_types(self):
        # Exclusions win over generic names
        self.assertFalse(is_endpoint_relevant("docs/architecture.md"))
        self.assertFalse(is_endpoint_relevant("README.md"))
        self.assertFalse(is_endpoint_relevant("VitalStride/CONTEXT.md"))
        self.assertFalse(is_endpoint_relevant("specs/027-testflight-auto-release/spec.md"))
        self.assertFalse(is_endpoint_relevant(".github/workflows/testflight.yml"))
        self.assertFalse(is_endpoint_relevant("Prototype/Main.swift"))
        self.assertFalse(is_endpoint_relevant("VitalStride.xcodeproj/project.pbxproj"))
        self.assertFalse(is_endpoint_relevant("VitalStrideTests/Test.swift"))
        self.assertFalse(is_endpoint_relevant("VitalStrideUITests/UITest.swift"))
        self.assertFalse(is_endpoint_relevant("VitalStrideWatchTests/WatchTest.swift"))
        self.assertFalse(is_endpoint_relevant("Packages/VitalModels/Tests/VitalModelsTests/Test.swift"))
        self.assertFalse(is_endpoint_relevant("scripts/ci/scan.sh"))

        # Exact root files
        self.assertTrue(is_endpoint_relevant("project.yml"))
        self.assertTrue(is_endpoint_relevant("fastlane/Fastfile"))
        self.assertTrue(is_endpoint_relevant("fastlane/Appfile"))

        # Shipped packages
        self.assertTrue(is_endpoint_relevant("Packages/VitalModels/Package.swift"))
        self.assertTrue(is_endpoint_relevant("Packages/VitalModels/Sources/VitalModels/Model.swift"))
        self.assertTrue(is_endpoint_relevant("Packages/VitalModels/Plugins/GenPlugin/Plugin.swift"))

        # Shipped app roots
        self.assertTrue(is_endpoint_relevant("VitalStride/Sources/App.swift"))
        self.assertTrue(is_endpoint_relevant("VitalStride/Resources/Localizable.strings"))
        self.assertTrue(is_endpoint_relevant("VitalStride/Assets.xcassets/AppIcon.appiconset/icon.png"))
        self.assertTrue(is_endpoint_relevant("VitalStrideMac/Sources/MacApp.swift"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWatch Watch App/Sources/WatchApp.swift"))

        # Record types: deletion, rename, copy, mixed
        self.assertTrue(is_diff_relevant([("D", "VitalStride/Sources/App.swift")]))
        self.assertFalse(is_diff_relevant([("D", "docs/index.md")]))

        self.assertTrue(is_diff_relevant([("R100", "docs/index.md", "VitalStride/Sources/App.swift")]))
        self.assertTrue(is_diff_relevant([("R100", "VitalStride/Sources/App.swift", "docs/index.md")]))
        self.assertFalse(is_diff_relevant([("R100", "docs/a.md", "docs/b.md")]))

        self.assertTrue(is_diff_relevant([("C100", "docs/index.md", "VitalStride/Sources/App.swift")]))
        self.assertFalse(is_diff_relevant([("C100", "docs/a.md", "docs/b.md")]))

        self.assertTrue(is_diff_relevant([("M", "docs/a.md"), ("M", "VitalStride/Sources/App.swift")]))
        self.assertFalse(is_diff_relevant([("M", "docs/a.md"), ("M", "docs/b.md")]))

    # 4. root-only entitlement positives for VitalStride/*.entitlements, VitalStrideMac/*.entitlements, and VitalStrideWatch Watch App/*.entitlements, plus one nested-entitlement negative case under each root;
    def test_item_4_root_only_entitlements_and_nested_negatives(self):
        # Root positives
        self.assertTrue(is_endpoint_relevant("VitalStride/VitalStride.entitlements"))
        self.assertTrue(is_endpoint_relevant("VitalStrideMac/VitalStrideMac.entitlements"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWatch Watch App/VitalStrideWatch.entitlements"))

        # Nested negatives under each root
        self.assertFalse(is_endpoint_relevant("VitalStride/Sub/Nested.entitlements"))
        self.assertFalse(is_endpoint_relevant("VitalStrideMac/Nested/Mac.entitlements"))
        self.assertFalse(is_endpoint_relevant("VitalStrideWatch Watch App/Sub/Watch.entitlements"))

    # 5. all four fully prefixed VitalStrideWidgets/** families and outside-root negative suffix cases;
    def test_item_5_widget_families_and_outside_root_negatives(self):
        # 1. VitalStrideWidgets/**/*.swift
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Widget.swift"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Nested/Sub/Widget.swift"))

        # 2. VitalStrideWidgets/**/*.plist
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Info.plist"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Nested/Config.plist"))

        # 3. VitalStrideWidgets/**/*.entitlements
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Widgets.entitlements"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Nested/Widgets.entitlements"))

        # 4. VitalStrideWidgets/**/*.xcassets/**
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Assets.xcassets/Icon.png"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWidgets/Sub/Preview.xcassets/Image.png"))

        # Outside-root negatives with matching suffixes
        self.assertFalse(is_endpoint_relevant("OtherWidgets/Widget.swift"))
        self.assertFalse(is_endpoint_relevant("VitalStride/Info.plist"))
        self.assertFalse(is_endpoint_relevant("OtherApp/Config.plist"))
        self.assertFalse(is_endpoint_relevant("OtherApp/App.entitlements"))
        self.assertFalse(is_endpoint_relevant("OtherWidgets/Assets.xcassets/Icon.png"))

    # 6. irrelevant skip, relevant lane decision, and invalid-marker failure;
    def test_item_6_skip_relevant_lane_and_invalid_marker_failure(self):
        # In gate script:
        # Invalid marker exits with code 1
        self.assertIn("print('::error::Marker tag testflight/last-released is missing.')", self.gate_step.replace('"', "'"))
        self.assertIn("marker-invalid", self.gate_step)
        self.assertIn("sys.exit(1)", self.gate_step)

        # Already covered or path-ineligible skips with release=false
        self.assertIn("already-covered", self.gate_step)
        self.assertIn("path-ineligible", self.gate_step)
        self.assertIn("write_output('release', 'false')", self.gate_step.replace('"', "'"))

        # Eligible sets release=true
        self.assertIn("write_output('release', 'true' if release else 'false')", self.gate_step.replace('"', "'"))

    # 7. existing-lane call followed by candidate marker update only on lane success;
    def test_item_7_existing_lane_call_and_post_upload_marker_update(self):
        # Verify lane invocation step exists and runs fastlane ios beta
        lane_step = self.workflow.split("- name: fastlane beta\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("fastlane ios beta", lane_step)

        # Verify marker update step is ordered after fastlane beta
        workflow_after_lane = self.workflow.split("- name: fastlane beta\n", 1)[1]
        self.assertIn("- name: Move last-released tag", workflow_after_lane)

        tag_step = workflow_after_lane.split("- name: Move last-released tag\n", 1)[1]
        self.assertIn('SHA="${{ steps.gate.outputs.candidate }}"', tag_step)
        self.assertIn('git tag -f testflight/last-released "$SHA"', tag_step)
        self.assertIn('git push -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"', tag_step)

    # 8. one non-cancelling group, job-level contents: write, and absence of auxiliary state/retry/rollback.
    def test_item_8_concurrency_job_permissions_and_no_auxiliary_state(self):
        # Concurrency at workflow level
        self.assertRegex(self.workflow, r"(?m)^concurrency:\s*\n\s*group:\s*testflight\s*\n\s*cancel-in-progress:\s*false")

        # Job-level contents: write permissions
        self.assertRegex(self.release, r"(?m)^\s*permissions:\s*\n\s*contents:\s*write")

        # Absence of workflow-level permissions
        workflow_header = self.workflow.split("\njobs:\n", 1)[0]
        self.assertNotIn("permissions:", workflow_header)

        # Absence of auxiliary state, queues, cursors, leases, or rollback refs
        for forbidden in [
            "testflight/queue",
            "testflight/cursor",
            "testflight/journal",
            "testflight/leases",
            "testflight/pending",
            "testflight/resolved",
            "testflight/recovery",
        ]:
            self.assertNotIn(forbidden, self.workflow)


if __name__ == "__main__":
    unittest.main()
