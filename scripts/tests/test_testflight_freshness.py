"""Guard TestFlight triggers, exact candidate capture, marker-range eligibility, and failure boundaries without building or uploading."""
from pathlib import Path
import contextlib
import io
import os
import re
import subprocess
import tempfile
import textwrap
import types
import unittest
from unittest import mock


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"
FASTFILE = ROOT / "fastlane/Fastfile"
PROJECT_YML = ROOT / "project.yml"


def production_gate():
    """Read the actual embedded release gate, without any build/upload steps."""
    workflow_text = WORKFLOW.read_text(encoding="utf-8")
    gate_body = workflow_text.split("python3 - <<'PY_GATE'\n", 1)[1].split("\n          PY_GATE", 1)[0]
    return textwrap.dedent(gate_body)


def load_production_classifier():
    """Compile the shipped endpoint and raw-diff classifier from the workflow."""
    classifier_code = (
        "def is_endpoint_relevant"
        + production_gate().split("def is_endpoint_relevant", 1)[1].split("\n# Capture Candidate", 1)[0]
    )

    module = types.ModuleType("production_testflight_gate")
    exec("import re, subprocess\n" + classifier_code, module.__dict__)
    return module.is_endpoint_relevant, module.classify_diff


is_endpoint_relevant, classify_diff = load_production_classifier()


def raw_diff(records: list[tuple[str, ...]]) -> bytes:
    """Encode records in git diff-tree --raw -z form."""
    output = bytearray()
    for rec in records:
        status = rec[0]
        output.extend(f":100644 100644 0000000 1111111 {status}".encode())
        output.extend(b"\0")
        output.extend(rec[1].encode())
        output.extend(b"\0")
        if status.startswith(("R", "C")):
            output.extend(rec[2].encode())
            output.extend(b"\0")
    return bytes(output)


def classify_raw(records: list[tuple[str, ...]]) -> tuple[bool, list[str]]:
    """Run the shipped parser with raw mocked git output."""
    with mock.patch("subprocess.run") as run:
        run.return_value = mock.Mock(stdout=raw_diff(records), returncode=0)
        result = classify_diff("baseline", "candidate")
    run.assert_called_once_with(
        [
            "git",
            "diff-tree",
            "-r",
            "-z",
            "--no-commit-id",
            "-C",
            "-C",
            "--find-copies-harder",
            "baseline",
            "candidate",
        ],
        capture_output=True,
        check=True,
    )
    return result


