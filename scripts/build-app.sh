#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${SDK_VERSION%%.*} < 26 )); then
    printf 'macOS SDK 26+ is required; selected SDK is %s. Check xcode-select -p.\n' "$SDK_VERSION" >&2
    exit 1
fi
ARCH="${CODEX_METER_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
BUILD_ARGS=(-c release --arch "$ARCH" --scratch-path "$PROJECT_DIR/.build/$ARCH")
swift build "${BUILD_ARGS[@]}" --product CodexMeter
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Codex Meter.app"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/CodexMeter"
# Recreate only this generated bundle, so old signatures/resources cannot leak into a release.
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexMeter" "$APP_EXECUTABLE"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns LICENSE "$APP_DIR/Contents/Resources/"
# Debug symbols can embed absolute source and object paths. Strip before signing.
xcrun strip -S "$APP_EXECUTABLE"
if LC_ALL=C grep -aFq -e "$PROJECT_DIR/" -e "$HOME/" -e '/Users/' -e '/home/' "$APP_EXECUTABLE"; then
    printf '%s\n' 'Build failed: the app executable still contains local paths.' >&2
    exit 1
fi
SIGN_IDENTITY="${CODEX_METER_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
    SIGNATURE_DETAILS="$(codesign -dv --verbose=2 "$APP_DIR" 2>&1)"
    if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -q '^Authority=Developer ID Application:'; then
        printf 'Distribution signing requires a Developer ID Application certificate.\n' >&2
        exit 1
    fi
fi
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
printf 'Built: %s\n' "$APP_DIR"
