import importlib.util
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("motion_test_analyzer", ROOT / "scripts" / "motion_test_analyzer.py")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


class MotionMetricsTests(unittest.TestCase):
    def test_hard_cut_has_no_intermediate_frames(self):
        result = analyzer.zero_frame_hard_cut([[0], [1]])
        self.assertTrue(result["detected"])
        self.assertEqual(0, result["intermediate_frames"])

    def test_velocity_reversal_is_jitter(self):
        result = analyzer.double_jump_jitter(positions=[0, 0.3, 0.7, 0.5, 1.0])
        self.assertTrue(result["detected"])
        self.assertIn(2, result["velocity_reversals"])

    def test_sandwich_score_flags_single_frame_spike(self):
        result = analyzer.one_frame_flicker([[0, 0], [1, 1], [0, 0]])
        self.assertTrue(result["detected"])
        self.assertIn(1, result["spikes"])

    def test_frozen_run_requires_pause_and_catch_up(self):
        result = analyzer.frozen_frame_jank([0, 50, 180, 190], [0, 0, 0, 10])
        self.assertTrue(result["detected"])
        self.assertEqual(0, result["runs"][0]["start"])

    def test_analyze_motion_has_four_named_metrics(self):
        result = analyzer.analyze_motion(
            frames=[[0], [0.5], [1.0]],
            timestamps_ms=[0, 50, 200],
            positions=[0, 0, 1],
        )
        self.assertEqual(
            {"zero_frame_hard_cut", "double_jump_jitter", "one_frame_flicker", "frozen_frame_jank"},
            set(result),
        )


class ArtifactTests(unittest.TestCase):
    def test_contact_sheet_is_deterministic_and_labels_all_cells(self):
        frames = [[[index]] for index in range(9)]
        first = analyzer.render_contact_sheet_svg(frames)
        second = analyzer.render_contact_sheet_svg(frames)
        self.assertEqual(first, second)
        for index in range(1, 10):
            self.assertIn(f"#{index:02d}", first)
        self.assertIn('fill="red"', first)

    def test_prompt_includes_metrics_and_rubric(self):
        prompt = analyzer.build_vlm_review_prompt({"metric": {"detected": False}})
        self.assertIn("curve_continuity", prompt)
        self.assertIn('"metric"', prompt)

    def test_verdict_schema_and_score_consistency(self):
        verdict = {
            "verdict": "PASS",
            "scores": {axis: 0.9 for axis in analyzer.RUBRIC_AXES},
            "rationale": "Continuous and coherent.",
        }
        self.assertEqual(verdict, analyzer.validate_vlm_verdict(verdict))
        verdict["scores"]["zero_flicker"] = 0.4
        with self.assertRaises(ValueError):
            analyzer.validate_vlm_verdict(verdict)

    def test_cli_writes_json_contact_sheet_and_prompt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "input.json"
            sheet = root / "sheet.svg"
            prompt = root / "prompt.txt"
            source.write_text(json.dumps({"frames": [[0], [1], [2]]}), encoding="utf-8")
            self.assertEqual(0, analyzer.main([str(source), "--contact-sheet", str(sheet), "--prompt", str(prompt)]))
            self.assertTrue(sheet.read_text(encoding="utf-8").startswith("<svg"))
            self.assertIn("zero_frame_hard_cut", prompt.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
