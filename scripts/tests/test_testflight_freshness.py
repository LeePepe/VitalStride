"""Guard TestFlight's manual-only entry point and in-run profile reuse without building or uploading."""
from pathlib import Path
import re
import shlex
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"
FASTFILE = ROOT / "fastlane/Fastfile"
PROJECT_YML = ROOT / "project.yml"


class TestFlightManualOnlyTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]

    def test_only_explicit_manual_dispatch_is_registered(self):
        events = re.findall(r"^  ([a-z_]+):", self.triggers, re.M)
        self.assertEqual(events, ["workflow_dispatch"])

    def test_release_rejects_non_manual_events(self):
        guards = re.findall(r"^    if: (.+)$", self.release, re.M)
        self.assertEqual(guards, ["github.event_name == 'workflow_dispatch'"])
        self.assertNotIn("needs: freshness", self.release)
        self.assertNotIn("  freshness:", self.workflow)

    def test_manual_force_and_no_new_commit_gate_are_preserved(self):
        force = self.triggers.split("      force:\n", 1)[1]
        self.assertIn("        type: boolean", force)
        self.assertIn("        default: false", force)
        self.assertIn('if [ "$FORCE" = "true" ] || [ "$LATEST" != "$RELEASED" ]; then', self.release)
        self.assertIn("steps.gate.outputs.release == 'true'", self.release)

    def test_release_still_uses_main_without_interrupting_uploads(self):
        self.assertIn("          ref: main", self.release)
        self.assertRegex(self.workflow, r"(?m)^  cancel-in-progress: false(?: |$)")


