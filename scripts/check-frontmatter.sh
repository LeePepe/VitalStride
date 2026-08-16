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
#
# 解析逻辑住在 scripts/lib/frontmatter.py（真实文件，不是 heredoc）。
# **本脚本不得再引入 heredoc / here-string**（MY-1415）：self-hosted mac runner
# 的 bash 5.3 在 payload >= PIPE_BUF(512B) 时会永久阻塞，而原先内嵌的两段解析器
# 分别是 1064B / 1161B —— 脚本在写 heredoc 时就挂死，pre-push 与 CI policy job
# 一起卡住，且没有任何输出。约束由 scripts/ci/review-cli-stdin.contract.test.sh 锁定。
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"; cd "$REPO"
command -v python3 >/dev/null || { echo "⚠️  无 python3，跳过 frontmatter 防腐校验"; exit 0; }

TOP_CONTEXT="CONTEXT.md"
[ -f "$TOP_CONTEXT" ] || { echo "❌ 缺顶层 $TOP_CONTEXT"; exit 1; }

PARSER="scripts/lib/frontmatter.py"
[ -f "$PARSER" ] || { echo "❌ 缺解析器 $PARSER"; exit 1; }

# ---- 解析 canonical_roles（顶层）----
CANON="$(python3 "$PARSER" canon "$TOP_CONTEXT")"
[ -n "$CANON" ] || { echo "❌ $TOP_CONTEXT: 缺 canonical_roles"; exit 1; }

fail=0
for tc in Packages/*/CONTEXT.md; do
  [ -f "$tc" ] || continue
  dir="$(dirname "$tc")"; pkg="$(basename "$dir")"
  parsed="$(python3 "$PARSER" parse "$tc")"
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
  # 用 tr 拆分而非 `read -ra <<<`：here-string 同样是 >=512B 会阻塞的 bash 5.3 路径。
  # `set -f` 关掉 glob：层名理应是纯标识符，但这是校验脚本，不能让写坏的
  # frontmatter（含 `*`）在拆分时被展开成文件名而静默改变判定结果。
  set -f
  for d in $(printf '%s' "$deps" | tr ',' ' '); do [ -z "$d" ] && continue
    [ -d "Packages/$d" ] || { echo "❌ $tc: depends_on '$d' 是幽灵层（Packages/$d 不存在）"; fail=1; }
    printf '%s\n' "$declared" | grep -qx "$d" || { echo "❌ $tc: depends_on 写了 '$d' 但 Package.swift 没声明"; fail=1; }
  done
  set +f
  while IFS= read -r pd; do [ -z "$pd" ] && continue
    printf ',%s,' "$deps" | grep -q ",$pd," || { echo "❌ $tc: Package.swift 依赖 '$pd' 但 depends_on 漏写"; fail=1; }
  done < <(printf '%s\n' "$declared")

  # ③ test 命令的 --package-path 存在
  tp="$(echo "$testcmd" | grep -oE -- '--package-path[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
  [ -z "$tp" ] || [ -d "$tp" ] || { echo "❌ $tc: test 路径 '$tp' 不存在"; fail=1; }

  # ④ roles: 角色名 ∈ canonical_roles；每个条目在 Sources 下真实存在（目录或 <条目>.swift）
  #    交给 python 做（bash 数组 + IFS 在 set -u 下易碎）
  roles_err="$(python3 "$PARSER" roles "$tc" "$dir" "$pkg" "$CANON")"
  if [ -n "$roles_err" ]; then
    while IFS= read -r line; do [ -z "$line" ] && continue; echo "❌ $tc: $line"; fail=1; done < <(printf '%s\n' "$roles_err")
  fi
done

[ "$fail" -eq 0 ] && echo "✅ frontmatter 与代码一致" \
  || { echo "架构变了？更新对应 CONTEXT.md frontmatter 后重试。"; exit 1; }
