#!/usr/bin/env python3
"""Launch the standard Codex CLI using the isolated review home configuration.

Keep CODEX_HOME, provider, model, tools and review policy separate from daily Codex.
Never load auth files, print credential values, edit configuration or retry.
"""
import os
from pathlib import Path
import sys
import tomllib


def _environment_value(environment, key):
    return environment[key] if key in environment else ""


def routing_arguments(environment):
    """Return optional Magpie/Raven routing overrides without changing defaults."""

    gateway = _environment_value(environment, "MAGPIE_BASE_URL") or _environment_value(
        environment, "RAVEN_BASE_URL"
    )
    logical_model = _environment_value(environment, "REVIEW_LOGICAL_MODEL")
    arguments = []
    if gateway:
        arguments.extend(
            [
                "-c",
                f"model={logical_model or 'group/reviewing'}",
                "-c",
                "model_provider=magpie",
                "-c",
                "model_providers.magpie.name=Magpie",
                "-c",
                f"model_providers.magpie.base_url={gateway}",
                "-c",
                "model_providers.magpie.wire_api=responses",
            ]
        )
    elif logical_model:
        arguments.extend(["-c", f"model={logical_model}"])
    return arguments


def extract_served_model(payload):
    """Extract the provider's served model attribution from a Codex response."""

    if isinstance(payload, dict):
        for key in ("served_model", "servedModel"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        for value in payload.values():
            result = extract_served_model(value)
            if result:
                return result
    elif isinstance(payload, list):
        for value in payload:
            result = extract_served_model(value)
            if result:
                return result
    return None


def extract_logical_model(payload):
    """Extract the logical model attribution from a Codex response."""

    if isinstance(payload, dict):
        for key in ("logical_model", "logicalModel"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        for value in payload.values():
            result = extract_logical_model(value)
            if result:
                return result
    elif isinstance(payload, list):
        for value in payload:
            result = extract_logical_model(value)
            if result:
                return result
    return None


def build_command(config_path, binary, arguments, environment=None):
    try:
        config = tomllib.loads(Path(config_path).read_text())
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise ValueError("Cannot read review home provider configuration") from None
    provider = config.get("model_provider")
    if not isinstance(provider, str) or not provider.strip():
        raise ValueError("Review home configuration must select a model provider")
    routing = routing_arguments({} if environment is None else environment)
    return [binary, "exec", *routing, *arguments]


def main():
    if len(sys.argv) < 2:
        print("[codex-review] expected Codex binary and exec arguments", file=sys.stderr)
        return 1
    review_home = os.environ.get("CODEX_HOME")
    if not review_home or not review_home.strip():
        print("[codex-review] Setup failed: CODEX_HOME environment variable is required", file=sys.stderr)
        return 1
    config = Path(review_home) / "config.toml"
    try:
        command = build_command(config, sys.argv[1], sys.argv[2:], os.environ)
        os.execvp(command[0], command)
    except (ValueError, OSError) as error:
        # Never print an OSError filename/argv or a TOML parser's source excerpt.
        detail = str(error) if isinstance(error, ValueError) else "Cannot start Codex executable"
        print(f"[codex-review] Setup failed: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
