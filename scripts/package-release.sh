#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Expected a version such as 0.1.0 in Info.plist.\n' >&2
    exit 1
fi
if [[ -n "${CODEX_METER_TAG:-}" && "$CODEX_METER_TAG" != "v$VERSION" ]]; then
    printf 'Tag %s does not match Info.plist version v%s.\n' "$CODEX_METER_TAG" "$VERSION" >&2
    exit 1
fi
if [[ -n "${CODEX_METER_NOTARY_PROFILE:-}" && "${CODEX_METER_SIGN_IDENTITY:--}" == "-" ]]; then
    printf 'Notarization requires CODEX_METER_SIGN_IDENTITY (Developer ID Application).\n' >&2
    exit 1
fi
./scripts/build-app.sh
APP_DIR="$PROJECT_DIR/dist/Codex Meter.app"
ARCH="$(lipo -archs "$APP_DIR/Contents/MacOS/CodexMeter")"
SIGNING="adhoc"
if [[ "${CODEX_METER_SIGN_IDENTITY:--}" != "-" ]]; then SIGNING="signed"; fi
if [[ -n "${CODEX_METER_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ZIP="$PROJECT_DIR/dist/notarization.zip"
    trap 'rm -f "$NOTARY_ZIP"' EXIT
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$CODEX_METER_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    spctl --assess --type execute --verbose "$APP_DIR"
    SIGNING="notarized"
fi
NAME="Codex-Meter-$VERSION-macos-$ARCH-$SIGNING.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PROJECT_DIR/dist/$NAME"
(
    cd "$PROJECT_DIR/dist"
    shasum -a 256 "$NAME" > "$NAME.sha256"
)
printf 'Release archive: %s/dist/%s\n' "$PROJECT_DIR" "$NAME"
