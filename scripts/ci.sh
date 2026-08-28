#!/usr/bin/env bash
# Runs the same checks as CI.
#
#   ./scripts/ci.sh        # everything
#   ./scripts/ci.sh core   # FinPlanCore package tests only
#   ./scripts/ci.sh app    # generate project, build and test the app target
#
# Override the simulator with FINPLAN_SIMULATOR_ID=<udid> if needed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="FinPlan"
PROJECT="$ROOT/FinPlan.xcodeproj"
DERIVED_DATA="${FINPLAN_DERIVED_DATA:-$ROOT/build/DerivedData}"
STAGE="${1:-all}"

log() { printf '\n==> %s\n' "$*"; }

pick_simulator() {
  if [[ -n "${FINPLAN_SIMULATOR_ID:-}" ]]; then
    echo "$FINPLAN_SIMULATOR_ID"
    return
  fi
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1])[:2] or (0,))
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    sys.exit("no available iPhone simulator found")
candidates.sort(reverse=True)
print(candidates[0][2])
'
}

run_core() {
  log "FinPlanCore: swift test"
  (cd "$ROOT/Packages/FinPlanCore" && swift test)
}

run_app() {
  log "Generating Xcode project"
  (cd "$ROOT" && xcodegen generate)

  local udid
  udid="$(pick_simulator)"
  log "Using simulator $udid"
  xcrun simctl list devices | grep "$udid" || true

  log "Building and testing $SCHEME"
  set -o pipefail
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build test
}

case "$STAGE" in
  core) run_core ;;
  app) run_app ;;
  all)
    run_core
    run_app
    ;;
  *)
    echo "usage: $0 [core|app|all]" >&2
    exit 2
    ;;
esac

log "OK"
