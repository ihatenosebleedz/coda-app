#!/bin/sh
# Syntax-checks every Swift source file with the local Swift compiler.
#
# `swiftc -parse` only runs the parser, so it needs neither an iOS SDK nor the
# SwiftUI/AVFoundation modules, which means it works on Linux. That catches
# syntax errors in the app sources before a slow CI macOS run does.
#
# Usage:
#   scripts/parse-check.sh            # parse Sources/ and App/
#   scripts/parse-check.sh App        # parse a single directory
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

TARGETS=${*:-"Sources App"}

for target in $TARGETS; do
	files=$(find "$target" -name '*.swift' | sort)
	if [ -z "$files" ]; then
		echo "error: no Swift files under $target" >&2
		exit 1
	fi

	echo "==> Parsing $(printf '%s\n' "$files" | wc -l | tr -d ' ') file(s) in $target"
	# shellcheck disable=SC2086
	./scripts/swiftenv.sh swiftc -parse $files
done

echo "==> All files parsed cleanly"
