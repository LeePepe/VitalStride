#!/usr/bin/env python3
"""CONTEXT.md frontmatter 解析器（check-frontmatter.sh 的后端）。

原先这三段逻辑是 check-frontmatter.sh 里的三个 `python3 - <<'PY'` heredoc。
在 self-hosted mac runner 的 bash 5.3 上，**任何 >= PIPE_BUF(512B) 的 heredoc
会永久阻塞**（MY-1415），其中两段分别是 1064B / 1161B —— 脚本因此在写 heredoc
时挂死，pre-push 与 CI policy job 都卡在这里。搬到真实文件后不再有 heredoc，
根因消失，且这些逻辑本来就该是可独立运行、可独立测试的程序。

行为与原 heredoc 逐字等价（含输出格式），三个子命令对应原来的三段：

  canon <top-context>                 → 逗号分隔的 canonical_roles
  parse <layer-context>               → NO_FRONTMATTER | LAYER=/TEST=/DEPS=/ROLE= 行
  roles <layer-context> <dir> <pkg> <canon>  → 每行一条错误（无错则无输出）
"""

import glob
import os
import re
import sys


def read_frontmatter(path):
    """取 `---` 包住的 frontmatter 正文；没有则返回 None。"""
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else None


def parse_list(fm, key):
    m = re.search(r"^%s:\s*\[(.*?)\]\s*$" % re.escape(key), fm, re.M)
    return [x.strip() for x in (m.group(1) if m else "").split(",") if x.strip()]


def parse_scalar(fm, key):
    m = re.search(r"^%s:\s*(.+)$" % re.escape(key), fm, re.M)
    return m.group(1).strip() if m else ""


def parse_roles(fm):
    """解析 `roles:` 块 —— 缩进的 `Key: [a, b]` 行，遇到顶格行即结束。"""
    roles, in_roles = {}, False
    for line in fm.splitlines():
        if re.match(r"^roles:\s*$", line):
            in_roles = True
            continue
        if in_roles:
            m = re.match(r"^\s+([A-Za-z]+):\s*\[(.*?)\]\s*$", line)
            if m:
                roles[m.group(1)] = [x.strip() for x in m.group(2).split(",") if x.strip()]
            elif re.match(r"^\S", line):
                in_roles = False
    return roles


def cmd_canon(top_context):
    fm = read_frontmatter(top_context) or ""
    print(",".join(parse_list(fm, "canonical_roles")))
    return 0


def cmd_parse(layer_context):
    fm = read_frontmatter(layer_context)
    if fm is None:
        print("NO_FRONTMATTER")
        return 0
    print("LAYER=" + parse_scalar(fm, "layer"))
    print("TEST=" + parse_scalar(fm, "test"))
    print("DEPS=" + ",".join(parse_list(fm, "depends_on")))
    for key, entries in parse_roles(fm).items():
        print("ROLE=%s=%s" % (key, "|".join(entries)))
    return 0


def cmd_roles(layer_context, dir_, pkg, canon_csv):
    """角色名 ∈ canonical_roles；每个条目在 Sources 下真实存在。"""
    canon = canon_csv.split(",")
    fm = read_frontmatter(layer_context) or ""
    srcroot = os.path.join(dir_, "Sources", pkg)
    for key, entries in parse_roles(fm).items():
        if key not in canon:
            print(f"roles 角色 '{key}' 不在 canonical_roles {canon}")
        for e in entries:
            if os.path.isdir(os.path.join(srcroot, e)):
                continue
            if os.path.isfile(os.path.join(srcroot, e + ".swift")):
                continue
            if glob.glob(os.path.join(srcroot, "**", e + ".swift"), recursive=True):
                continue
            print(f"roles 条目 '{e}'（角色 {key}）在 {srcroot} 下既非目录也非 <条目>.swift")
    return 0


COMMANDS = {"canon": (cmd_canon, 1), "parse": (cmd_parse, 1), "roles": (cmd_roles, 4)}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(f"usage: {argv[0]} {{{'|'.join(COMMANDS)}}} <args...>", file=sys.stderr)
        return 2
    fn, argc = COMMANDS[argv[1]]
    args = argv[2:]
    if len(args) != argc:
        print(f"{argv[1]}: 需要 {argc} 个参数，实际 {len(args)}", file=sys.stderr)
        return 2
    return fn(*args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
