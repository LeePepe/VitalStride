#!/usr/bin/env bash
# check-frontmatter: 校验所有 formal layer CONTEXT.md 的 frontmatter 与代码一致。
# 腐烂即报错（exit 1）。依赖 python3。
#
# 校验四件事:
#   ① layer 名、change-owner paths 与 context 位置一致
#   ② depends_on ⇄ Package.swift/project.yml 双向一致（不漏、不多、不指向幽灵层）
#   ③ depended_by 与 depends_on 互为镜像；test 命令引用路径存在
#   ④ roles: 角色名都在顶层 CONTEXT.md 的 canonical_roles 里；每个条目在本层 Sources 下
#      真实存在（作为目录或 <条目>.swift 文件）
#   ⑤ tracked schedulable paths are exhaustive and non-overlapping; declared
#      support/generated/local-only exclusions are outside all layer content
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
COVERAGE="scripts/lib/layer_coverage.py"
[ -f "$COVERAGE" ] || { echo "❌ 缺递归 layer resolver $COVERAGE"; exit 1; }
CONTEXTS=()
while IFS= read -r context; do
  [ -n "$context" ] && CONTEXTS+=("$context")
done < <(python3 "$COVERAGE" contexts)
for tc in "${CONTEXTS[@]}"; do
  [ -f "$tc" ] || continue
  dir="$(dirname "$tc")"; pkg="$(basename "$dir")"
  parsed="$(python3 "$PARSER" parse "$tc")"
  [ "$parsed" = "NO_FRONTMATTER" ] && { echo "❌ $tc: 缺 frontmatter"; fail=1; continue; }
  layer="$(echo "$parsed"  | sed -n 's/^LAYER=//p')"
  deps="$(echo "$parsed"   | sed -n 's/^DEPS=//p')"
  by="$(echo "$parsed"     | sed -n 's/^BY=//p')"
  paths="$(echo "$parsed"  | sed -n 's/^PATHS=//p')"
  testcmd="$(echo "$parsed"| sed -n 's/^TEST=//p')"

  # ① Leaf ownership. Context location does not define layer identity.
  if [ -n "$paths" ]; then
    while IFS= read -r owned; do
      [ -z "$owned" ] && continue
      [ -e "$owned" ] || { echo "❌ $tc: paths 条目 '$owned' 不存在"; fail=1; }
    done < <(printf '%s' "$paths" | tr '|' '\n')
  fi

  # ② depends_on ⇄ code/config declarations.
  if [ "$layer" = "AppUI" ]; then
    # AppUI owns all Xcode targets as one change-owner layer. The allowed local
    # dependency set is the union of local package references in project.yml.
    declared="$(grep -E '^[[:space:]]+- package:[[:space:]]+' project.yml 2>/dev/null \
      | sed -E 's/.*- package:[[:space:]]+([^[:space:]]+).*/\1/' \
      | while IFS= read -r d; do [ -d "Packages/$d" ] && printf '%s\n' "$d"; done \
      | sort -u || true)"
  elif [ "$layer" = "RepoInfra" ]; then
    # Repository automation/config has no production code dependency. Invoking
    # another layer's validation command is a gate relationship, not depends_on.
    declared=""
  else
    # Directory-backed SPM layers (Packages/* and Prototype).
    declared="$(grep -oE '\.package\(path:[[:space:]]*"\.\./[^"]+"' "$dir/Package.swift" 2>/dev/null \
                  | sed -E 's|.*/([^"]+)".*|\1|' | sort -u || true)"
  fi
  # 用 tr 拆分而非 `read -ra <<<`：here-string 同样是 >=512B 会阻塞的 bash 5.3 路径。
  # `set -f` 关掉 glob：层名理应是纯标识符，但这是校验脚本，不能让写坏的
  # frontmatter（含 `*`）在拆分时被展开成文件名而静默改变判定结果。
  set -f
  for d in $(printf '%s' "$deps" | tr ',' ' '); do [ -z "$d" ] && continue
    depctx="$(python3 "$COVERAGE" field "$d" context 2>/dev/null || true)"
    [ -f "$depctx" ] || { echo "❌ $tc: depends_on '$d' 是幽灵层（无 CONTEXT.md）"; fail=1; continue; }
    printf '%s\n' "$declared" | grep -qx "$d" || { echo "❌ $tc: depends_on 写了 '$d' 但代码/配置没声明"; fail=1; }

    reverse="$(python3 "$PARSER" parse "$depctx" | sed -n 's/^BY=//p')"
    printf ',%s,' "$reverse" | grep -q ",$layer," \
      || { echo "❌ $tc: depends_on '$d'，但 $depctx.depended_by 漏写 '$layer'"; fail=1; }
  done
  set +f
  while IFS= read -r pd; do [ -z "$pd" ] && continue
    printf ',%s,' "$deps" | grep -q ",$pd," || { echo "❌ $tc: 代码/配置依赖 '$pd' 但 depends_on 漏写"; fail=1; }
  done < <(printf '%s\n' "$declared")

  set -f
  for consumer in $(printf '%s' "$by" | tr ',' ' '); do [ -z "$consumer" ] && continue
    consumerctx="$(python3 "$COVERAGE" field "$consumer" context 2>/dev/null || true)"
    if [ ! -f "$consumerctx" ]; then
      echo "❌ $tc: depended_by '$consumer' 是幽灵层（无 CONTEXT.md）"; fail=1; continue
    fi
    consumerdeps="$(python3 "$PARSER" parse "$consumerctx" | sed -n 's/^DEPS=//p')"
    printf ',%s,' "$consumerdeps" | grep -q ",$layer," \
      || { echo "❌ $tc: depended_by 写了 '$consumer'，但 $consumerctx.depends_on 漏写 '$layer'"; fail=1; }
  done
  set +f

  # ③ test command target exists.
  tp="$(echo "$testcmd" | grep -oE -- '--package-path[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
  [ -z "$tp" ] || [ -d "$tp" ] || { echo "❌ $tc: test 路径 '$tp' 不存在"; fail=1; }
  xp="$(echo "$testcmd" | grep -oE -- '-project[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
  [ -z "$xp" ] || [ -e "$xp" ] || { echo "❌ $tc: test project '$xp' 不存在"; fail=1; }
  sp="$(printf '%s\n' "$testcmd" | awk '$1 == "bash" || $1 == "python3" {print $2}')"
  [ -z "$sp" ] || [ -f "$sp" ] || { echo "❌ $tc: test script '$sp' 不存在"; fail=1; }

  # ④ roles: 角色名 ∈ canonical_roles；每个条目在 Sources 下真实存在（目录或 <条目>.swift）
  #    交给 python 做（bash 数组 + IFS 在 set -u 下易碎）
  roles_err="$(python3 "$PARSER" roles "$tc" "$dir" "$pkg" "$CANON")"
  if [ -n "$roles_err" ]; then
    while IFS= read -r line; do [ -z "$line" ] && continue; echo "❌ $tc: $line"; fail=1; done < <(printf '%s\n' "$roles_err")
  fi
done

# AppUI is a logical multi-root layer. Its explicit path map must cover every
# production/test/build-config root exactly once; additions cannot silently
# fall back to "outside all layers".
APPUI_REQUIRED=(
  VitalStride VitalStrideMac "VitalStrideWatch Watch App" VitalStrideWidgets
  VitalStrideTests VitalStrideUITests VitalStrideWatchTests project.yml
)
APPUI_PATHS="$(python3 "$PARSER" parse VitalStride/CONTEXT.md | sed -n 's/^PATHS=//p')"
for required in "${APPUI_REQUIRED[@]}"; do
  printf '%s' "$APPUI_PATHS" | tr '|' '\n' | grep -Fxq "$required" \
    || { echo "❌ VitalStride/CONTEXT.md: AppUI paths 漏写 '$required'"; fail=1; }
done

# Recursively audit every root-to-leaf route and tracked path.
if ! python3 "$COVERAGE" audit; then
  fail=1
fi

[ "$fail" -eq 0 ] && echo "✅ frontmatter 与代码一致" \
  || { echo "架构变了？更新对应 CONTEXT.md frontmatter 后重试。"; exit 1; }
