#!/usr/bin/env bash
# Launch or snapshot the 120Hz Native SwiftUI 4-Page × 10-Candidate VitalStride Preview Host
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_PATH="$REPO_ROOT/Prototype"

swift build --package-path "$PACKAGE_PATH" --product VitalStridePreviewHost
BIN_PATH="$(swift build --package-path "$PACKAGE_PATH" --show-bin-path)/VitalStridePreviewHost"
APP_ROOT="/tmp/vs-preview-host"
APP_PATH="$APP_ROOT/VitalStridePreviewHost.app"
CONTENTS_PATH="$APP_PATH/Contents"

while read -r pid; do
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
done < <(ps -axo pid=,args= | awk '/\/VitalStridePreviewHost(\s|$)/ && $0 !~ /open-local-preview\.sh/ && $0 !~ /awk/ { print $1 }')
sleep 0.2

mkdir -p "$CONTENTS_PATH/MacOS"
rm -f "$CONTENTS_PATH/MacOS/VitalStridePreviewHost"
cp "$BIN_PATH" "$CONTENTS_PATH/MacOS/VitalStridePreviewHost"
chmod +x "$CONTENTS_PATH/MacOS/VitalStridePreviewHost"

printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<dict>' \
  '  <key>CFBundleExecutable</key>' \
  '  <string>VitalStridePreviewHost</string>' \
  '  <key>CFBundleIdentifier</key>' \
  '  <string>com.leepepe.vitalstride.previewhost</string>' \
  '  <key>CFBundleName</key>' \
  '  <string>VitalStridePreviewHost</string>' \
  '  <key>CFBundlePackageType</key>' \
  '  <string>APPL</string>' \
  '  <key>NSHighResolutionCapable</key>' \
  '  <true/>' \
  '</dict>' \
  '</plist>' > "$CONTENTS_PATH/Info.plist"

codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || true

if [ "${1:-}" = "--snapshot" ] || [ "${1:-}" = "--snapshot-all" ] || [ "${1:-}" = "--archive-and-reset" ]; then
  "$BIN_PATH" "$@"
else
  if [ "$#" -gt 0 ]; then
    open -n -a "$APP_PATH" --args "$@"
  else
    open -n -a "$APP_PATH"
  fi
  echo "✅ Packaged and launched $APP_PATH"
fi
