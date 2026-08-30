#!/usr/bin/env bash
set -uo pipefail

QUARANTINE="${APP_TARGET_QUARANTINE:-OverviewHealthSnapshotTests/loadAllMetrics}"
PROJECT="${APP_TARGET_PROJECT:-VitalStride.xcodeproj}"
SCHEME="${APP_TARGET_SCHEME:-VitalStride}"
DESTINATION="${APP_TARGET_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
LOG_PATH="${APP_TARGET_LOG_PATH:-/tmp/app-target-tests.log}"

cmd=(
  xcodebuild
  test
  -project
  "$PROJECT"
  -scheme
  "$SCHEME"
  -destination
  "$DESTINATION"
  -skipPackagePluginValidation
  "-skip-testing:VitalStrideTests/${QUARANTINE}"
)

if [ -n "${APP_TARGET_RUNNER:-}" ]; then
  run_cmd=("$APP_TARGET_RUNNER" "${cmd[@]}")
else
  run_cmd=("${cmd[@]}")
fi

echo "🚦 Starting App target tests"
echo "Running: ${cmd[*]}"
: > "$LOG_PATH"

echo "::group::App target test output"
if "${run_cmd[@]}" 2>&1 | tee "$LOG_PATH"; then
  status=0
else
  status=${PIPESTATUS[0]}
fi
echo "::endgroup::"

if [ "$status" -eq 0 ]; then
  echo "✅ App target tests passed"
  exit 0
fi

echo "❌ App target tests failed with exit status ${status}"
echo "::group::App target failure summary"
summary=$(grep -E "error:|Testing failed|actor-isolated|BUILD FAILED|Unable to find" "$LOG_PATH" | sort -u | head -60 || true)
if [ -n "$summary" ]; then
  printf '%s\n' "$summary"
else
  tail -n 60 "$LOG_PATH" 2>/dev/null || true
fi
echo "::endgroup::"
exit "$status"
