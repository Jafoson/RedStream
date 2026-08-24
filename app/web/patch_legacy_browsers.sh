#!/usr/bin/env bash
# Down-levels ES2020+ syntax in the built Flutter web output so it can run
# on pre-2020 browser engines (e.g. Smart TV "legacy browser" apps whose
# Chromium engine predates Chrome 80 / Feb 2020).
#
# Flutter's web loader (flutter_bootstrap.js, which inlines flutter.js) and
# CanvasKit's own glue JS (canvaskit/**/*.js) use optional chaining (?.) and
# nullish coalescing (?? / ??=) unconditionally, with no build flag to opt
# out. On an old engine this is a SyntaxError parsing the file — nothing
# runs at all, not even our own bootstrap config — which shows up as a
# blank white screen with no console output. esbuild strips just that
# syntax, targeting Chrome 69 (~2018/2019 engines), without touching
# import.meta / dynamic import / ES modules, which those browsers already
# support natively. main.dart.js (dart2js output) doesn't currently use
# this syntax but is included for safety, in case a future Dart SDK starts
# emitting it.
#
# Usage: web/patch_legacy_browsers.sh [build/web]
# Run from the app/ directory (or let this script cd there itself).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${1:-build/web}"

if [ ! -x ./esbuild ]; then
    curl -fsSL https://esbuild.github.io/dl/latest | sh
fi

for f in "$BUILD_DIR/flutter_bootstrap.js" "$BUILD_DIR/main.dart.js"; do
    if [ -f "$f" ]; then
        ./esbuild "$f" --target=chrome69 --outfile="$f" --allow-overwrite --log-level=warning
    fi
done

for f in "$BUILD_DIR/canvaskit/canvaskit.js" \
         "$BUILD_DIR/canvaskit/chromium/canvaskit.js" \
         "$BUILD_DIR/canvaskit/webparagraph/canvaskit.js" \
         "$BUILD_DIR/canvaskit/skwasm.js" \
         "$BUILD_DIR/canvaskit/skwasm_heavy.js" \
         "$BUILD_DIR/canvaskit/wimp.js"; do
    if [ -f "$f" ]; then
        ./esbuild "$f" --target=chrome69 --format=esm --outfile="$f" --allow-overwrite --log-level=warning
    fi
done
