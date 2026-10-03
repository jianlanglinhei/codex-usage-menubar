#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$PROJECT_ROOT/build/tests"
mkdir -p "$TEST_OUTPUT"
xcrun swiftc "$PROJECT_ROOT/Tests/Watchdog/main.swift" "$PROJECT_ROOT/Sources/SleepKeeper.swift" \
  -o "$TEST_OUTPUT/watchdog-generator" -framework AppKit -framework IOKit
python3 "$PROJECT_ROOT/Tests/Watchdog/test_watchdog.py" "$TEST_OUTPUT/watchdog-generator"
xcrun swiftc "$PROJECT_ROOT/Tests/Forecast/main.swift" "$PROJECT_ROOT/Sources/ResetForecast.swift" \
  -o "$TEST_OUTPUT/forecast-check" -framework AppKit
"$TEST_OUTPUT/forecast-check" "$PROJECT_ROOT/Tests/Fixtures/forecast.html"
