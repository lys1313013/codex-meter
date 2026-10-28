<p align="center"><img src="docs/images/app-icon.png" width="96" alt="Codex Meter icon"></p>

# Codex Meter

A native macOS floating widget for your remaining Codex quota. Keep it on the desktop or show just a number in the menu bar.

Built with Swift, SwiftUI and AppKit. No third-party runtime dependencies, WebView or backend. An independent community project, not affiliated with OpenAI. The application UI is currently in Chinese.

[简体中文](README.md) · [Releases](https://github.com/lys1313013/codex-meter/releases) · [MIT License](LICENSE)

| Desktop ring | Quota details | Menu bar |
| :---: | :---: | :---: |
| <img src="docs/images/desktop-ring.png" width="96" alt="74 percent remaining"> | <img src="docs/images/details.png" width="320" alt="Five-hour and weekly quotas"> | <img src="docs/images/menu-bar.png" width="64" alt="Menu bar number 74"> |

Previews use synthetic data. The ring and detail content are rendered from application views; the detail preview uses an opaque background. The menu bar image illustrates the number format and font size. Live system materials vary by macOS version and appearance.

## Features

- Draggable floating ring, always-on-top option, and menu-bar-only mode.
- Adjustable 40–120pt ring, four palettes, persisted preferences and position.
- Remaining quota, low-quota colors and reset countdowns; the indicator uses the window with the lowest remaining percentage in the selected group.
- Refreshes approximately two minutes after each request completes, on wake and on demand.
- Optional launch at login, managed by macOS (requires the packaged app).
- Multiple quota groups and actual window durations, without assuming both weekly and five-hour limits exist.
- Failed requests retain the previous result with a stale indicator; unknown values never appear as a full quota.

## Requirements and compatibility

- Deployment target: macOS 13+. Older macOS versions still need device validation.
- Initial prebuilt package: Apple Silicon (`arm64`). Intel builds are experimental and have not been tested on an Intel Mac.
- Build tools: Swift 6 and macOS SDK 26+ (Xcode 26+ or matching Command Line Tools).
- Locally checked: macOS 27.2, Apple Silicon, Swift 6.4 and macOS SDK 27.
- CI is configured for `macos-15` with Xcode 26.2 and an `arm64` build. Check the actual Actions results for its status.
- A local Codex installation signed in with a ChatGPT account. API key authentication does not provide this subscription quota.

## Install

Download a matching ZIP from [Releases](https://github.com/lys1313013/codex-meter/releases), extract it and move `Codex Meter.app` to Applications. If there are no downloadable assets yet, build from source:

```bash
git clone https://github.com/lys1313013/codex-meter.git
cd codex-meter
./scripts/build-app.sh
open "dist/Codex Meter.app"
```

Package names identify signing status: `adhoc` (no Developer ID or notarization), `signed` (Developer ID only), or `notarized` (signed, notarized and stapled). The default workflow creates ad-hoc packages, which may be blocked by Gatekeeper. Prefer notarized packages or build locally. See [Apple's distribution guidance](https://developer.apple.com/developer-id/).

## Use and troubleshoot

Drag the ring to move it, double-click for details and right-click for settings. `74` in the menu bar means 74% remaining. `--` indicates unknown or stale data. The settings menu supports a custom Codex executable; Finder-launched apps may have a different PATH from your terminal.

If the wrong account or no quota appears, check which Codex installation the app selected and whether it is signed in with ChatGPT. App-bundled executables take priority over PATH. Only windows returned by Codex are displayed. After a reset time passes, the app waits for fresh server data instead of assuming 100%.

For uninstalling, disable launch at login, quit the app and delete it from Applications. Optionally remove the packaged app's preferences:

```bash
defaults delete io.github.lys1313013.codex-meter
```

## Privacy and development

Each refresh starts a short-lived `codex app-server`, initializes the connection and calls `account/rateLimits/read`. It does not create conversations, generate model responses, or read/copy `auth.json`. Codex handles authentication and network access. The app has no analytics, telemetry or quota-history storage; settings are stored in UserDefaults and launch at login is managed by macOS.

```bash
./scripts/verify.sh
swift run MeterChecks
swift run CodexMeter --check
swift run CodexMeter --render-previews docs/images
```

Automated checks use synthetic fixtures and do not require an account. `--check` is an optional live integration check; it prints quota information, not credentials or raw server responses. Preview generation uses isolated preferences and never starts Codex.

See [Contributing](CONTRIBUTING.md), [Release guide](docs/RELEASING.md) and [Changelog](CHANGELOG.md) (Chinese).

Source code, original icon and example previews are available under the [MIT License](LICENSE), © 2026 lys1313013.
