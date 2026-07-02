#!/usr/bin/env bash
# check-frontmatter: 校验每个 Packages/<X>/CONTEXT.md 的 frontmatter 与代码一致。
# 腐烂即报错（exit 1）。依赖 python3。
#
# 校验四件事:
#   ① layer 名 == 目录名
#   ② depends_on ⇄ Package.swift 的 .package(path:"../X") 双向一致（不漏、不多、不指向幽灵层）
#   ③ test 命令引用的 --package-path 路径存在
#   ④ roles: 角色名都在顶层 CONTEXT.md 的 canonical_roles 里；每个条目在本层 Sources 下
#      真实存在（作为目录或 <条目>.swift 文件）
#
# 三段门禁共用（pre-push / CI policy job）。语言相关处仅 Package.swift 依赖提取一处。
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"; cd "$REPO"
command -v python3 >/dev/null || { echo "⚠️  无 python3，跳过 frontmatter 防腐校验"; exit 0; }

TOP_CONTEXT="CONTEXT.md"
[ -f "$TOP_CONTEXT" ] || { echo "❌ 缺顶层 $TOP_CONTEXT"; exit 1; }

# ---- 解析 canonical_roles（顶层）----
CANON="$(python3 - "$TOP_CONTEXT" <<'PY'
import sys, re
t = open(sys.argv[1], encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
fm = m.group(1) if m else ""
mm = re.search(r'^canonical_roles:\s*\[(.*?)\]\s*$', fm, re.M)
roles = [r.strip() for r in (mm.group(1) if mm else "").split(',') if r.strip()]
print(",".join(roles))
PY
)"
[ -n "$CANON" ] || { echo "❌ $TOP_CONTEXT: 缺 canonical_roles"; exit 1; }

# frontmatter 解析器（写临时文件，避免 heredoc 嵌进 $() 的括号解析坑）
PARSER="$(mktemp)"; trap 'rm -f "$PARSER"' EXIT
cat > "$PARSER" <<'PY'
import sys, re
text = open(sys.argv[1], encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m: print("NO_FRONTMATTER"); sys.exit(0)
fm = m.group(1)
def scalar(k):
    mm = re.search(r'^%s:\s*(.+)$' % re.escape(k), fm, re.M)
    return mm.group(1).strip() if mm else ""
def listfield(k):
    mm = re.search(r'^%s:\s*\[(.*?)\]\s*$' % re.escape(k), fm, re.M)
    return [x.strip() for x in (mm.group(1) if mm else "").split(',') if x.strip()]
# roles 块: 收集 "  Key: [a, b]" 行
roles = {}
in_roles = False
for line in fm.splitlines():
    if re.match(r'^roles:\s*$', line): in_roles = True; continue
    if in_roles:
        mm = re.match(r'^\s+([A-Za-z]+):\s*\[(.*?)\]\s*$', line)
        if mm:
            roles[mm.group(1)] = [x.strip() for x in mm.group(2).split(',') if x.strip()]
        elif re.match(r'^\S', line):
            in_roles = False
print("LAYER="+scalar("layer"))
print("TEST="+scalar("test"))
print("DEPS="+",".join(listfield("depends_on")))
for k, v in roles.items():
    print("ROLE=%s=%s" % (k, "|".join(v)))
PY

fail=0
for tc in Packages/*/CONTEXT.md; do
  [ -f "$tc" ] || continue
  dir="$(dirname "$tc")"; pkg="$(basename "$dir")"
  parsed="$(python3 "$PARSER" "$tc")"
  [ "$parsed" = "NO_FRONTMATTER" ] && { echo "❌ $tc: 缺 frontmatter"; fail=1; continue; }
  layer="$(echo "$parsed"  | sed -n 's/^LAYER=//p')"
  deps="$(echo "$parsed"   | sed -n 's/^DEPS=//p')"
  testcmd="$(echo "$parsed"| sed -n 's/^TEST=//p')"

  # ① layer 名 == 目录名
  [ "$layer" = "$pkg" ] || { echo "❌ $tc: layer='$layer' ≠ 目录 '$pkg'"; fail=1; }

  # ② depends_on ⇄ Package.swift 双向一致
  #    从 .package(path: "../X") 提取本地依赖包名
  declared="$(grep -oE '\.package\(path:[[:space:]]*"\.\./[^"]+"' "$dir/Package.swift" 2>/dev/null \
                | sed -E 's|.*/([^"]+)".*|\1|' | sort -u || true)"
  IFS=',' read -ra darr <<< "$deps"
  for d in "${darr[@]:-}"; do [ -z "$d" ] && continue
    [ -d "Packages/$d" ] || { echo "❌ $tc: depends_on '$d' 是幽灵层（Packages/$d 不存在）"; fail=1; }
    echo "$declared" | grep -qx "$d" || { echo "❌ $tc: depends_on 写了 '$d' 但 Package.swift 没声明"; fail=1; }
  done
  while IFS= read -r pd; do [ -z "$pd" ] && continue
    echo ",$deps," | grep -q ",$pd," || { echo "❌ $tc: Package.swift 依赖 '$pd' 但 depends_on 漏写"; fail=1; }
  done <<< "$declared"

  # ③ test 命令的 --package-path 存在
  tp="$(echo "$testcmd" | grep -oE -- '--package-path[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
  [ -z "$tp" ] || [ -d "$tp" ] || { echo "❌ $tc: test 路径 '$tp' 不存在"; fail=1; }

  # ④ roles: 角色名 ∈ canonical_roles；每个条目在 Sources 下真实存在（目录或 <条目>.swift）
  #    交给 python 做（bash 数组 + IFS 在 set -u 下易碎）
  roles_err="$(python3 - "$tc" "$dir" "$pkg" "$CANON" <<'PY'
import sys, re, os, glob
tc, dir_, pkg, canon = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(',')
fm = re.match(r'^---\n(.*?)\n---\n', open(tc, encoding='utf-8').read(), re.S)
fm = fm.group(1) if fm else ""
# 解析 roles 块
roles, in_roles = {}, False
for line in fm.splitlines():
    if re.match(r'^roles:\s*$', line): in_roles = True; continue
    if in_roles:
        mm = re.match(r'^\s+([A-Za-z]+):\s*\[(.*?)\]\s*$', line)
        if mm: roles[mm.group(1)] = [x.strip() for x in mm.group(2).split(',') if x.strip()]
        elif re.match(r'^\S', line): in_roles = False
srcroot = os.path.join(dir_, "Sources", pkg)
errs = []
for key, entries in roles.items():
    if key not in canon:
        errs.append(f"roles 角色 '{key}' 不在 canonical_roles {canon}")
    for e in entries:
        if os.path.isdir(os.path.join(srcroot, e)): continue
        if os.path.isfile(os.path.join(srcroot, e + ".swift")): continue
        if glob.glob(os.path.join(srcroot, "**", e + ".swift"), recursive=True): continue
        errs.append(f"roles 条目 '{e}'（角色 {key}）在 {srcroot} 下既非目录也非 <条目>.swift")
for x in errs: print(x)
PY
)"
  if [ -n "$roles_err" ]; then
    while IFS= read -r line; do [ -z "$line" ] && continue; echo "❌ $tc: $line"; fail=1; done <<< "$roles_err"
  fi
done

[ "$fail" -eq 0 ] && echo "✅ frontmatter 与代码一致" \
  || { echo "架构变了？更新对应 CONTEXT.md frontmatter 后重试。"; exit 1; }
