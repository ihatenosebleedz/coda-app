#!/bin/sh
# Builds Navi.app and Navi.ipa for arm64 iOS without an .xcodeproj.
#
# NaviCore is a platform-independent Swift package with no UI, so instead of
# hand-maintaining a pbxproj we drive swiftc + actool directly. This keeps the
# whole iOS build in one auditable script that runs on any Mac (and in CI).
#
# The output .app is deliberately UNSIGNED. SideStore signs it on-device with
# the user's own certificate, so no signing identity is needed in CI.
#
# Usage:
#   scripts/build-ios.sh [output-dir]
#
# Requirements: Xcode command line tools, run on macOS.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${1:-$REPO_ROOT/build-ios}

APP_NAME=Navi
BUNDLE_ID=io.github.ihatenosebleedz.navi
DEPLOYMENT_TARGET=17.0
SDK_NAME=iphoneos

cd "$REPO_ROOT"

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: build-ios.sh requires macOS (xcrun + iphoneos SDK)." >&2
	echo "       On Linux use scripts/naviswift for the NaviCore test suite." >&2
	exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
	echo "error: xcrun not found. Install Xcode and run xcode-select --switch." >&2
	exit 1
fi

echo "==> Xcode: $(xcodebuild -version | tr '\n' ' ')"
SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
SDK_VERSION=$(xcrun --sdk "$SDK_NAME" --show-sdk-version)
echo "==> SDK: $SDK_NAME $SDK_VERSION ($SDK_PATH)"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

CORE_SOURCES=$(find Sources/NaviCore -name '*.swift' | sort)
APP_SOURCES=$(find App -name '*.swift' | sort)

if [ -z "$APP_SOURCES" ]; then
	echo "error: no Swift sources found under App/." >&2
	exit 1
fi

# 1. Compile NaviCore into an iOS static library plus its swiftmodule, so the
#    app sources can `import NaviCore` exactly as they would under SwiftPM.
echo "==> Compiling NaviCore for iOS (arm64, iOS $DEPLOYMENT_TARGET)"
CORE_MODULE_DIR="$OUTPUT_DIR/modules"
mkdir -p "$CORE_MODULE_DIR"

# shellcheck disable=SC2086
xcrun swiftc \
	-target "arm64-apple-ios$DEPLOYMENT_TARGET" \
	-sdk "$SDK_PATH" \
	-O \
	-whole-module-optimization \
	-module-name NaviCore \
	-emit-module -emit-module-path "$CORE_MODULE_DIR/NaviCore.swiftmodule" \
	-emit-library -o "$OUTPUT_DIR/libNaviCore.a" \
	$CORE_SOURCES

# 2. Compile the SwiftUI app against that module. -parse-as-library is required
#    so that @main is treated as the entry point rather than a top-level file.
echo "==> Compiling $APP_NAME app"
# shellcheck disable=SC2086
xcrun swiftc \
	-target "arm64-apple-ios$DEPLOYMENT_TARGET" \
	-sdk "$SDK_PATH" \
	-O \
	-parse-as-library \
	-module-name "$APP_NAME" \
	-I "$CORE_MODULE_DIR" \
	-L "$OUTPUT_DIR" \
	-lNaviCore \
	-framework SwiftUI \
	-framework UIKit \
	-framework AVFoundation \
	-framework AVKit \
	-framework MediaPlayer \
	-framework Combine \
	-framework Security \
	-Xlinker -rpath -Xlinker /usr/lib/swift \
	-o "$OUTPUT_DIR/$APP_NAME" \
	$APP_SOURCES

# 3. Assemble the .app bundle by hand.
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE"

cp "$OUTPUT_DIR/$APP_NAME" "$APP_BUNDLE/$APP_NAME"

# actool compiles Assets.xcassets into Assets.car. Skip silently when there is
# no catalog so a bare-bones checkout still produces an installable app.
if [ -d "App/Assets.xcassets" ]; then
	echo "==> Compiling asset catalog"
	xcrun actool \
		--compile "$APP_BUNDLE" \
		--platform "$SDK_NAME" \
		--minimum-deployment-target "$DEPLOYMENT_TARGET" \
		--target-device iphone \
		--app-icon AppIcon \
		--output-format human-readable-text \
		--notices \
		--warnings \
		App/Assets.xcassets
fi

# Install the maintained Info.plist, then make sure the identifiers match the
# binary this script produced.
cp App/Info.plist "$APP_BUNDLE/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_BUNDLE/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Info.plist"

# Strip the debug dylib the Swift driver emits next to the executable; the app
# is fully static apart from the system frameworks linked above.
rm -f "$APP_BUNDLE/$APP_NAME.debug.dylib"

echo "==> Validating bundle"
plutil -lint "$APP_BUNDLE/Info.plist"
file "$APP_BUNDLE/$APP_NAME"

# 4. Package as an .ipa. iOS expects the app to live in a Payload/ directory.
echo "==> Packaging .ipa"
IPA_STAGE="$OUTPUT_DIR/ipa-stage"
rm -rf "$IPA_STAGE"
mkdir -p "$IPA_STAGE/Payload"
cp -R "$APP_BUNDLE" "$IPA_STAGE/Payload/"

IPA_PATH="$OUTPUT_DIR/$APP_NAME.ipa"
rm -f "$IPA_PATH"
(cd "$IPA_STAGE" && zip -qry "$IPA_PATH" Payload)

echo "==> Built $IPA_PATH"
ls -lh "$IPA_PATH"
echo
echo "The app is unsigned. Install it with SideStore, which signs it on-device."
echo "Bundle id: $BUNDLE_ID   minimum iOS: $DEPLOYMENT_TARGET"
