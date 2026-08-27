import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
HOOK_PATH = ROOT / "scripts" / "hooks" / "pre-push"


class PrePushHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pre-push-hook-", dir="/tmp")
        self.root = pathlib.Path(self.temp.name)
        self.old_cwd = os.getcwd()
        self.old_env = os.environ.copy()
        for key in list(os.environ):
            if key.startswith("GIT_"):
                os.environ.pop(key, None)
        os.chdir(self.root)
        subprocess.run(["git", "init"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["git", "config", "user.name", "Tester"], check=True)
        subprocess.run(["git", "config", "user.email", "tester@example.com"], check=True)

        (self.root / "scripts" / "lib").mkdir(parents=True)
        (self.root / "scripts" / "hooks").mkdir(parents=True)
        (self.root / "scripts" / "tests").mkdir(parents=True)

        self.layer_coverage = self.root / "scripts" / "lib" / "layer_coverage.py"
        self.layer_coverage.write_text(
            (
                "import argparse\n"
                "import pathlib\n"
                "import sys\n\n"
                "def _layers_for(paths):\n"
                "    for path in paths:\n"
                "        if path.startswith('docs/'):\n"
                "            continue\n"
                "        if path.startswith('scripts/') or path.startswith('.github/'):\n"
                "            return ['RepoInfra']\n"
                "    return []\n\n"
                "def main(argv):\n"
                "    parser = argparse.ArgumentParser()\n"
                "    sub = parser.add_subparsers(dest='command', required=True)\n"
                "    layers = sub.add_parser('layers')\n"
                "    layers.add_argument('--stdin', action='store_true')\n"
                "    field = sub.add_parser('field')\n"
                "    field.add_argument('layer')\n"
                "    field.add_argument('field')\n"
                "    run = sub.add_parser('run')\n"
                "    run.add_argument('layer')\n"
                "    run.add_argument('action')\n"
                "    args = parser.parse_args(argv)\n"
                "    if args.command == 'layers':\n"
                "        paths = [line.strip() for line in sys.stdin if line.strip()]\n"
                "        for layer in _layers_for(paths):\n"
                "            print(layer)\n"
                "        return 0\n"
                "    if args.command == 'field':\n"
                "        if args.field == 'gate_tier':\n"
                "            print('local-fast')\n"
                "        return 0\n"
                "    if args.command == 'run':\n"
                "        out = pathlib.Path('.run-log')\n"
                "        existing = out.read_text() if out.exists() else ''\n"
                "        out.write_text(existing + f\"{args.layer}:{args.action}\\n\")\n"
                "        return 0\n"
                "    return 0\n\n"
                "if __name__ == '__main__':\n"
                "    raise SystemExit(main(sys.argv[1:]))\n"
            ) + "\n",
            encoding="utf-8",
        )

        hook_target = self.root / "scripts" / "hooks" / "pre-push"
        shutil.copy2(HOOK_PATH, hook_target)
        hook_target.chmod(0o755)

        self.check_frontmatter = self.root / "scripts" / "check-frontmatter.sh"
        self.check_frontmatter.write_text(
            "#!/bin/bash\n"
            "echo frontmatter-ran > frontmatter-ran.txt\n"
            "exit 0\n",
            encoding="utf-8",
        )
        self.check_frontmatter.chmod(0o755)

        (self.root / "scripts" / "test-repoinfra.sh").write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        (self.root / "scripts" / "test-repoinfra.sh").chmod(0o755)

        (self.root / "README.md").write_text("base\n", encoding="utf-8")
        subprocess.run(["git", "add", "README.md"], check=True, cwd=self.root, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-m", "base"], check=True, cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def tearDown(self):
        os.chdir(self.old_cwd)
        os.environ.clear()
        os.environ.update(self.old_env)
        self.temp.cleanup()

    def _commit(self, relpath: str, content: str):
        path = self.root / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "add", relpath], check=True, cwd=self.root, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-m", f"add {relpath}"], check=True, cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_support_only_push_runs_frontmatter_before_exit(self):
        self._commit("docs/plan.md", "# plan\n")
        self._commit("CONTEXT.md", "scope: repo\n")
        proc = subprocess.run(
            [
                "bash",
                "scripts/hooks/pre-push",
                "origin",
                "git@github.com:example/repo.git",
            ],
            cwd=self.root,
            input=(
                f"refs/heads/feature {subprocess.check_output(['git','rev-parse','HEAD'], cwd=self.root, text=True).strip()} "
                "refs/heads/main 0000000000000000000000000000000000000000\n"
            ),
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertTrue((self.root / "frontmatter-ran.txt").exists())

    def test_repoinfra_push_validates_once(self):
        self._commit("scripts/ci/check.sh", "#!/bin/bash\nexit 0\n")
        self._commit("CONTEXT.md", "scope: repo\n")
        proc = subprocess.run(
            [
                "bash",
                "scripts/hooks/pre-push",
                "origin",
                "git@github.com:example/repo.git",
            ],
            cwd=self.root,
            input=(
                f"refs/heads/feature {subprocess.check_output(['git','rev-parse','HEAD'], cwd=self.root, text=True).strip()} "
                "refs/heads/main 0000000000000000000000000000000000000000\n"
            ),
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertFalse((self.root / "frontmatter-ran.txt").exists())
        self.assertEqual(["RepoInfra:build\n", "RepoInfra:test\n"], (self.root / ".run-log").read_text(encoding="utf-8").splitlines(True))


if __name__ == "__main__":
    unittest.main()
