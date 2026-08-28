import os
import pathlib
import re
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ci" / "run-app-target-tests.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
EXPECTED_ARGV = [
    "xcodebuild",
    "test",
    "-project",
    "VitalStride.xcodeproj",
    "-scheme",
    "VitalStride",
    "-destination",
    "platform=iOS Simulator,name=iPhone 17",
    "-skipPackagePluginValidation",
    "-skip-testing:VitalStrideTests/OverviewHealthSnapshotTests/loadAllMetrics",
]


class AppTargetGateRunnerTests(unittest.TestCase):
    def _wait_for_output(self, proc, marker, release_path, timeout=5.0):
        streamed = []
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                line = proc.stdout.readline()
                if not line:
                    if proc.poll() is not None:
                        break
                    continue
                streamed.append(line)
                if marker in line:
                    self.assertIsNone(proc.poll())
                    return "".join(streamed)
            release_path.touch(exist_ok=True)
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
            raise AssertionError(f"Timed out waiting for output marker {marker!r}. Collected output:\n{''.join(streamed)}")
        finally:
            release_path.touch(exist_ok=True)

    def test_controlled_failure_is_single_invocation_and_propagates_exit(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            count = tmp / "count.txt"
            args = tmp / "args.txt"
            release = tmp / "release.txt"
            fake = tmp / "fake-command.sh"
            fake.write_text(
                "#!/usr/bin/env bash\n"
                "count_file=\"${APP_TARGET_COUNT_FILE}\"\n"
                "args_file=\"${APP_TARGET_ARGS_FILE}\"\n"
                "release_file=\"${APP_TARGET_RELEASE_FILE}\"\n"
                "if [ -f \"$count_file\" ]; then\n"
                "  current=$(cat \"$count_file\")\n"
                "else\n"
                "  current=0\n"
                "fi\n"
                "next=$((current + 1))\n"
                "printf '%s\\n' \"$next\" > \"$count_file\"\n"
                "printf '%s\\n' \"$@\" > \"$args_file\"\n"
                "echo 'fake failure progress'\n"
                "while [ ! -f \"$release_file\" ]; do sleep 0.05; done\n"
                "exit 42\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)

            env = os.environ.copy()
            env["APP_TARGET_RUNNER"] = str(fake)
            env["APP_TARGET_COUNT_FILE"] = str(count)
            env["APP_TARGET_ARGS_FILE"] = str(args)
            env["APP_TARGET_RELEASE_FILE"] = str(release)

            proc = subprocess.Popen(
                ["bash", str(SCRIPT)],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=env,
            )
            try:
                output = self._wait_for_output(proc, "fake failure progress", release)
                release.touch(exist_ok=True)
                remaining, _ = proc.communicate(timeout=10)
                output += remaining
                self.assertIn("Starting App target tests", output)
                self.assertIn("fake failure progress", output)
                self.assertIn("App target tests failed with exit status 42", output)
                self.assertIn("::group::App target test output", output)
                self.assertIn("::group::App target failure summary", output)
                self.assertEqual(output.count("::group::"), 2)
                self.assertEqual(output.count("::endgroup::"), 2)
                self.assertEqual(42, proc.returncode)
                self.assertEqual("1\n", count.read_text(encoding="utf-8"))
                recorded = args.read_text(encoding="utf-8").splitlines()
                self.assertEqual(EXPECTED_ARGV, recorded)
                self.assertEqual(1, recorded.count("-skip-testing:VitalStrideTests/OverviewHealthSnapshotTests/loadAllMetrics"))
            finally:
                release.touch(exist_ok=True)
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=3)

    def test_controlled_success_is_single_invocation_and_returns_zero(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            count = tmp / "count.txt"
            args = tmp / "args.txt"
            release = tmp / "release.txt"
            fake = tmp / "fake-command.sh"
            fake.write_text(
                "#!/usr/bin/env bash\n"
                "count_file=\"${APP_TARGET_COUNT_FILE}\"\n"
                "args_file=\"${APP_TARGET_ARGS_FILE}\"\n"
                "release_file=\"${APP_TARGET_RELEASE_FILE}\"\n"
                "if [ -f \"$count_file\" ]; then\n"
                "  current=$(cat \"$count_file\")\n"
                "else\n"
                "  current=0\n"
                "fi\n"
                "next=$((current + 1))\n"
                "printf '%s\\n' \"$next\" > \"$count_file\"\n"
                "printf '%s\\n' \"$@\" > \"$args_file\"\n"
                "echo 'fake success progress'\n"
                "while [ ! -f \"$release_file\" ]; do sleep 0.05; done\n"
                "exit 0\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)

            env = os.environ.copy()
            env["APP_TARGET_RUNNER"] = str(fake)
            env["APP_TARGET_COUNT_FILE"] = str(count)
            env["APP_TARGET_ARGS_FILE"] = str(args)
            env["APP_TARGET_RELEASE_FILE"] = str(release)

            proc = subprocess.Popen(
                ["bash", str(SCRIPT)],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=env,
            )
            try:
                output = self._wait_for_output(proc, "fake success progress", release)
                release.touch(exist_ok=True)
                remaining, _ = proc.communicate(timeout=10)
                output += remaining
                self.assertEqual(0, proc.returncode)
                self.assertEqual("1\n", count.read_text(encoding="utf-8"))
                self.assertIn("Starting App target tests", output)
                self.assertIn("App target tests passed", output)
                self.assertIn("fake success progress", output)
                self.assertIn("::group::App target test output", output)
                self.assertEqual(output.count("::group::"), 1)
                self.assertEqual(output.count("::endgroup::"), 1)
                recorded = args.read_text(encoding="utf-8").splitlines()
                self.assertEqual(EXPECTED_ARGV, recorded)
            finally:
                release.touch(exist_ok=True)
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=3)

    def test_workflow_uses_single_fail_closed_runner(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        marker = "\n  app:\n"
        self.assertIn(marker, text)
        start = text.index(marker)
        end = text.index("\n  # ---- Job C (REQUIRED): lint + policy gates", start)
        app_block = text[start + len(marker):end]
        self.assertIn("name: App target", app_block)
        self.assertEqual(1, app_block.count("bash scripts/ci/run-app-target-tests.sh"))
        self.assertNotIn("continue-on-error", app_block)
        self.assertNotIn("until [ \"$attempt\" -gt \"$max\" ]; do", app_block)
        self.assertNotIn("attempt=1", app_block)


if __name__ == "__main__":
    unittest.main()
