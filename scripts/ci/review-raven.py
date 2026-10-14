#!/usr/bin/env python3
"""Launch the standard Codex CLI using the isolated review home configuration.

Keep CODEX_HOME, provider, model, tools and review policy separate from daily Codex.
Never load auth files, print credential values, edit configuration or retry.
"""
import os
from pathlib import Path
import sys
import tomllib


def build_command(config_path, binary, arguments, environment=None):
    try:
        config = tomllib.loads(Path(config_path).read_text())
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise ValueError("Cannot read review home provider configuration") from None
    provider = config.get("model_provider")
    if not isinstance(provider, str) or not provider.strip():
        raise ValueError("Review home configuration must select a model provider")
    return [binary, "exec", *arguments]


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
