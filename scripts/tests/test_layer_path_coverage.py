import importlib.util
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts/lib/layer_coverage.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("layer_coverage", MODULE_PATH)
layer_coverage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(layer_coverage)


class LayerPathCoverageTests(unittest.TestCase):
    def context(self, directory: pathlib.Path, name: str, body: str) -> str:
        path = directory / name
        path.write_text(f"---\n{body}\n---\n", encoding="utf-8")
        return str(path)

    def test_positive_coverage_with_support_and_generated_exclusions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            context = self.context(
                root,
                "infra.md",
                "\n".join(
                    [
                        "layer: RepoInfra",
                        "paths: [scripts]",
                        "support_excludes: [docs]",
                        "generated_excludes: ['*.log']",
                    ]
                ),
            )
            self.assertEqual(
                [],
                layer_coverage.classify(
                    ["scripts/check.sh", "docs/plan.md", "build.log"], [context]
                ),
            )

    def test_unmapped_path_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            context = self.context(root, "infra.md", "layer: RepoInfra\npaths: [scripts]")
            self.assertEqual(
                ["unmapped tracked path: tools/new.py"],
                layer_coverage.classify(["tools/new.py"], [context]),
            )

    def test_owner_overlap_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            first = self.context(root, "first.md", "layer: One\npaths: [scripts]")
            second = self.context(root, "second.md", "layer: Two\npaths: [scripts/ci]")
            errors = layer_coverage.classify(["scripts/ci/gate.sh"], [first, second])
            self.assertEqual(["owner overlap: scripts/ci/gate.sh -> ['One', 'Two']"], errors)

if __name__ == "__main__":
    unittest.main()