class TestFlightProfileHandoffTests(unittest.TestCase):
    def setUp(self):
        self.fastfile = FASTFILE.read_text(encoding="utf-8")
        self.project_yml = PROJECT_YML.read_text(encoding="utf-8")

    def test_both_targets_fetch_forced_appstore_profiles_with_installation(self):
        app_fetch = re.search(
            r"get_provisioning_profile\s*\(\s*[^)]*app_identifier:\s*APP_IDENTIFIER[^)]*\)",
            self.fastfile,
            re.S
        )
        self.assertIsNotNone(app_fetch, "App provisioning profile fetch not found in Fastfile")
        self.assertIn("force: true", app_fetch.group(0))
        self.assertIn("skip_install: false", app_fetch.group(0))

        widget_fetch = re.search(
            r"get_provisioning_profile\s*\(\s*[^)]*app_identifier:\s*WIDGET_IDENTIFIER[^)]*\)",
            self.fastfile,
            re.S
        )
        self.assertIsNotNone(widget_fetch, "Widget provisioning profile fetch not found in Fastfile")
        self.assertIn("force: true", widget_fetch.group(0))
        self.assertIn("skip_install: false", widget_fetch.group(0))

    def test_canonical_profile_names_resolved_and_fail_closed_before_build_app(self):
        # Exact assignment assertions
        self.assertRegex(
            self.fastfile,
            r'app_profile_name\s*=\s*ENV\["sigh_#\{APP_IDENTIFIER\}_appstore_profile-name"\]',
            "app_profile_name is not assigned from exact canonical app environment variable"
        )
        self.assertRegex(
            self.fastfile,
            r'widget_profile_name\s*=\s*ENV\["sigh_#\{WIDGET_IDENTIFIER\}_appstore_profile-name"\]',
            "widget_profile_name is not assigned from exact canonical widget environment variable"
        )

        # Absence of action return fallback
        self.assertNotRegex(
            self.fastfile,
            r'ENV\.fetch\(\s*["\']sigh_#\{APP_IDENTIFIER\}_appstore_profile-name["\']\s*,\s*app_profile\s*\)',
            "Fastfile still uses action return fallback for app profile"
        )
        self.assertNotRegex(
            self.fastfile,
            r'ENV\.fetch\(\s*["\']sigh_#\{WIDGET_IDENTIFIER\}_appstore_profile-name["\']\s*,\s*widget_profile\s*\)',
            "Fastfile still uses action return fallback for widget profile"
        )

        build_app_idx = self.fastfile.find("build_app(")
        self.assertNotEqual(build_app_idx, -1, "build_app call not found in Fastfile")
        pre_build_app = self.fastfile[:build_app_idx]

        # Fatal error branches before build_app
        self.assertRegex(
            pre_build_app,
            r'if\s+app_profile_name\.(?:nil\?|strip\.empty\?|empty\?)\s*\|\|\s*app_profile_name\.(?:nil\?|strip\.empty\?|empty\?)\s*\n\s*UI\.user_error!\(',
            "Missing fatal UI.user_error! for missing/empty app profile before build_app"
        )
        self.assertRegex(
            pre_build_app,
            r'if\s+widget_profile_name\.(?:nil\?|strip\.empty\?|empty\?)\s*\|\|\s*widget_profile_name\.(?:nil\?|strip\.empty\?|empty\?)\s*\n\s*UI\.user_error!\(',
            "Missing fatal UI.user_error! for missing/empty widget profile before build_app"
        )
        self.assertRegex(
            pre_build_app,
            r'if\s+app_profile_name\s*==\s*widget_profile_name\s*\n\s*UI\.user_error!\(',
            "Missing fatal UI.user_error! for equal profile names before build_app"
        )

        # Failure messages must not interpolate or leak resolved profile values
        self.assertNotRegex(
            pre_build_app,
            r'UI\.user_error!\([^)]*#\{app_profile_name\}',
            "Profile failure message interpolates and leaks resolved app profile name"
        )
        self.assertNotRegex(
            pre_build_app,
            r'UI\.user_error!\([^)]*#\{widget_profile_name\}',
            "Profile failure message interpolates and leaks resolved widget profile name"
        )

    def test_archive_transports_target_specific_keys_shell_safely(self):
        # Target-scoped xcargs bindings
        self.assertRegex(
            self.fastfile,
            r'VITALSTRIDE_APP_PROFILE_SPECIFIER=#\{Shellwords\.escape\(app_profile_name\)\}',
            "VITALSTRIDE_APP_PROFILE_SPECIFIER is not bound to Shellwords.escape(app_profile_name)"
        )
        self.assertRegex(
            self.fastfile,
            r'VITALSTRIDE_WIDGET_PROFILE_SPECIFIER=#\{Shellwords\.escape\(widget_profile_name\)\}',
            "VITALSTRIDE_WIDGET_PROFILE_SPECIFIER is not bound to Shellwords.escape(widget_profile_name)"
        )

        xcargs_match = re.search(r"xcargs:\s*(.+?)(?=\n\s*[a-z_]+:|\n\s*\))", self.fastfile, re.S)
        self.assertIsNotNone(xcargs_match, "xcargs parameter not found in Fastfile")
        if xcargs_match:
            self.assertNotRegex(
                xcargs_match.group(1),
                r'(?<![A-Z0-9_])PROVISIONING_PROFILE_SPECIFIER=',
                "Found forbidden global PROVISIONING_PROFILE_SPECIFIER override in xcargs"
            )

    def test_export_options_reuses_exact_resolved_profile_variables(self):
        export_match = re.search(
            r"export_options:\s*\{[^}]*provisioningProfiles:\s*\{([^}]+)\}",
            self.fastfile,
            re.S
        )
        self.assertIsNotNone(export_match, "export_options provisioningProfiles not found in Fastfile")
        prov_profiles = export_match.group(1)
        self.assertRegex(
            prov_profiles,
            r'APP_IDENTIFIER\s*=>\s*app_profile_name',
            "export_options must directly reuse app_profile_name"
        )
        self.assertRegex(
            prov_profiles,
            r'WIDGET_IDENTIFIER\s*=>\s*widget_profile_name',
            "export_options must directly reuse widget_profile_name"
        )

    def test_project_yml_signing_configuration_and_dynamic_specifiers(self):
        # Verify base settings retain Automatic signing
        base_settings = self.project_yml.split("settings:\n  base:\n", 1)[1].split("packages:\n", 1)[0]
        self.assertIn("CODE_SIGN_STYLE: Automatic", base_settings)

        # Extract target sections
        targets = self.project_yml.split("targets:\n", 1)[1]
        app_target = targets.split("VitalStride:\n", 1)[1].split("\n  VitalStrideMac:\n", 1)[0]
        widget_target = targets.split("VitalStrideWidgets:\n", 1)[1].split("\n  VitalStrideWatchTests:\n", 1)[0]

        # Verify App Target Release configuration
        app_release = app_target.split("Release:\n", 1)[1].split("base:\n", 1)[0]
        self.assertIn("CODE_SIGN_STYLE: Manual", app_release)
        self.assertIn("CODE_SIGN_IDENTITY: Apple Distribution", app_release)
        self.assertIn('PROVISIONING_PROFILE_SPECIFIER: "$(VITALSTRIDE_APP_PROFILE_SPECIFIER)"', app_release)
        self.assertNotIn("VITALSTRIDE_WIDGET_PROFILE_SPECIFIER", app_release)
        self.assertNotIn("com.leepepe.vitalstride AppStore", app_release)

        # Verify Widget Target Release configuration
        widget_release = widget_target.split("Release:\n", 1)[1].split("base:\n", 1)[0]
        self.assertIn("CODE_SIGN_STYLE: Manual", widget_release)
        self.assertIn("CODE_SIGN_IDENTITY: Apple Distribution", widget_release)
        self.assertIn('PROVISIONING_PROFILE_SPECIFIER: "$(VITALSTRIDE_WIDGET_PROFILE_SPECIFIER)"', widget_release)
        self.assertNotIn("VITALSTRIDE_APP_PROFILE_SPECIFIER", widget_release)
        self.assertNotIn("com.leepepe.vitalstride.widgets AppStore", widget_release)

    def test_opaque_names_with_whitespace_and_shell_metacharacters(self):
        opaque_app = "Match AppStore com.leepepe.vitalstride (2026-10-13) $`'\"\\!"
        opaque_widget = 'Match AppStore com.leepepe.vitalstride.widgets (2026-10-13) $`\'"\\!'

        escaped_app = shlex.quote(opaque_app)
        escaped_widget = shlex.quote(opaque_widget)

        simulated_xcargs = (
            f"VITALSTRIDE_APP_PROFILE_SPECIFIER={escaped_app} "
            f"VITALSTRIDE_WIDGET_PROFILE_SPECIFIER={escaped_widget}"
        )

        parsed_tokens = shlex.split(simulated_xcargs)
        self.assertEqual(len(parsed_tokens), 2)
        self.assertEqual(parsed_tokens[0], f"VITALSTRIDE_APP_PROFILE_SPECIFIER={opaque_app}")
        self.assertEqual(parsed_tokens[1], f"VITALSTRIDE_WIDGET_PROFILE_SPECIFIER={opaque_widget}")


if __name__ == "__main__":
    unittest.main()
