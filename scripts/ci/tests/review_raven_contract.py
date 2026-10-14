#!/usr/bin/env python3
"""Offline tests: Provider-neutral review routing through isolated review home."""
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

CONFIG = '''model_provider = "custom-review-provider"
model = "review-model"
approval_policy = "never"
[features]
hooks = false
[model_providers.custom-review-provider]
name = "custom-review-provider"
base_url = "https://example.test/v1"
'''


class ReviewRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "config.toml"
        self.config.write_text(CONFIG)

    def command(self, env=None):
        return raven.build_command(
            self.config, "/opt/homebrew/bin/codex",
            ["--output-schema", "schema.json", "-o", "out.json", "synthetic prompt"],
            {} if env is None else env,
        )

    def test_arbitrary_provider_selected_in_review_home_is_accepted_without_cli_overrides(self):
        for provider_name in ("raven", "custom-provider", "openai", "claude", "deepseek-local"):
            with self.subTest(provider_name=provider_name):
                self.config.write_text(f'model_provider = "{provider_name}"\n')
                command = self.command()
                self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])
                self.assertEqual(command[-1], "synthetic prompt")
                # No -c model_provider=... or model_providers.* CLI overrides injected
                self.assertNotIn("-c", command)

    def test_missing_or_empty_provider_fails_closed(self):
        for bad_config in (
            "",
            'model = "gpt-4o"\n',
            'model_provider = ""\n',
            'model_provider = "   "\n',
            'model_provider = 123\n',
            'model_provider = true\n',
        ):
            with self.subTest(bad_config=bad_config):
                self.config.write_text(bad_config)
                with self.assertRaisesRegex(ValueError, "must select a model provider"):
                    self.command()

    def test_no_environment_credential_required_and_unrelated_ci_secrets_not_inspected(self):
        class MockNoCredentialReads(dict):
            def get(self, key, default=None):
                raise AssertionError("Environment credentials must not be inspected")

        # Command building succeeds with empty or mock env; no credential required
        command = self.command(MockNoCredentialReads())
        self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])

    def test_missing_or_malformed_config_is_sanitized(self):
        self.config.write_text('secret = "fixture-sensitive-invalid')
        with self.assertRaises(ValueError) as error:
            self.command()
        self.assertNotIn("fixture-sensitive", str(error.exception))
        self.config.unlink()
        with self.assertRaises(ValueError):
            self.command()

    def test_unreadable_config_fails_with_sanitized_diagnostic(self):
        self.config.write_text(CONFIG)
        self.config.chmod(0o000)
        try:
            with self.assertRaises(ValueError) as error:
                self.command()
            self.assertIn("Cannot read review home provider configuration", str(error.exception))
            self.assertNotIn(str(self.config), str(error.exception))
        finally:
            self.config.chmod(0o600)

    def test_helper_missing_codex_home_fails_closed_without_fallback(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text('#!' + sys.executable + '\nimport sys; sys.exit(0)\n')
        fake.chmod(0o700)
        # Even if CODEX_REVIEW_HOME or ~/.codex-review exists, helper must require CODEX_HOME
        default_home = Path(self.directory.name) / ".codex-review"
        default_home.mkdir(exist_ok=True)
        (default_home / "config.toml").write_text(CONFIG)
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_REVIEW_HOME=str(default_home))
        env.pop("CODEX_HOME", None)
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Setup failed: CODEX_HOME environment variable is required", result.stderr)

    def test_rejected_configuration_sources_are_mechanically_distinguishable(self):
        """Prove that malformed/provider-unselected/unreadable non-review sources fail closed if read,

        while valid $CODEX_HOME/config.toml successfully launches fake Codex.
        """
        fake = Path(self.directory.name) / "codex"
        fake.write_text(
            '#!' + sys.executable + '\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n'
        )
        fake.chmod(0o700)

        valid_home = Path(self.directory.name) / "valid_review_home"
        valid_home.mkdir(exist_ok=True)
        (valid_home / "config.toml").write_text('model_provider = "valid-review-provider"\n')

        # Rejected source 1: CODEX_RAVEN_CONFIG points to malformed/unselected TOML
        poison_file = Path(self.directory.name) / "poison_raven_config.toml"
        poison_file.write_text('malformed_syntax = [unclosed\n')

        # Rejected source 2: daily ~/.codex/config.toml is provider-unselected / bad TOML
        daily_home = Path(self.directory.name) / ".codex"
        daily_home.mkdir(exist_ok=True)
        (daily_home / "config.toml").write_text('malformed_daily = "no_provider"\n')

        # Rejected source 3: inherited daily home config is malformed
        inherited_home = Path(self.directory.name) / "inherited_daily_home"
        inherited_home.mkdir(exist_ok=True)
        (inherited_home / "config.toml").write_text('bad_inherited = invalid\n')

        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_HOME=str(valid_home),
                   CODEX_RAVEN_CONFIG=str(poison_file))

        # Real helper reaches fake Codex successfully because it only reads $CODEX_HOME/config.toml
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture prompt"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"][0], "exec")
        self.assertEqual(output["review_home"], str(valid_home))

        # Conversely, verify that if any of those rejected sources WAS read as config_path, build_command would fail
        with self.assertRaises(ValueError):
            raven.build_command(poison_file, str(fake), ["arg"])
        with self.assertRaises(ValueError):
            raven.build_command(daily_home / "config.toml", str(fake), ["arg"])
        with self.assertRaises(ValueError):
            raven.build_command(inherited_home / "config.toml", str(fake), ["arg"])

    def test_missing_codex_executable_fails_without_leaking_path_or_argv(self):
        valid_home = Path(self.directory.name) / "valid_review_home_exec"
        valid_home.mkdir(exist_ok=True)
        (valid_home / "config.toml").write_text('model_provider = "valid-provider"\n')

        secret_path = "/path/to/secret-private-codex-bin-does-not-exist"
        secret_prompt = "secret-sensitive-user-prompt-must-not-leak"
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_HOME=str(valid_home))
        result = subprocess.run([sys.executable, str(HELPER), secret_path, secret_prompt],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Setup failed: Cannot start Codex executable", result.stderr)
        self.assertNotIn("secret-private-codex", result.stderr + result.stdout)
        self.assertNotIn(secret_prompt, result.stderr + result.stdout)

    def test_real_launcher_preserves_exec_arguments_and_review_home(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text(
            '#!' + sys.executable + '\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n'
        )
        fake.chmod(0o700)
        review_home = Path(self.directory.name) / "isolated review"
        review_home.mkdir()
        (review_home / "config.toml").write_text('model_provider = "isolated-provider"\n')
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_HOME=str(review_home))
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture prompt"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"][0], "exec")
        self.assertEqual(output["args"][-2:], ["--skip-git-repo-check", "fixture prompt"])
        self.assertEqual(output["review_home"], str(review_home))

    def test_caller_keeps_isolation_and_uses_review_launcher(self):
        source = (CI / "codex-review.sh").read_text()
        self.assertIn('python3 "$SCRIPT_DIR/review-raven.py" "$CODEX_BIN"', source)
        self.assertIn('CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"', source)
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)

    def test_argv_round_trip_keeps_metacharacters_as_data(self):
        marker = Path(self.directory.name) / "never-created"
        arguments = ["--output-schema", "schema with spaces.json", "-o", "out.json",
                     f"prompt 'quoted' $(touch {marker}) `touch {marker}`\n中文"]
        command = raven.build_command(self.config, "/fake codex", arguments)
        self.assertEqual(command[0], "/fake codex")
        self.assertEqual(command[-len(arguments):], arguments)
        self.assertFalse(marker.exists())

    def run_actual_caller(self, *, override=False, missing_config=False, bad_verdict=False,
                          empty_output=False, blockers=False, cli_failure=False, hang=False):
        """Run the real shell, renderer, provider helper and watchdog; fake only external tools."""
        root = Path(self.directory.name)
        bin_dir = root / "bin"
        bin_dir.mkdir(exist_ok=True)

        # Daily ~/.codex must NOT be authority; seed with malformed/unselected config + distinct auth sentinel
        daily = root / ".codex"
        daily.mkdir(exist_ok=True)
        daily_config_content = 'model_provider = "daily-must-not-be-used"\n'
        daily_auth_content = '{"api_key":"daily-auth-sentinel-must-not-mutate"}\n'
        (daily / "config.toml").write_text(daily_config_content)
        (daily / "auth.json").write_text(daily_auth_content)

        # Inherited CODEX_HOME must NOT be authority; seed with distinct config + distinct auth sentinel
        inherited = root / "inherited daily home"
        inherited.mkdir(exist_ok=True)
        inherited_config_content = 'model_provider = "inherited-must-not-be-used"\n'
        inherited_auth_content = '{"api_key":"inherited-auth-sentinel-must-not-mutate"}\n'
        (inherited / "config.toml").write_text(inherited_config_content)
        (inherited / "auth.json").write_text(inherited_auth_content)

        # Default review home ~/.codex-review; seed with distinct config + distinct auth sentinel
        default_review = root / ".codex-review"
        default_review.mkdir(exist_ok=True)
        default_config_content = 'model_provider = "default-review-provider"\n'
        default_auth_content = '{"api_key":"default-review-auth-sentinel-must-not-mutate"}\n'
        (default_review / "auth.json").write_text(default_auth_content)
        if not missing_config:
            (default_review / "config.toml").write_text(default_config_content)

        # Explicit review home if override; seed with distinct config + distinct auth sentinel
        explicit_review = root / "explicit review home"
        explicit_review.mkdir(exist_ok=True)
        explicit_config_content = 'model_provider = "explicit-review-provider"\n'
        explicit_auth_content = '{"api_key":"explicit-review-auth-sentinel-must-not-mutate"}\n'
        (explicit_review / "auth.json").write_text(explicit_auth_content)
        if override:
            (explicit_review / "config.toml").write_text(explicit_config_content)

        marker = root / "SHELL_MUST_NOT_RUN"
        payload = f"+ quoted 'text' $(touch {marker}) `touch {marker}` 中文"
        capture = root / "capture.json"
        fake = bin_dir / "codex fixture"

        verdict_obj = {
            "verdict": "changes" if blockers else "pass",
            "summary": "offline fixture",
            "blockers": [{"file": "VitalStride/App.swift", "line": 42, "why": "P0 bug", "severity": "P0"}] if blockers else [],
            "notes": []
        }
        if empty_output:
            verdict_str = ""
        elif bad_verdict:
            verdict_str = "malformed not json"
        else:
            verdict_str = json.dumps(verdict_obj)

        fake.write_text(
            "#!" + sys.executable + "\nimport json,os,sys,time\nfrom pathlib import Path\n"
            "args=sys.argv[1:]\n"
            "stage=os.environ.get('VS_GATE_STAGE_FILE')\n"
            "Path(os.environ['CAPTURE']).write_text(json.dumps({'args':args,"
            "'home':os.environ.get('CODEX_HOME'),"
            "'stage':Path(stage).read_text() if stage else None,"
            "'stdin':sys.stdin.read()}))\n"
            "if os.environ.get('FIXTURE_HANG'): time.sleep(60)\n"
            "if os.environ.get('FIXTURE_CLI_FAIL'): sys.exit(2)\n"
            f"Path(args[args.index('-o')+1]).write_text({repr(verdict_str)})\n"
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
            "HOME": str(root),
            "CODEX_HOME": str(inherited),  # Should be overridden by codex-review.sh
            "CODEX_BIN": str(fake),
            "PR_NUMBER": "1",
            "BASE_SHA": "fixture-base",
            "HEAD_SHA": "fixture-head",
            "BASE_REPO": "fixture/repository",
            "CAPTURE": str(capture),
            "FIXTURE_REPO": str(CI.parents[1]),
            "FIXTURE_DIFF": payload,
            "GATE_TIMEOUT_SECONDS": "1" if hang else "30",
            "REVIEW_CLI_TIMEOUT_SECONDS": "1" if hang else "30",
        }
        if override:
            env["CODEX_REVIEW_HOME"] = str(explicit_review)
        if hang:
            env["FIXTURE_HANG"] = "1"
        if cli_failure:
            env["FIXTURE_CLI_FAIL"] = "1"

        result = subprocess.run(
            ["bash", str(CI / "codex-review.sh")], cwd=CI.parents[1], env=env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
        )
        self.assertFalse(marker.exists())
        self.assertNotIn("auth-sentinel", result.stdout + result.stderr)

        # Assert exact non-mutation of all configs and auth cache sentinels across every caller path
        self.assertEqual((daily / "config.toml").read_text(), daily_config_content)
        self.assertEqual((daily / "auth.json").read_text(), daily_auth_content)
        self.assertEqual((inherited / "config.toml").read_text(), inherited_config_content)
        self.assertEqual((inherited / "auth.json").read_text(), inherited_auth_content)
        self.assertEqual((default_review / "auth.json").read_text(), default_auth_content)
        if not missing_config:
            self.assertEqual((default_review / "config.toml").read_text(), default_config_content)
        self.assertEqual((explicit_review / "auth.json").read_text(), explicit_auth_content)
        if override:
            self.assertEqual((explicit_review / "config.toml").read_text(), explicit_config_content)

        return result, capture, env, payload

    def test_actual_caller_defaults_to_independent_home_and_review_home_config(self):
        result, capture, env, payload = self.run_actual_caller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        recorded = json.loads(capture.read_text())
        self.assertEqual(recorded["home"], str(Path(env["HOME"]) / ".codex-review"))
        self.assertEqual(recorded["args"][0], "exec")
        self.assertIn(payload, recorded["args"][-1])
        self.assertIn("sandbox_mode=read-only", recorded["args"])
        self.assertIn("approval_policy=never", recorded["args"])
        self.assertNotIn("daily-must-not-be-used", " ".join(recorded["args"]))
        self.assertEqual(recorded["stdin"], "")
        if "VS_GATE_SUPERVISED" in (CI / "codex-review.sh").read_text():
            self.assertEqual(recorded["stage"], "codex-exec")

    def test_actual_caller_honors_explicit_review_home(self):
        result, capture, env, _ = self.run_actual_caller(override=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(capture.read_text())["home"], env["CODEX_REVIEW_HOME"])

    def test_actual_caller_without_env_credentials_succeeds(self):
        # Verified that caller has no RAVEN_API_KEY / OPENAI_API_KEY and succeeds
        result, capture, _, _ = self.run_actual_caller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(capture.exists())

    def test_actual_caller_missing_review_config_fails_closed(self):
        result, capture, _, _ = self.run_actual_caller(missing_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Setup failed", result.stderr)
        self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_zero_exit_empty_output_fails_closed(self):
        result, capture, _, _ = self.run_actual_caller(empty_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(capture.exists())
        self.assertIn("codex CLI 失败 (rc=0)", result.stdout)
        self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_cli_failure_fails_closed(self):
        result, capture, _, _ = self.run_actual_caller(cli_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(capture.exists())
        self.assertIn("codex CLI 失败", result.stdout)

    def test_actual_caller_malformed_verdict_fails_closed(self):
        result, capture, _, _ = self.run_actual_caller(bad_verdict=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(capture.exists())
        self.assertIn("无法解析 verdict", result.stdout)

    def test_actual_caller_blockers_verdict_fails_closed(self):
        result, capture, _, _ = self.run_actual_caller(blockers=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(capture.exists())
        self.assertIn("verdict=changes, blockers=1", result.stdout)

    def test_actual_caller_watchdog_still_bounds_exec(self):
        result, capture, _, _ = self.run_actual_caller(hang=True)
        self.assertTrue(capture.exists(), result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("codex-exec", result.stdout)


if __name__ == "__main__":
    unittest.main()
