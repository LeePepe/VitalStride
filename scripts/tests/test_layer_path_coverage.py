import importlib.util
import os
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


class RecursiveLayerCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.old_cwd = os.getcwd()
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self.old_cwd)
        self.temp.cleanup()

    def write(self, path, frontmatter):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f"---\n{frontmatter}\n---\n", encoding="utf-8")

    def fixture(self):
        self.write(
            "CONTEXT.md",
            """scope: repo
routes:
  - paths: [Packages]
    context: Packages/CONTEXT.md
    kind: index
  - paths: [App, AppTests]
    context: App/CONTEXT.md
    kind: layer
support_excludes: [docs]""",
        )
        self.write(
            "Packages/CONTEXT.md",
            """scope: Packages
routes:
  - paths: [Packages/Core]
    context: Packages/Core/CONTEXT.md
    kind: layer""",
        )
        self.write(
            "Packages/Core/CONTEXT.md",
            """layer: Core
paths: [Packages/Core]
test_paths: [Packages/Core/Tests]
gate_tier: local-fast
build: swift build
test: swift test""",
        )
        self.write(
            "App/CONTEXT.md",
            """layer: AppUI
paths: [App]
test_paths: [AppTests]
gate_tier: ci-only
build: xcodebuild build
test: xcodebuild test""",
        )

    def test_progressive_resolve_and_exclusion(self):
        self.fixture()
        app = layer_coverage.resolve("App/Root.swift")
        core = layer_coverage.resolve("Packages/Core/Sources/Thing.swift")
        docs = layer_coverage.resolve("docs/plan.md")
        self.assertEqual("AppUI", app["layer"])
        self.assertEqual(("CONTEXT.md", "App/CONTEXT.md"), app["context_chain"])
        self.assertEqual("Core", core["layer"])
        self.assertEqual(3, len(core["context_chain"]))
        self.assertIn("excluded", docs)

    def test_child_unmapped_is_rejected(self):
        self.fixture()
        with self.assertRaisesRegex(layer_coverage.RouteError, "unmapped at Packages/CONTEXT.md"):
            layer_coverage.resolve("Packages/New/Sources/New.swift")

    def test_sibling_overlap_is_rejected(self):
        self.fixture()
        self.write(
            "Packages/CONTEXT.md",
            """scope: Packages
routes:
  - paths: [Packages/Core]
    context: Packages/Core/CONTEXT.md
    kind: layer
  - paths: [Packages/Core/Sources]
    context: Packages/Other/CONTEXT.md
    kind: layer""",
        )
        with self.assertRaisesRegex(layer_coverage.RouteError, "route overlap"):
            layer_coverage.resolve("Packages/Core/Sources/Thing.swift")

    def test_cycle_is_rejected(self):
        self.write(
            "CONTEXT.md",
            """scope: repo
routes:
  - paths: [Loop]
    context: Child/CONTEXT.md
    kind: index""",
        )
        self.write(
            "Child/CONTEXT.md",
            """scope: Child
routes:
  - paths: [Loop]
    context: CONTEXT.md
    kind: index""",
        )
        with self.assertRaisesRegex(layer_coverage.RouteError, "context cycle"):
            layer_coverage.resolve("Loop/file.swift")

    def test_parent_leaf_mismatch_is_rejected(self):
        self.fixture()
        self.write(
            "App/CONTEXT.md",
            """layer: AppUI
paths: [App]
test_paths: []
gate_tier: ci-only
test: xcodebuild test""",
        )
        with self.assertRaisesRegex(layer_coverage.RouteError, "parent/leaf mismatch"):
            layer_coverage.resolve("AppTests/RootTests.swift")


if __name__ == "__main__":
    unittest.main()
