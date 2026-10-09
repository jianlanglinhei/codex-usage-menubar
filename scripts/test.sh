#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$PROJECT_ROOT/build/tests"
L10N="$PROJECT_ROOT/Sources/Localization.swift"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$TEST_OUTPUT"
xcrun swiftc "$PROJECT_ROOT/Tests/Watchdog/main.swift" "$PROJECT_ROOT/Sources/SleepKeeper.swift" "$L10N" \
  -o "$TEST_OUTPUT/watchdog-generator" -framework AppKit -framework IOKit
python3 "$PROJECT_ROOT/Tests/Watchdog/test_watchdog.py" "$TEST_OUTPUT/watchdog-generator"
xcrun swiftc "$PROJECT_ROOT/Tests/Forecast/main.swift" "$PROJECT_ROOT/Sources/ResetForecast.swift" "$L10N" \
  -o "$TEST_OUTPUT/forecast-check" -framework AppKit
"$TEST_OUTPUT/forecast-check" "$PROJECT_ROOT/Tests/Fixtures/forecast.html"
xcrun swiftc "$PROJECT_ROOT/Tests/Usage/main.swift" "$PROJECT_ROOT/Sources/Usage.swift" "$L10N" -o "$TEST_OUTPUT/usage-check"
"$TEST_OUTPUT/usage-check"

xcrun swiftc -parse-as-library "$PROJECT_ROOT/Tests/QuotaCup/Rendering.swift" "$PROJECT_ROOT/Sources/QuotaCup.swift" "$PROJECT_ROOT/Sources/QuotaStatusIcon.swift" "$PROJECT_ROOT/Sources/Usage.swift" "$L10N" \
  -o "$TEST_OUTPUT/cup-check" -framework AppKit -framework SwiftUI
"$TEST_OUTPUT/cup-check" "$TEST_OUTPUT/cup-preview.png"

xcrun swiftc "$PROJECT_ROOT/Tests/QuotaAlerts/main.swift" "$PROJECT_ROOT/Sources/QuotaAlertState.swift" "$PROJECT_ROOT/Sources/Usage.swift" "$L10N" \
  -o "$TEST_OUTPUT/quota-alert-check" -framework CryptoKit
"$TEST_OUTPUT/quota-alert-check"
