#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build}"
app="$out/TouchGuard.app"
if [[ -e "$app" || -L "$app" ]]; then
    printf 'Refusing to overwrite an existing app; choose a fresh output directory.\n' >&2
    exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchAgents"
cp modern/Info.plist "$app/Contents/Info.plist"
cp modern/dev.yoddv.TouchGuard.plist "$app/Contents/Library/LaunchAgents/"
xcrun clang -x objective-c -std=c11 -O2 -Wall -Wextra -Werror -fobjc-arc \
    -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 \
    modern/main.m modern/guard.c tests/native_probe.m -I modern \
    -framework AppKit -framework ApplicationServices -framework Carbon \
    -framework ServiceManagement -o "$app/Contents/MacOS/TouchGuard"
revision="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then revision="$revision-dirty"; fi
printf '%s\n' "$revision" > "$app/Contents/Resources/source-revision.txt"
signing="${SIGNING_IDENTITY:--}"
if [[ "$signing" == '-' ]]; then
    codesign --force --options runtime --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$signing" "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
