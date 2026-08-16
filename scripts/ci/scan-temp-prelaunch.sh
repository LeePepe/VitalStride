#!/usr/bin/env bash
# TEMP-PRELAUNCH 扫描（spec 019 FR-016 / FR-017 / SC-007）。
#
# TEMP-PRELAUNCH 是**受控临时例外**：发布前单用户调试用的原始健康值，只落本地
# `cloudKitDatabase: .none` 分区。宪法 I 的永久生效状态要求**上架前**把标记的
# 字段 + 写入点全部移除。
#
# 两种模式，因为「发布前」在本项目里有两个不同的含义：
#
#   audit（默认）—— 扫描并报告，命中不阻塞，退出码恒为 0。
#     用于 TestFlight 内测分发。spec 019 spec.md:144 明确：当前处于「未发布、
#     单用户（项目 owner 自用）」阶段，这正是 FR-015/016 例外成立的前提，而
#     TestFlight 内测**就是**该阶段的分发方式。在这里硬阻塞等于在例外窗口内
#     禁止一切内测，恰好废掉例外本身的用途。但仍然打印命中清单 + workflow
#     warning，让残留始终可见，不会悄悄堆积。
#
#   enforce —— 命中即失败（exit 1）。
#     用于 PR 门（ci.yml「Lint & policy」，2026-08-16 起）与将来的 App Store 提交
#     路径（FR-017 的「上架」）。Stage 6e 已把受控例外清零，例外窗口就此关闭 ——
#     清零之后任何新命中都只可能是回归，所以这道门现在每个 PR 都跑。
#     fastlane 目前只有 beta lane，尚无提交 lane；提交路径落地时同样接本模式。
#
# 无论哪种模式，扫描范围缺失或 grep 执行出错一律 exit 1 —— 这道门不能 fail-open。
set -uo pipefail

MODE="${1:-audit}"
case "$MODE" in
  audit|enforce) ;;
  *) echo "::error::未知模式 '$MODE'（可选：audit | enforce）" ; exit 1 ;;
esac

# 扫描范围与 ci.yml 的「No HealthKit values in logs」一致：app targets + Packages
# 源码。不扫 specs/ —— 那里的 TEMP-PRELAUNCH 是**规则文本本身**（FR-016/017 的
# 定义），不是待清除的代码点；也不扫 .github/ 与本脚本（含该字面量做 grep
# pattern，自匹配会让门永远红）。
SCAN_PATHS=(VitalStride VitalStrideMac "VitalStrideWatch Watch App" Packages)

# 先校验每个扫描路径都存在。若目录被改名 / checkout 布局变化，grep 只会少扫一个
# 目录并静默返回空，门就变成「没扫到 = 通过」。路径缺失一律判失败。
for p in "${SCAN_PATHS[@]}"; do
  if [ ! -d "$p" ]; then
    echo "::error::TEMP-PRELAUNCH 扫描路径不存在: $p —— 拒绝在扫描范围残缺的情况下继续"
    exit 1
  fi
done

# 只对「无匹配」(rc=1) 容错；grep 真出错(rc>=2)一律判失败，同样不 fail-open。
set +e
MATCHES=$(grep -rn 'TEMP-PRELAUNCH' --include='*.swift' "${SCAN_PATHS[@]}")
GREP_RC=$?
set -e

if [ "$GREP_RC" -ge 2 ]; then
  echo "::error::TEMP-PRELAUNCH grep 执行失败 (rc=$GREP_RC) —— 拒绝继续"
  exit 1
fi

if [ -z "$MATCHES" ]; then
  echo "OK: 无 TEMP-PRELAUNCH 残留。"
  exit 0
fi

COUNT=$(printf '%s\n' "$MATCHES" | wc -l | tr -d ' ')

if [ "$MODE" = "enforce" ]; then
  echo "::error::上架前必须移除受控临时例外（spec 019 FR-017 / SC-007）"
  echo "TEMP-PRELAUNCH 命中 $COUNT 处："
  echo "$MATCHES"
  echo ""
  echo "要求：移除 RoutingSignalEntry 的 rawPromptDebug/rawResponseDebug 字段"
  echo "      及所有 raw 写入点，恢复「只存 metadata + 分数」（宪法 I 永久态）。"
  exit 1
fi

echo "::warning::存在 $COUNT 处 TEMP-PRELAUNCH 受控临时例外——上架前必须清零（spec 019 FR-017 / SC-007）"
echo "TEMP-PRELAUNCH 命中 $COUNT 处（内测阶段允许，不阻塞本次分发）："
echo "$MATCHES"
echo ""
echo "提醒：这些是发布前调试用的原始健康值字段，只落本地 .none 分区。"
echo "      走 App Store 提交前必须清零，届时同一脚本以 enforce 模式硬阻塞。"
exit 0
