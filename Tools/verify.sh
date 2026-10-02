#!/bin/bash
# Full local check: backend + publisher tests, native tests, Release build, privacy guard.
set -euo pipefail
cd "$(dirname "$0")/.."
npm run typecheck
npm test
xcodegen generate --quiet
SIM="${FINANCE_SIMULATOR_ID:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["state"] == "Booted"))')}"
xcodebuild test -project Finance.xcodeproj -scheme Finance -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -quiet
xcodebuild build -project Finance.xcodeproj -scheme Finance -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
python3 Tools/check_private_files.py
