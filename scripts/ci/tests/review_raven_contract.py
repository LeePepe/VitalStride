#!/usr/bin/env python3
"""Offline tests: Raven routing without credentials, network or GitHub writes."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1]
HELPER = CI / "review-raven.py"
spec = importlib.util.spec_from_file_location("review_raven", HELPER)
raven = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raven)

CONFIG = '''model_provider = "raven"
model = "daily-model-must-not-leak"
approval_policy = "never"
[features]
hooks = true
[model_providers.raven]
name = "raven"
base_url = "http://localhost:7024/v1"
wire_api = "responses"
env_key = "RAVEN_API_KEY"
'''


class RavenRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "config.toml"
        self.config.write_text(CONFIG)

    def command(self, env=None):
        return raven.build_command(
            self.config, "/opt/homebrew/bin/codex",
            ["--output-schema", "schema.json", "-o", "out.json", "synthetic prompt"],
            {"RAVEN_API_KEY": "fixture-not-a-real-credential"} if env is None else env,
        )

    def test_imports_only_raven_connection_not_daily_model_or_capabilities(self):
        command = self.command()
        self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])
        text = " ".join(command)
        self.assertIn('model_provider="raven"', text)
        self.assertIn('base_url = "http://localhost:7024/v1"', text)
        self.assertIn('requires_openai_auth = false', text)
        self.assertIn('env_key = "RAVEN_API_KEY"', text)
        self.assertNotIn("fixture-not-a-real-credential", text)
        self.assertNotIn("daily-model", text)
        self.assertNotIn("hooks", text)
        self.assertEqual(command[-1], "synthetic prompt")

    def test_missing_environment_fails_before_codex_without_fallback(self):
        with self.assertRaisesRegex(ValueError, "RAVEN_API_KEY"):
            self.command({})

    def test_unrelated_ci_credentials_are_rejected_before_environment_lookup(self):
        class MockNoCredentialReads(dict):
            def get(self, key, default=None):
                raise AssertionError("Unrelated credential environment must not be inspected")

        for key in ("GH_TOKEN", "GITHUB_TOKEN", "ANTHROPIC_API_KEY", "AZURE_API_KEY"):
            with self.subTest(key=key):
                self.config.write_text(CONFIG.replace("RAVEN_API_KEY", key))
                with self.assertRaisesRegex(ValueError, "Unsupported Raven credential environment name"):
                    self.command(MockNoCredentialReads())

    def test_both_existing_raven_credential_names_remain_supported(self):
        for key in ("RAVEN_API_KEY", "OPENAI_API_KEY"):
            with self.subTest(key=key):
                self.config.write_text(CONFIG.replace("RAVEN_API_KEY", key))
                command = self.command({key: "fixture-not-a-real-credential"})
                self.assertIn(f'env_key = "{key}"', " ".join(command))
                self.assertNotIn("fixture-not-a-real-credential", " ".join(command))

    def test_missing_or_malformed_config_is_sanitized(self):
        self.config.write_text('secret = "fixture-sensitive-invalid')
        with self.assertRaises(ValueError) as error:
            self.command()
        self.assertNotIn("fixture-sensitive", str(error.exception))
        self.config.unlink()
        with self.assertRaises(ValueError):
            self.command()

    def test_wrong_provider_does_not_silently_use_openai(self):
        self.config.write_text(CONFIG.replace('model_provider = "raven"', 'model_provider = "openai"'))
        with self.assertRaises(ValueError):
            self.command()

    def test_remote_or_credential_bearing_endpoint_is_rejected(self):
        for endpoint in ("https://example.com/v1", "http://user:secret@localhost:7024/v1",
                         "http://localhost:7024/v1?key=secret", "http://localhost:7024/v1#secret"):
            with self.subTest(endpoint=endpoint):
                self.config.write_text(CONFIG.replace("http://localhost:7024/v1", endpoint))
                with self.assertRaises(ValueError) as error:
                    self.command()
                self.assertNotIn("secret", str(error.exception))

    def test_chatgpt_auth_or_nonresponses_provider_is_rejected(self):
        for config in (CONFIG + "requires_openai_auth = true\n",
                       CONFIG.replace('wire_api = "responses"', 'wire_api = "chat"')):
            self.config.write_text(config)
            with self.assertRaises(ValueError):
                self.command()

    def test_configuration_is_not_shell_evaluated(self):
        marker = Path(self.directory.name) / "must-not-exist"
        self.config.write_text(CONFIG.replace('name = "raven"', f'name = "$(touch {marker})"'))
        self.command()
        self.assertFalse(marker.exists())

    def test_real_launcher_preserves_exec_arguments_and_review_home(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text(
            '#!' + sys.executable + '\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n'
        )
        fake.chmod(0o700)
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_HOME=str(Path(self.directory.name) / "isolated review"),
                   CODEX_RAVEN_CONFIG=str(self.config), RAVEN_API_KEY="fixture")
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"][0], "exec")
        self.assertEqual(output["args"][-2:], ["--skip-git-repo-check", "fixture"])
        self.assertEqual(output["review_home"], env["CODEX_HOME"])

    def test_caller_keeps_isolation_and_uses_raven_launcher(self):
        source = (CI / "codex-review.sh").read_text()
        self.assertIn('python3 "$SCRIPT_DIR/review-raven.py" "$CODEX_BIN"', source)
        self.assertIn('CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"', source)
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)



    def test_argv_round_trip_keeps_metacharacters_as_data(self):
        import tomllib
        marker = Path(self.directory.name) / "never-created"
        endpoint = f"http://localhost:7024/v1/$(touch {marker})"
        self.config.write_text(CONFIG.replace("http://localhost:7024/v1", endpoint))
        arguments = ["--output-schema", "schema with spaces.json", "-o", "out.json",
                     f"prompt 'quoted' $(touch {marker}) `touch {marker}`\n中文"]
        command = raven.build_command(self.config, "/fake codex", arguments,
                                      {"RAVEN_API_KEY": "fixture-secret"})
        self.assertEqual(command[0], "/fake codex")
        self.assertEqual(command[-len(arguments):], arguments)
        provider = tomllib.loads(command[5])["model_providers"]["raven"]
        self.assertEqual(provider["base_url"], endpoint)
        self.assertFalse(marker.exists())

    def run_actual_caller(self, *, override=False, credential=True, unsafe=False, hang=False):
        """Run the real shell, renderer, provider helper and watchdog; fake only external tools."""
        root = Path(self.directory.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        daily = root / ".codex"
        daily.mkdir()
        config = CONFIG.replace("http://localhost:7024/v1", "https://example.invalid/v1") if unsafe else CONFIG
        (daily / "config.toml").write_text(config)
        # An auth cache is deliberately present, but cannot substitute for the environment.
        (daily / "auth.json").write_text('{"api_key":"auth-file-must-not-be-used"}')
        inherited = root / "inherited daily home"
        inherited.mkdir()
        (inherited / "config.toml").write_text('model_provider = "must-not-be-used"')
        marker = root / "SHELL_MUST_NOT_RUN"
        payload = f"+ quoted 'text' $(touch {marker}) `touch {marker}` 中文"
        capture = root / "capture.json"
        fake = bin_dir / "codex fixture"
        fake.write_text(
            "#!" + sys.executable + "\nimport json,os,sys,time\nfrom pathlib import Path\n"
            "args=sys.argv[1:]\n"
            "stage=os.environ.get('VS_GATE_STAGE_FILE')\n"
            "Path(os.environ['CAPTURE']).write_text(json.dumps({'args':args,"
            "'home':os.environ.get('CODEX_HOME'),"
            "'stage':Path(stage).read_text() if stage else None,"
            "'stdin':sys.stdin.read()}))\n"
            "if os.environ.get('FIXTURE_HANG'): time.sleep(60)\n"
            "Path(args[args.index('-o')+1]).write_text(json.dumps("
            "{'verdict':'pass','summary':'offline fixture','blockers':[],'notes':[]}))\n"
        )
        (bin_dir / "git").write_text(
            "#!" + sys.executable + "\nimport os,sys\n"
            "cmd=sys.argv[1]\n"
            "if cmd=='rev-parse': print(os.environ['FIXTURE_REPO'])\n"
            "elif cmd=='diff': print('fixture.md' if '--name-only' in sys.argv else "
            "'diff --git a/fixture.md b/fixture.md\\n'+os.environ['FIXTURE_DIFF'])\n"
            "elif cmd not in ('fetch','cat-file'): sys.exit(1)\n"
        )
        (bin_dir / "gh").write_text("#!/bin/sh\nexit 0\n")
        for binary in (fake, bin_dir / "git", bin_dir / "gh"):
            binary.chmod(0o700)
        env = {
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "HOME": str(root), "CODEX_HOME": str(inherited), "CODEX_BIN": str(fake),
            "PR_NUMBER": "1", "BASE_SHA": "fixture-base", "HEAD_SHA": "fixture-head",
            "BASE_REPO": "fixture/repository", "CAPTURE": str(capture),
            "FIXTURE_REPO": str(CI.parents[1]), "FIXTURE_DIFF": payload,
            "GATE_TIMEOUT_SECONDS": "1" if hang else "30",
            "REVIEW_CLI_TIMEOUT_SECONDS": "1" if hang else "30",
        }
        if credential:
            env["RAVEN_API_KEY"] = "fixture-secret-never-print"
        if override:
            env["CODEX_REVIEW_HOME"] = str(root / "explicit review home")
        if hang:
            env["FIXTURE_HANG"] = "1"
        result = subprocess.run(
            ["bash", str(CI / "codex-review.sh")], cwd=CI.parents[1], env=env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
        )
        self.assertFalse(marker.exists())
        self.assertNotIn("fixture-secret-never-print", result.stdout + result.stderr)
        self.assertNotIn("auth-file-must-not-be-used", result.stdout + result.stderr)
        self.assertEqual((daily / "config.toml").read_text(), config)
        self.assertEqual((inherited / "config.toml").read_text(), 'model_provider = "must-not-be-used"')
        return result, capture, env, payload

    def test_actual_caller_defaults_to_independent_home_and_daily_provider_source(self):
        result, capture, env, payload = self.run_actual_caller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        recorded = json.loads(capture.read_text())
        self.assertEqual(recorded["home"], str(Path(env["HOME"]) / ".codex-review"))
        self.assertEqual(recorded["args"][0], "exec")
        self.assertIn('model_provider="raven"', recorded["args"])
        self.assertIn(payload, recorded["args"][-1])
        self.assertIn("sandbox_mode=read-only", recorded["args"])
        self.assertIn("approval_policy=never", recorded["args"])
        self.assertNotIn("daily-model", " ".join(recorded["args"]))
        self.assertEqual(recorded["stdin"], "")
        if "VS_GATE_SUPERVISED" in (CI / "codex-review.sh").read_text():
            self.assertEqual(recorded["stage"], "codex-exec")

    def test_actual_caller_honors_explicit_review_home(self):
        result, capture, env, _ = self.run_actual_caller(override=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(capture.read_text())["home"], env["CODEX_REVIEW_HOME"])

    def test_actual_caller_missing_environment_never_starts_codex_or_reads_auth_cache(self):
        result, capture, _, _ = self.run_actual_caller(credential=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)
        self.assertIn("RAVEN_API_KEY", result.stderr)
        self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_unsafe_endpoint_never_starts_codex(self):
        result, capture, _, _ = self.run_actual_caller(unsafe=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_watchdog_still_bounds_raven_exec(self):
        result, capture, _, _ = self.run_actual_caller(hang=True)
        self.assertTrue(capture.exists(), result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("超时" if (CI / "review-common.sh").exists() else "codex-exec",
                      result.stdout)

if __name__ == "__main__":
    unittest.main()
