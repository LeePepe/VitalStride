#!/usr/bin/env python3
"""Validate exhaustive, non-overlapping formal-layer path ownership."""

from __future__ import annotations

import argparse
import fnmatch
import subprocess
import sys
from pathlib import PurePosixPath

from frontmatter import parse_list, parse_scalar, read_frontmatter


def matches(path: str, pattern: str) -> bool:
    """Match an exact path, directory root, or explicit glob pattern."""
    if any(char in pattern for char in "*?["):
        return fnmatch.fnmatchcase(path, pattern) or PurePosixPath(path).match(pattern)
    return path == pattern or path.startswith(pattern.rstrip("/") + "/")


def classify(files: list[str], contexts: list[str]) -> list[str]:
    owners: list[tuple[str, str]] = []
    support_excludes: list[str] = []
    generated_excludes: list[str] = []
    errors: list[str] = []

    for context in contexts:
        fm = read_frontmatter(context)
        if fm is None:
            errors.append(f"{context}: missing frontmatter")
            continue
        layer = parse_scalar(fm, "layer")
        paths = parse_list(fm, "paths")
        if not paths and context.startswith("Packages/"):
            paths = [context.split("/", 2)[0] + "/" + context.split("/", 2)[1]]
        for path in paths:
            owners.append((layer, path))
        support_excludes.extend(parse_list(fm, "support_excludes"))
        generated_excludes.extend(parse_list(fm, "generated_excludes"))

    for path in files:
        exclusions = [
            pattern
            for pattern in support_excludes + generated_excludes
            if matches(path, pattern)
        ]
        matched_owners = sorted({layer for layer, pattern in owners if matches(path, pattern)})
        if exclusions:
            # Exclusions carve support/generated files out of otherwise owned
            # directory roots (for example Packages/X/CONTEXT.md). They are
            # classified as exclusions, never as layer content.
            continue
        if not matched_owners:
            errors.append(f"unmapped tracked path: {path}")
        elif len(matched_owners) > 1:
            errors.append(f"owner overlap: {path} -> {matched_owners}")
    return errors


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"], check=True, stdout=subprocess.PIPE
    )
    return [item.decode() for item in result.stdout.split(b"\0") if item]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("contexts", nargs="+")
    parser.add_argument("--files-from", help="newline-delimited fixture paths")
    args = parser.parse_args(argv)
    if args.files_from:
        with open(args.files_from, encoding="utf-8") as handle:
            files = [line.strip() for line in handle if line.strip()]
    else:
        files = tracked_files()
    errors = classify(files, args.contexts)
    if errors:
        print("\n".join(f"❌ {error}" for error in errors))
        return 1
    print(f"✅ layer path coverage: {len(files)} tracked paths classified")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
