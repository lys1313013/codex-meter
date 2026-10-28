#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
swift run MeterChecks
./scripts/package-release.sh
