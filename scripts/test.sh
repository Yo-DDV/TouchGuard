#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build/tests}"
mkdir -p "$out"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -I modern \
    modern/guard.c tests/guard_test.c -o "$out/guard-test"
sandbox-exec -f tests/isolated.sb "$out/guard-test"
xcrun clang -std=c11 -O1 -g -fsanitize=address,undefined \
    -Wall -Wextra -Werror -I modern modern/guard.c tests/guard_test.c \
    -o "$out/guard-sanitized"
"$out/guard-sanitized"
plutil -lint modern/Info.plist
plutil -lint modern/dev.yoddv.TouchGuard.plist
bash -n scripts/build.sh scripts/test.sh
