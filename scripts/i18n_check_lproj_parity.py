#!/usr/bin/env python3
"""Check zh-Hans/en localization key parity and write a markdown report."""

from __future__ import annotations

import json
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = REPO_ROOT / "scripts" / "i18n_check_lproj_parity.report.md"
STRINGS_RE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"', re.MULTILINE)


def decode_strings_key(raw: str) -> str:
    return bytes(raw, "utf-8").decode("unicode_escape")


def parse_strings(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {decode_strings_key(match.group(1)) for match in STRINGS_RE.finditer(path.read_text(encoding="utf-8"))}


# NOTE: Previously this script created empty Localizable.strings stubs in every
# en.lproj/ directory when missing. That caused Xcode 26 to emit
#   "Localizable.xcstrings cannot co-exist with other .strings or .stringsdict
#    tables with the same name"
# because the empty .strings was indexed by xcodegen alongside the canonical
# Localizable.xcstrings (MY-882). We now treat Localizable.xcstrings as the
# sole source of truth and intentionally do NOT auto-create empty .strings
# stubs. If you genuinely want a legacy .strings file, create it explicitly.


def lproj_key_sets() -> tuple[set[str], set[str], list[str]]:
    zh_keys: set[str] = set()
    en_keys: set[str] = set()
    sources: list[str] = []
    for zh_path in sorted(REPO_ROOT.rglob("zh-Hans.lproj/Localizable.strings")):
        if ".git" in zh_path.parts:
            continue
        zh_keys |= parse_strings(zh_path)
        sources.append(str(zh_path.relative_to(REPO_ROOT)))
    for en_path in sorted(REPO_ROOT.rglob("en.lproj/Localizable.strings")):
        if ".git" in en_path.parts:
            continue
        en_keys |= parse_strings(en_path)
        sources.append(str(en_path.relative_to(REPO_ROOT)))
    return zh_keys, en_keys, sources


def xcstrings_key_sets() -> tuple[set[str], set[str], list[str]]:
    zh_keys: set[str] = set()
    en_keys: set[str] = set()
    sources: list[str] = []
    for path in sorted(REPO_ROOT.rglob("Localizable.xcstrings")):
        if ".git" in path.parts:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        sources.append(str(path.relative_to(REPO_ROOT)))
        for key, payload in data.get("strings", {}).items():
            localizations = payload.get("localizations", {}) if isinstance(payload, dict) else {}
            if "zh-Hans" in localizations:
                zh_keys.add(key)
            if "en" in localizations:
                en_keys.add(key)
    return zh_keys, en_keys, sources


def markdown_code(value: str) -> str:
    escaped = value.replace("`", r"\`")
    return f"`{escaped}`"


def write_report(
    zh_keys: set[str],
    en_keys: set[str],
    sources: list[str],
    created: list[Path],
) -> float:
    zh_only = sorted(zh_keys - en_keys)
    en_only = sorted(en_keys - zh_keys)
    coverage = (len(zh_keys & en_keys) / len(zh_keys) * 100.0) if zh_keys else 100.0

    lines = [
        "# Localization Parity Baseline",
        "",
        f"zh-Hans key count: {len(zh_keys)}",
        f"en key count: {len(en_keys)}",
        f"en coverage: {coverage:.1f}%",
        "",
    ]
    if sources:
        lines.append("## Sources")
        lines.append("")
        for source in sorted(set(sources)):
            lines.append(f"- `{source}`")
        lines.append("")
    if created:
        lines.append("## Created Empty en Localizable.strings")
        lines.append("")
        for path in created:
            lines.append(f"- `{path.relative_to(REPO_ROOT)}`")
        lines.append("")
    lines.append("## zh-Hans only")
    lines.append("")
    if zh_only:
        lines.extend(f"- {markdown_code(key)}" for key in zh_only)
    else:
        lines.append("None")
    lines.append("")
    lines.append("## en only")
    lines.append("")
    if en_only:
        lines.extend(f"- {markdown_code(key)}" for key in en_only)
    else:
        lines.append("None")
    REPORT_PATH.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return coverage


def main() -> int:
    created: list[Path] = []
    zh_lproj, en_lproj, lproj_sources = lproj_key_sets()
    zh_xc, en_xc, xc_sources = xcstrings_key_sets()
    zh_keys = zh_lproj | zh_xc
    en_keys = en_lproj | en_xc
    coverage = write_report(zh_keys, en_keys, lproj_sources + xc_sources, created)
    print(f"zh_hans_keys: {len(zh_keys)}")
    print(f"en_keys: {len(en_keys)}")
    print(f"en_coverage_pct: {coverage:.1f}")
    print(f"report: {REPORT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
