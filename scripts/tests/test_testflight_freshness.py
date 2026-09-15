"""Exercise the actual workflow shell block with a deterministic UTC clock."""

import os
import pathlib
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


class TestFlightFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.freshness = self.workflow.split("  freshness:\n", 1)[1].split(
            "\n  release:\n", 1
        )[0]
        self.script = textwrap.dedent(self.freshness.split("        run: |\n", 1)[1])

    def run_gate(self, clock, schedule="0 19 * * 3", event="schedule"):
        # Keep schedule configuration under test instead of duplicating defaults.
        config = dict(re.findall(r'^          (\w+): "([0-9]+)"$', self.freshness, re.M))
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "output"
            env = {
                **os.environ,
                **config,
                "EVENT_NAME": event,
                "EVENT_SCHEDULE": schedule,
                "GITHUB_OUTPUT": str(output),
                "TEST_UTC_CLOCK": clock,
            }
            fake_clock = '''
date() {
  [[ "$#" == 2 && "$1" == -u && "$2" == '+%w %H %M' ]] || return 2
  printf '%s\n' "$TEST_UTC_CLOCK"
}
'''
            result = subprocess.run(
                ["bash", "-c", fake_clock + self.script],
                env=env, capture_output=True, text=True, timeout=5,
            )
            values = output.read_text(encoding="utf-8") if output.exists() else ""
        return result, values

    def test_weekday_crons_cover_each_day_once(self):
        schedules = re.findall(r'^    - cron: "([^"]+)"', self.workflow, re.M)
        self.assertEqual(schedules, [f"0 19 * * {day}" for day in range(7)])
        self.assertIn("EVENT_SCHEDULE: ${{ github.event.schedule }}", self.freshness)

    def test_schedule_boundaries_and_cross_day_delays(self):
        for clock, schedule, delay, proceed in [
            ("3 19 00", "0 19 * * 3", 0, True),
            ("3 19 30", "0 19 * * 3", 30, True),
            ("3 20 00", "0 19 * * 3", 60, True),
            ("3 20 01", "0 19 * * 3", 61, False),
            ("4 00 00", "0 19 * * 3", 300, False),
            ("4 08 09", "0 19 * * 3", 789, False),
            ("4 19 30", "0 19 * * 3", 1470, False),
            ("0 19 30", "0 19 * * 6", 1470, False),
            ("3 18 59", "0 19 * * 3", 10079, False),
        ]:
            with self.subTest(clock=clock, schedule=schedule):
                result, values = self.run_gate(clock, schedule)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(values, f"proceed={str(proceed).lower()}\n")
                self.assertIn(f"current delay is {delay} minute(s)", result.stdout)

    def test_manual_dispatch_bypasses_schedule_deadline(self):
        result, values = self.run_gate("invalid", schedule="", event="workflow_dispatch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values, "proceed=true\n")

    def test_invalid_weekday_fails_closed(self):
        for schedule in ["", "0 19 * * *", "0 19 * * 7", "0 19 * * x"]:
            with self.subTest(schedule=schedule):
                result, values = self.run_gate("3 19 30", schedule)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(values, "")
                self.assertIn("Unexpected schedule expression", result.stdout)

    def test_release_requires_freshness_approval_before_self_hosted_runner(self):
        release = self.workflow.split("\n  release:\n", 1)[1]
        self.assertIn("runs-on: ubuntu-latest", self.freshness)
        self.assertIn("needs: freshness", release)
        self.assertIn("if: needs.freshness.outputs.proceed == 'true'", release)
        self.assertIn("runs-on: [self-hosted, vitalstride-mac]", release)
