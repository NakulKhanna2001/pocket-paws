#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIGURATION:-release}"
BUILD_ARGS=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Build slices separately so universal builds also work with command-line
    # tools alone, without SwiftPM's Xcode multi-architecture build backend.
    swift build "${BUILD_ARGS[@]}" --arch arm64
    swift build "${BUILD_ARGS[@]}" --arch x86_64
    ARM_BIN="$(swift build "${BUILD_ARGS[@]}" --arch arm64 --show-bin-path)"
    INTEL_BIN="$(swift build "${BUILD_ARGS[@]}" --arch x86_64 --show-bin-path)"
    BIN="$(swift build "${BUILD_ARGS[@]}" --arch "$(uname -m)" --show-bin-path)"
else
    swift build "${BUILD_ARGS[@]}"
    BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
fi
APP="$ROOT/dist/Pocket Paws.app"
# Recreate this generated output to avoid retaining removed animals or stale signatures.
if [[ -d "$APP" ]]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    lipo -create "$ARM_BIN/PocketPaws" "$INTEL_BIN/PocketPaws" -output "$APP/Contents/MacOS/PocketPaws"
else
    cp "$BIN/PocketPaws" "$APP/Contents/MacOS/PocketPaws"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Animal.bundled() explicitly resolves resources from the signed app's Resources.
for bundle in "$BIN"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

ICONSET="$ROOT/dist/PocketPaws.iconset"
mkdir -p "$ICONSET"
"$BIN/PocketPaws" --export-icon "$ROOT/dist/icon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/dist/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    twice=$((size * 2))
    sips -z "$twice" "$twice" "$ROOT/dist/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PocketPaws.icns"

# Local builds use an ad-hoc signature. Supply a Developer ID identity to make
# a distributable release, then notarize using the process in README.md.
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Pocket-Paws-macOS.zip"
printf 'Built: %s\n' "$APP"
