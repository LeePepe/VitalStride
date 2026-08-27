import contextlib
import importlib.util
import io
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


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


class ResolverRunCommandRegressionTests(unittest.TestCase):
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

    def fixture(self, *, build_command: str = "swift build --package-path Packages/Core", test_command: str = "swift test --package-path Packages/Core"):
        self.write(
            "CONTEXT.md",
            """scope: repo
routes:
  - paths: [Packages]
    context: Packages/CONTEXT.md
    kind: index
  - paths: [App]
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
            f"""layer: Core
paths: [Packages/Core]
test_paths: [Packages/Core/Tests]
gate_tier: local-fast
build: {build_command}
test: {test_command}""",
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

    def test_run_uses_argv_without_shell(self):
        self.fixture(build_command="swift build --package-path Packages/Core")
        with mock.patch("layer_coverage.subprocess.run", return_value=mock.Mock(returncode=0)) as run_mock:
            rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(0, rc)
        run_mock.assert_called_once_with(["swift", "build", "--package-path", "Packages/Core"], shell=False)

    def test_run_rejects_malformed_and_shell_control(self):
        unsafe = [
            'python3 -c "print(\'hello\')" && echo nope',
            'python3 -c "print(\'hello\')" > /tmp/boom',
            'python3 -c "print(\'hello\')" $(whoami)',
            'python3 -c "print(\'hello\')',
            '""',
            '/usr/bin/env python3 -c "print(\'hello\')"',
            "bash -lc 'echo nope'",
            "bash /tmp/payload.sh",
            "python3 -c \"open('/tmp/pwn','w').close()\"",
        ]

        for command in unsafe:
            self.fixture(build_command=command)
            with mock.patch("layer_coverage.subprocess.run") as run_mock:
                rc = layer_coverage.main(["run", "Core", "build"])
            self.assertEqual(1, rc)
            run_mock.assert_not_called()

        self.fixture(build_command="swift build --package-path Packages/Core")
        self.write(
            "Packages/Core/CONTEXT.md",
            """layer: Core
paths: [Packages/Core]
test_paths: [Packages/Core/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/Core
test: swift test --package-path Packages/Core
""",
        )
        with mock.patch("layer_coverage.subprocess.run", return_value=mock.Mock(returncode=0)) as run_mock:
            rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(0, rc)
        run_mock.assert_called_once_with(["swift", "build", "--package-path", "Packages/Core"], shell=False)

    def test_run_accepts_trusted_repo_commands(self):
        self.fixture(build_command="swift build --package-path Packages/AIService")
        with mock.patch("layer_coverage.subprocess.run", return_value=mock.Mock(returncode=0)) as run_mock:
            rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(0, rc)
        run_mock.assert_called_once_with(["swift", "build", "--package-path", "Packages/AIService"], shell=False)

        self.write(
            "CONTEXT.md",
            """scope: repo
routes:
  - paths: [Prototype]
    context: Prototype/CONTEXT.md
    kind: layer
support_excludes: [docs]""",
        )
        self.write(
            "Prototype/CONTEXT.md",
            """layer: Prototype
paths: [Prototype]
test_paths: []
gate_tier: local-fast
build: swift build --package-path Prototype
test: swift build --package-path Prototype
""",
        )
        with mock.patch("layer_coverage.subprocess.run", return_value=mock.Mock(returncode=0)) as run_mock:
            rc = layer_coverage.main(["run", "Prototype", "build"])
        self.assertEqual(0, rc)
        run_mock.assert_called_once_with(["swift", "build", "--package-path", "Prototype"], shell=False)

    def test_run_rejects_unapproved_swift_action_and_package_path(self):
        self.fixture(build_command="swift run --package-path Packages/AIService")
        with mock.patch("layer_coverage.subprocess.run") as run_mock:
            rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(1, rc)
        run_mock.assert_not_called()

        (self.root / "Packages" / "Arbitrary").mkdir(parents=True, exist_ok=True)
        self.fixture(build_command="swift build --package-path Packages/Arbitrary")
        with mock.patch("layer_coverage.subprocess.run") as run_mock:
            rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(1, rc)
        run_mock.assert_not_called()

    def test_run_emits_layered_failure_signal_on_nonzero_exit(self):
        self.fixture(build_command="swift build --package-path Packages/Core")
        with mock.patch("layer_coverage.subprocess.run", return_value=mock.Mock(returncode=7)) as run_mock:
            with contextlib.redirect_stdout(io.StringIO()) as stdout:
                rc = layer_coverage.main(["run", "Core", "build"])
        self.assertEqual(7, rc)
        run_mock.assert_called_once_with(["swift", "build", "--package-path", "Packages/Core"], shell=False)
        self.assertIn("::layered-signal::", stdout.getvalue())

    def test_run_rejects_unknown_xcodebuild_destination(self):
        self.write(
            "App/CONTEXT.md",
            """layer: AppUI
paths: [App]
test_paths: [AppTests]
gate_tier: ci-only
build: xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 99' -skipPackagePluginValidation
test: xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 99' -skipPackagePluginValidation
""",
        )
        with mock.patch("layer_coverage.subprocess.run") as run_mock:
            rc = layer_coverage.main(["run", "AppUI", "build"])
        self.assertEqual(1, rc)
        run_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
