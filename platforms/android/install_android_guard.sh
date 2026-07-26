#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/adb_focus_guard.sh"

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "adb_focus_guard.sh not found at $SCRIPT_PATH"
  exit 1
fi

chmod +x "$SCRIPT_PATH"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. Install Android platform-tools first."
  exit 1
fi

adb start-server >/dev/null 2>&1 || true
adb devices

echo "Android guard is ready."
echo "Run: $SCRIPT_PATH"
