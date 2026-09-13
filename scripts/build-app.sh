#!/usr/bin/env bash
#
# Builds DeepSeekUsage.app (a menu bar / LSUIElement bundle) from the SwiftPM package.
#
#   ./scripts/build-app.sh            # release
#   ./scripts/build-app.sh debug      # debug
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="DeepSeekUsage"
BUNDLE_ID="dev.locao.DeepSeekUsage"
VERSION="0.0.1"
MIN_MACOS="14.0"
APP_DIR="dist/${APP_NAME}.app"

# Keep every SwiftPM/Clang cache inside the checkout so the build needs no writes
# outside the project directory.
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
SPM_ARGS=(
  --scratch-path .build
  --cache-path .swiftpm/cache
  --config-path .swiftpm/config
  --security-path .swiftpm/security
)

# SwiftPM compiles manifests and runs tests inside its own sandbox-exec, and macOS refuses
# to nest that inside an outer sandbox. Build hosts that already sandbox the shell (for
# example the DeepSeek Harness) need it turned off; a normal terminal does not.
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
  echo "==> SwiftPM sandbox disabled (SWIFTPM_DISABLE_SANDBOX=1)"
  SPM_ARGS+=(--disable-sandbox)
fi

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}" "${SPM_ARGS[@]}"

BIN_DIR="$(swift build -c "${CONFIG}" "${SPM_ARGS[@]}" --show-bin-path)"
BIN="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "$BIN" ]]; then
  echo "error: expected executable at $BIN" >&2
  exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>DeepSeek Usage</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
if codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null 2>&1; then
  echo "    signed (ad-hoc)"
else
  echo "    warning: ad-hoc codesign failed — the app still runs locally"
fi

echo "==> done: ${APP_DIR}"
echo "    open ${APP_DIR}"
