#!/usr/bin/env python3
"""Report hardcoded Chinese Swift string literals that still need i18n work."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = REPO_ROOT / "scripts" / "i18n_extract_hardcoded.report.md"
CHINESE_RE = re.compile(r"[\u4e00-\u9fff]")

SCAN_ROOTS = [
    REPO_ROOT / "VitalStride",
    REPO_ROOT / "VitalStrideMac",
    REPO_ROOT / "VitalStrideWatch",
    REPO_ROOT / "VitalStrideWatch Watch App",
]

PHRASE_TOKENS = {
    "AI": "ai",
    "Apple": "apple",
    "API": "api",
    "Azure": "azure",
    "HealthKit": "healthkit",
    "kg": "kg",
    "km": "km",
    "OAuth": "oauth",
    "URL": "url",
    "一周": "week",
    "一天": "day",
    "上肢": "upper_body",
    "下肢": "lower_body",
    "不可用": "unavailable",
    "中等": "medium",
    "主动": "active",
    "今日": "today",
    "休息": "rest",
    "保存": "save",
    "删除": "delete",
    "取消": "cancel",
    "名称": "name",
    "启动": "start",
    "周": "week",
    "完成": "done",
    "心率": "heart_rate",
    "恢复": "recovery",
    "成功": "success",
    "手臂": "arms",
    "数据": "data",
    "无": "none",
    "时间": "time",
    "日期": "date",
    "显示": "display",
    "更新": "update",
    "月": "month",
    "有氧": "cardio",
    "次数": "reps",
    "步": "steps",
    "测试": "test",
    "添加": "add",
    "清空": "clear",
    "编辑": "edit",
    "训练": "training",
    "记录": "record",
    "设置": "settings",
    "详情": "detail",
    "身体": "body",
    "运动": "workout",
    "连接": "connection",
    "选择": "select",
    "重量": "weight",
    "错误": "error",
    "阅读": "read",
    "隐藏": "hide",
    "高": "high",
}

CHAR_INITIALS = {
    "万": "w", "上": "s", "下": "x", "不": "b", "中": "z", "为": "w", "主": "z",
    "了": "l", "事": "s", "二": "e", "于": "y", "云": "y", "些": "x", "今": "j",
    "从": "c", "代": "d", "休": "x", "优": "y", "会": "h", "低": "d", "体": "t",
    "保": "b", "信": "x", "修": "x", "值": "z", "健": "j", "停": "t", "储": "c",
    "像": "x", "允": "y", "元": "y", "先": "x", "全": "q", "关": "g", "其": "q",
    "内": "n", "准": "z", "分": "f", "切": "q", "列": "l", "删": "s", "到": "d",
    "创": "c", "别": "b", "前": "q", "力": "l", "功": "g", "加": "j", "动": "d",
    "包": "b", "化": "h", "匹": "p", "区": "q", "单": "d", "卡": "k", "历": "l",
    "去": "q", "参": "c", "双": "s", "反": "f", "发": "f", "取": "q", "变": "b",
    "另": "l", "只": "z", "可": "k", "台": "t", "名": "m", "启": "q", "告": "g",
    "周": "z", "和": "h", "咳": "k", "哈": "h", "响": "x", "器": "q", "四": "s",
    "回": "h", "因": "y", "围": "w", "固": "g", "图": "t", "在": "z", "地": "d",
    "型": "x", "增": "z", "处": "c", "备": "b", "复": "f", "外": "w", "多": "d",
    "大": "d", "天": "t", "失": "s", "好": "h", "始": "s", "存": "c", "字": "z",
    "完": "w", "定": "d", "实": "s", "客": "k", "容": "r", "密": "m", "对": "d",
    "导": "d", "将": "j", "小": "x", "少": "s", "尚": "s", "屏": "p", "已": "y",
    "布": "b", "常": "c", "年": "n", "并": "b", "应": "y", "开": "k", "式": "s",
    "引": "y", "张": "z", "强": "q", "当": "d", "录": "l", "形": "x", "很": "h",
    "得": "d", "微": "w", "心": "x", "必": "b", "态": "t", "性": "x", "总": "z",
    "息": "x", "恢": "h", "您": "n", "成": "c", "我": "w", "或": "h", "截": "j",
    "所": "s", "手": "s", "打": "d", "扫": "s", "批": "p", "找": "z", "报": "b",
    "择": "z", "持": "c", "指": "z", "按": "a", "换": "h", "授": "s", "排": "p",
    "接": "j", "提": "t", "搜": "s", "播": "b", "操": "c", "支": "z", "收": "s",
    "改": "g", "效": "x", "数": "s", "整": "z", "文": "w", "新": "x", "方": "f",
    "无": "w", "日": "r", "时": "s", "明": "m", "显": "x", "暂": "z", "更": "g",
    "最": "z", "月": "y", "有": "y", "未": "w", "本": "b", "来": "l", "板": "b",
    "标": "b", "格": "g", "检": "j", "模": "m", "次": "c", "欢": "h", "正": "z",
    "步": "b", "止": "z", "每": "m", "比": "b", "毫": "h", "没": "m", "法": "f",
    "活": "h", "消": "x", "添": "t", "清": "q", "源": "y", "点": "d", "热": "r",
    "然": "r", "片": "p", "版": "b", "状": "z", "率": "l", "现": "x", "用": "y",
    "由": "y", "登": "d", "的": "d", "目": "m", "看": "k", "知": "z", "码": "m",
    "确": "q", "示": "s", "秒": "m", "移": "y", "空": "k", "窗": "c", "立": "l",
    "等": "d", "签": "q", "简": "j", "类": "l", "精": "j", "系": "x", "索": "s",
    "线": "x", "组": "z", "细": "x", "练": "l", "络": "l", "置": "z", "美": "m",
    "者": "z", "耗": "h", "联": "l", "肌": "j", "背": "b", "能": "n", "腿": "t",
    "自": "z", "至": "z", "获": "h", "菜": "c", "藏": "c", "行": "x", "表": "b",
    "要": "y", "览": "l", "规": "g", "视": "s", "解": "j", "计": "j", "认": "r",
    "记": "j", "设": "s", "话": "h", "详": "x", "误": "w", "请": "q", "读": "d",
    "调": "t", "负": "f", "账": "z", "败": "b", "起": "q", "距": "j", "身": "s",
    "输": "s", "运": "y", "近": "j", "连": "l", "选": "x", "通": "t", "速": "s",
    "量": "l", "钟": "z", "错": "c", "键": "j", "长": "c", "闭": "b", "问": "w",
    "间": "j", "阅": "y", "隐": "y", "集": "j", "需": "x", "面": "m", "音": "y",
    "项": "x", "页": "y", "频": "p", "高": "g",
}


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    text: str
    key: str


def is_test_path(path: Path) -> bool:
    parts = set(path.parts)
    return "Tests" in parts or path.name.endswith("Tests.swift") or "VitalStrideTests" in parts


# File-level exemption marker. A file containing a line starting with
# `// i18n:exempt` in its first 40 lines is fully skipped by this scanner.
# Intended for non-UI text such as AI prompt templates that are sent to
# language models rather than rendered to end users (Constitution §VI-G notes
# that only user-visible strings are P1; AI prompts are explicitly exempt per
# MY-1269 acceptance criteria).
I18N_EXEMPT_MARKER = "// i18n:exempt"


def is_file_exempt(path: Path) -> bool:
    try:
        with path.open("r", encoding="utf-8") as fh:
            for i, line in enumerate(fh):
                if i >= 40:
                    break
                if I18N_EXEMPT_MARKER in line:
                    return True
    except OSError:
        return False
    return False


def swift_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        if root.exists():
            files.extend(root.rglob("*.swift"))
    packages = REPO_ROOT / "Packages"
    if packages.exists():
        files.extend(packages.glob("*/Sources/**/*.swift"))
    return sorted({p for p in files if not is_test_path(p) and not is_file_exempt(p)})


def iter_string_literals(source: str):
    line = 1
    col = 1
    i = 0
    in_block_comment = False
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if ch == "\n":
            line += 1
            col = 1
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                col += 2
            else:
                i += 1
                col += 1
            continue
        if ch == "/" and nxt == "/":
            next_newline = source.find("\n", i)
            if next_newline == -1:
                break
            i = next_newline
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            col += 2
            continue
        if ch == '"':
            if source[i : i + 3] == '"""':
                i += 3
                col += 3
                continue
            start = i
            start_line = line
            start_col = col
            i += 1
            col += 1
            literal_chars: list[str] = []
            escaped = False
            while i < len(source):
                ch = source[i]
                if ch == "\n":
                    break
                if escaped:
                    literal_chars.append(ch)
                    escaped = False
                    i += 1
                    col += 1
                    continue
                if ch == "\\":
                    literal_chars.append(ch)
                    escaped = True
                    i += 1
                    col += 1
                    continue
                if ch == '"':
                    end = i + 1
                    yield start_line, start_col, start, end, "".join(literal_chars)
                    i += 1
                    col += 1
                    break
                literal_chars.append(ch)
                i += 1
                col += 1
            continue
        i += 1
        col += 1