class TestFlightRegressionContractTests(unittest.TestCase):
    """Preserve the release contract with schedule/manual source admission."""

    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]
        self.gate_step = self.workflow.split("- name: Decide whether to release\n", 1)[1].split("\n      - name:", 1)[0]

    # 1. exact schedule/manual/main guards, manual force compatibility, and one captured candidate;
    def test_item_1_exact_automatic_guards_and_captured_candidate(self):
        self.assertEqual(re.findall(r"^  ([a-z_]+):", self.triggers, re.M), ["schedule", "workflow_dispatch"])
        self.assertEqual(re.findall(r"cron: '([^']+)'", self.triggers), ["47 6,18 * * *"])
        self.assertIn("workflow_dispatch:", self.triggers)
        self.assertIn("force:", self.triggers)

        self.assertIn(
            "(github.event_name == 'schedule' || github.event_name == 'workflow_dispatch') &&\n"
            "      github.ref == 'refs/heads/main'",
            self.release,
        )
        self.assertNotIn("workflow_run", self.workflow)

        # Both sources checkout main once and capture that snapshot, not the event SHA.
        self.assertEqual(re.findall(r"(?m)^\s+ref: (.+)$", self.release), ["main"])
        self.assertEqual(
            self.gate_step.count('subprocess.check_output(["git", "rev-parse", "HEAD"], text=True)'),
            1,
        )
        self.assertNotIn("github.sha", self.gate_step)
        self.assertIn("SOURCE_REF: ${{ github.ref }}", self.gate_step)
        self.assertIn("FORCE_INPUT: ${{ github.event.inputs.force }}", self.gate_step)

    # 2. marker resolution and literal marker..candidate range;
    def test_item_2_marker_resolution_and_literal_range(self):
        self.assertIn("refs/tags/testflight/last-released", self.gate_step)
        self.assertIn("classify_diff(marker_sha, candidate)", self.gate_step)
        self.assertIn('"-C", "-C", "--find-copies-harder"', self.gate_step)

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
        self.assertTrue(is_endpoint_relevant("VitalStrideMac/Resources/Localizable.strings"))
        self.assertTrue(is_endpoint_relevant("VitalStrideMac/Assets.xcassets/AppIcon.appiconset/icon.png"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWatch Watch App/Sources/WatchApp.swift"))
        self.assertTrue(is_endpoint_relevant("VitalStrideWatch Watch App/Resources/Localizable.strings"))
        self.assertTrue(
            is_endpoint_relevant("VitalStrideWatch Watch App/Assets.xcassets/AppIcon.appiconset/icon.png")
        )

        # Raw NUL parser: add/modify/delete, rename/copy endpoints, and mixed records.
        self.assertTrue(classify_raw([("A", "VitalStride/Sources/New.swift")])[0])
        self.assertTrue(classify_raw([("M", "VitalStride/Sources/App.swift")])[0])
        self.assertTrue(classify_raw([("D", "VitalStride/Sources/App.swift")])[0])
        self.assertFalse(classify_raw([("D", "docs/index.md")])[0])

        self.assertTrue(classify_raw([("R100", "docs/index.md", "VitalStride/Sources/App.swift")])[0])
        self.assertTrue(classify_raw([("R100", "VitalStride/Sources/App.swift", "docs/index.md")])[0])
        self.assertFalse(classify_raw([("R100", "docs/a.md", "docs/b.md")])[0])

        self.assertTrue(classify_raw([("C100", "docs/index.md", "VitalStride/Sources/App.swift")])[0])
        self.assertTrue(classify_raw([("C100", "VitalStride/Sources/App.swift", "docs/index.md")])[0])
        self.assertFalse(classify_raw([("C100", "docs/a.md", "docs/b.md")])[0])

        self.assertTrue(classify_raw([("M", "docs/a.md"), ("M", "VitalStride/Sources/App.swift")])[0])
        self.assertFalse(classify_raw([("M", "docs/a.md"), ("M", "docs/b.md")])[0])

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

    # 6. irrelevant skip, relevant lane decision, manual force decision, and invalid-marker failure;
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

        # Manual force bypasses path eligibility and already-covered skip
        self.assertIn("is_force = (source == 'manual' and force_input)", self.gate_step.replace('"', "'"))
        self.assertIn("candidate == marker_sha and not is_force", self.gate_step)

    # 7. existing-lane call followed by candidate marker update only on lane success;
    def test_item_7_existing_lane_call_and_post_upload_marker_update(self):
        # Verify lane invocation step exists and runs fastlane ios beta
        lane_step = self.workflow.split("- name: fastlane beta\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("fastlane ios beta", lane_step)

        # Verify marker update step is ordered after fastlane beta
        workflow_after_lane = self.workflow.split("- name: fastlane beta\n", 1)[1]
        self.assertIn("- name: Move last-released tag", workflow_after_lane)

        tag_step = workflow_after_lane.split("- name: Move last-released tag\n", 1)[1]
        self.assertIn("if: steps.gate.outputs.release == 'true'", tag_step)
        self.assertNotIn("always()", tag_step)
        self.assertNotIn("continue-on-error", lane_step)
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


class TestFlightGateExecutionTests(unittest.TestCase):
    """Execute the embedded gate with controlled Git responses; never upload or mutate tags."""

    head = "c" * 40
    marker = "b" * 40

    def run_gate(self, *, event="schedule", ref="refs/heads/main", marker=None,
                 marker_state="valid", records=(), force="false", fail_command=None):
        marker = self.marker if marker is None else marker
        calls = []

        def git_run(args, **kwargs):
            calls.append(args)
            if args == ["git", "fetch", "--tags", "origin"]:
                return subprocess.CompletedProcess(args, 0)
            if args == ["git", "rev-parse", "-q", "--verify", "refs/tags/testflight/last-released"]:
                return subprocess.CompletedProcess(args, int(marker_state == "missing"), marker + "\n")
            if args == ["git", "rev-parse", "--verify", f"{marker}^{{commit}}"]:
                return subprocess.CompletedProcess(args, int(marker_state == "noncommit"))
            if args == ["git", "merge-base", "--is-ancestor", marker, self.head]:
                return subprocess.CompletedProcess(args, int(marker_state == "nonancestor"))
            diff_args = ["git", "diff-tree", "-r", "-z", "--no-commit-id", "-C", "-C",
                         "--find-copies-harder", marker, self.head]
            if args == diff_args or args == ["git", "checkout", self.head]:
                if args[1] == fail_command:
                    raise subprocess.CalledProcessError(1, args)
                return subprocess.CompletedProcess(args, 0, raw_diff(records))
            raise AssertionError(f"Unexpected Git command: {args}")

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            summary = Path(directory) / "summary"
            env = {"EVENT_NAME": event, "SOURCE_REF": ref, "FORCE_INPUT": force,
                   "GITHUB_SHA": "a" * 40, "GITHUB_OUTPUT": str(output),
                   "GITHUB_STEP_SUMMARY": str(summary)}
            with mock.patch.dict(os.environ, env, clear=True), \
                    mock.patch("subprocess.run", side_effect=git_run), \
                    mock.patch("subprocess.check_output", return_value=self.head + "\n") as capture, \
                    contextlib.redirect_stdout(io.StringIO()):
                try:
                    exec(compile(production_gate(), str(WORKFLOW), "exec"), {})
                    status = 0
                except SystemExit as error:
                    status = error.code
                except subprocess.CalledProcessError:
                    status = 1
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
            summary_text = summary.read_text() if summary.exists() else ""
        return status, outputs, calls, capture.call_args_list, summary_text

    def test_schedule_and_manual_capture_checkout_head_and_reuse_candidate(self):
        for event, source in [("schedule", "automatic-schedule"), ("workflow_dispatch", "manual")]:
            with self.subTest(event=event):
                status, outputs, calls, captures, summary = self.run_gate(
                    event=event, records=[("M", "VitalStride/Sources/App.swift")])
                self.assertEqual(status, 0)
                self.assertEqual(outputs, {"release": "true", "reason": "eligible",
                                           "candidate": self.head, "source": source})
                self.assertEqual(captures, [mock.call(["git", "rev-parse", "HEAD"], text=True)])
                self.assertIn(["git", "checkout", self.head], calls)
                self.assertIn(f"- **Candidate**: `{self.head}`", summary)

    def test_rejected_events_and_non_main_refs_do_not_read_git_or_release(self):
        cases = [(event, "refs/heads/main", "unsupported-event")
                 for event in ("push", "workflow_run", "pull_request", "pull_request_target", "unexpected")]
        cases += [(event, ref, "unsupported-source-event")
                  for event in ("schedule", "workflow_dispatch")
                  for ref in ("refs/heads/feature", "refs/tags/main", "")]
        for event, ref, reason in cases:
            with self.subTest(event=event, ref=ref):
                status, outputs, calls, captures, _ = self.run_gate(event=event, ref=ref, force="true")
                self.assertEqual(status, 0)
                self.assertEqual(outputs, {"release": "false", "reason": reason, "candidate": "none"})
                self.assertEqual(calls, [])
                self.assertEqual(captures, [])

    def test_same_marker_skips_and_schedule_cannot_force(self):
        for event, force in [("schedule", "false"), ("schedule", "true"), ("workflow_dispatch", "false")]:
            with self.subTest(event=event, force=force):
                status, outputs, calls, _, _ = self.run_gate(event=event, marker=self.head, force=force)
                self.assertEqual(status, 0)
                self.assertEqual(outputs["release"], "false")
                self.assertEqual(outputs["reason"], "already-covered")
                self.assertFalse(any(cmd[1] in ("diff-tree", "checkout") for cmd in calls))

    def test_irrelevant_cumulative_range_skips(self):
        status, outputs, calls, _, _ = self.run_gate(records=[("M", "docs/a.md")], force="true")
        self.assertEqual(status, 0)
        self.assertEqual(outputs["reason"], "path-ineligible")
        self.assertEqual(outputs["release"], "false")
        self.assertFalse(any(cmd[1] == "checkout" for cmd in calls))

    def test_manual_force_releases_equal_or_irrelevant_candidate(self):
        for marker in (self.head, self.marker):
            with self.subTest(marker=marker):
                status, outputs, calls, _, _ = self.run_gate(
                    event="workflow_dispatch", marker=marker, force="true", records=[("M", "docs/a.md")])
                self.assertEqual(status, 0)
                self.assertEqual(outputs["release"], "true")
                self.assertEqual(outputs["reason"], "force")
                self.assertIn(["git", "checkout", self.head], calls)
                self.assertFalse(any(cmd[1] == "diff-tree" for cmd in calls))

    def test_missing_noncommit_or_nonancestor_marker_fails_even_under_manual_force(self):
        for state in ("missing", "noncommit", "nonancestor"):
            for event, force in [("schedule", "false"), ("workflow_dispatch", "true")]:
                with self.subTest(state=state, event=event):
                    status, outputs, calls, _, _ = self.run_gate(
                        marker_state=state, event=event, force=force)
                    self.assertEqual(status, 1)
                    self.assertEqual(outputs["release"], "false")
                    self.assertEqual(outputs["reason"], "marker-missing" if state == "missing" else "marker-invalid")
                    self.assertFalse(any(cmd[1] in ("diff-tree", "checkout") for cmd in calls))

    def test_diff_or_candidate_checkout_failure_fails_the_gate(self):
        for command in ("diff-tree", "checkout"):
            with self.subTest(command=command):
                status, _, _, _, _ = self.run_gate(
                    records=[("M", "VitalStride/Sources/App.swift")], fail_command=command)
                self.assertEqual(status, 1)


if __name__ == "__main__":
    unittest.main()
