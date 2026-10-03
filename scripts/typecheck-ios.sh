#!/bin/sh
# Type-checks the iOS app sources against the real iOS SDK.
#
# This is a pure verification step: it compiles everything to object files and
# emits no .app. It requires macOS with Xcode, and is the check that catches
# API misuse, which `scripts/parse-check.sh` cannot.
#
# Usage:
#   scripts/typecheck-ios.sh
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR="$REPO_ROOT/build-ios/typecheck"

cd "$REPO_ROOT"

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: typecheck-ios.sh requires macOS with Xcode." >&2
	exit 1
fi

DEPLOYMENT_TARGET=${DEPLOYMENT_TARGET:-17.0}
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/modules"

CORE_SOURCES=$(find Sources/NaviCore -name '*.swift' | sort)
APP_SOURCES=$(find App -name '*.swift' | sort)

# Emit the NaviCore swiftmodule so the app sources can resolve `import NaviCore`.
# Only the module interface is needed for a type-check, not the code itself.
echo "==> Emitting NaviCore swiftmodule"
# shellcheck disable=SC2086
xcrun swiftc \
	-target "arm64-apple-ios$DEPLOYMENT_TARGET" \
	-sdk "$SDK_PATH" \
	-module-name NaviCore \
	-emit-module -emit-module-path "$OUTPUT_DIR/modules/NaviCore.swiftmodule" \
	$CORE_SOURCES

echo "==> Type-checking app against NaviCore"
# shellcheck disable=SC2086
xcrun swiftc \
	-typecheck \
	-target "arm64-apple-ios$DEPLOYMENT_TARGET" \
	-sdk "$SDK_PATH" \
	-parse-as-library \
	-module-name Navi \
	-I "$OUTPUT_DIR/modules" \
	$APP_SOURCES

echo "==> Type-check clean"