def is_string_localized_first_argument(source: str, start: int) -> bool:
    prefix = source[max(0, start - 250) : start]
    # Strip line comments so `String(localized: // swiftlint:disable...\n "..."`
    # still matches.
    prefix_no_comments = re.sub(r"//[^\n]*", "", prefix)
    if re.search(r"String\s*\(\s*localized\s*:\s*$", prefix_no_comments, re.DOTALL) is not None:
        return True
    # Also skip literals used as `defaultValue:` argument of String(localized: "key", defaultValue: "...")
    # — this is the standard SwiftUI/Foundation i18n pattern for supplying a fallback string.
    if re.search(r"defaultValue\s*:\s*$", prefix_no_comments, re.DOTALL) is not None:
        return True
    return False


def is_swiftui_localized_key_with_comment(source: str, start: int, end: int) -> bool:
    """Return True when a literal is the first arg to a SwiftUI initializer that
    also passes an explicit `comment:` argument — the standard Apple i18n pattern
    for translator hints (e.g. `Text("训练", comment: "Tab title")`).

    We match the surrounding parenthesized call ending with `, comment: "..."`.
    """
    # Look at the ~250 chars before to see we're in an argument list
    prefix = source[max(0, start - 250) : start]
    # Must be immediately after `(` or `, ` — i.e. this is a positional first arg
    if not re.search(r"[(,]\s*$", prefix, re.DOTALL):
        return False
    # Look forward for `, comment:` before the enclosing `)` at same paren depth
    depth = 0
    i = end
    src_len = len(source)
    while i < src_len:
        ch = source[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            if depth == 0:
                return False
            depth -= 1
        elif ch == "," and depth == 0:
            # Check if the next non-whitespace token is `comment:`
            j = i + 1
            while j < src_len and source[j] in " \t\n":
                j += 1
            if source.startswith("comment:", j):
                return True
        elif ch == "\n" and depth == 0:
            # Multi-line arg list — allow, continue scanning
            pass
        i += 1
    return False


def is_debug_print_line(source: str, start: int, end: int) -> bool:
    line_start = source.rfind("\n", 0, start) + 1
    line_end = source.find("\n", end)
    if line_end == -1:
        line_end = len(source)
    line = source[line_start:line_end]
    return re.search(r"\b(?:print|debugPrint)\s*\(", line) is not None


def snake_case(value: str) -> str:
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").lower()
    return value


def phrase_to_tokens(text: str) -> list[str]:
    cleaned = re.sub(r"\\\([^)]*\)", " value ", text)
    tokens: list[str] = []
    i = 0
    phrases = sorted(PHRASE_TOKENS, key=len, reverse=True)
    while i < len(cleaned):
        if cleaned[i].isascii():
            match = re.match(r"[A-Za-z0-9]+", cleaned[i:])
            if match:
                tokens.append(match.group(0).lower())
                i += len(match.group(0))
                continue
        matched = False
        for phrase in phrases:
            if cleaned.startswith(phrase, i):
                tokens.extend(PHRASE_TOKENS[phrase].split("_"))
                i += len(phrase)
                matched = True
                break
        if matched:
            continue
        ch = cleaned[i]
        if CHINESE_RE.match(ch):
            tokens.append(CHAR_INITIALS.get(ch, f"u{ord(ch):x}"))
        i += 1
    return [t for t in tokens if t]


def suggested_key(path: Path, line_text: str, text: str) -> str:
    rel = path.relative_to(REPO_ROOT)
    if text == "数据":
        return "data_tab_title"
    tokens = phrase_to_tokens(text)
    if ".tabItem" in line_text:
        stem = snake_case(path.stem.replace("View", "")) or "app"
        return "_".join([stem, "tab", "title"])
    key = "_".join(tokens) if tokens else "localized_string"
    key = re.sub(r"_+", "_", key).strip("_")
    if not key or key.startswith("u"):
        digest = hashlib.sha1(f"{rel}:{text}".encode("utf-8")).hexdigest()[:8]
        key = f"localized_{digest}"
    return key[:80]


def collect_findings() -> list[Finding]:
    findings: list[Finding] = []
    for path in swift_files():
        source = path.read_text(encoding="utf-8")
        lines = source.splitlines()
        for line, _col, start, end, text in iter_string_literals(source):
            if not CHINESE_RE.search(text):
                continue
            if is_debug_print_line(source, start, end):
                continue
            if is_string_localized_first_argument(source, start):
                continue
            if is_swiftui_localized_key_with_comment(source, start, end):
                continue
            line_text = lines[line - 1] if 0 <= line - 1 < len(lines) else ""
            findings.append(Finding(path, line, text, suggested_key(path, line_text, text)))
    return findings


def write_report(findings: list[Finding]) -> None:
    grouped: dict[Path, list[Finding]] = {}
    for finding in findings:
        grouped.setdefault(finding.path, []).append(finding)

    lines = [
        "# Hardcoded Chinese String Baseline",
        "",
        f"Total findings: {len(findings)}",
        "",
        "Excludes comments, test files, debug `print`/`debugPrint`, and `String(localized:)` source keys.",
        "",
    ]
    for path in sorted(grouped):
        rel = path.relative_to(REPO_ROOT)
        lines.extend([f"## `{rel}`", ""])
        for finding in grouped[path]:
            text = finding.text.replace("`", "\\`")
            lines.append(f"- Line {finding.line}: `{text}` -> `{finding.key}`")
        lines.append("")
    REPORT_PATH.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> int:
    findings = collect_findings()
    write_report(findings)
    print(f"hardcoded_count: {len(findings)}")
    print(f"report: {REPORT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
