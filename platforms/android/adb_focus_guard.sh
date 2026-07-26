#!/usr/bin/env bash
set -euo pipefail

CHECK_INTERVAL_SECONDS="${ANDROID_CHECK_INTERVAL_SECONDS:-3}"
ALERT_REPEAT_SECONDS="${ANDROID_ALERT_REPEAT_SECONDS:-8}"
STREAK_TO_HOME="${ANDROID_STREAK_TO_HOME:-2}"
BLOCK_PACKAGES_CSV="${ANDROID_BLOCK_PACKAGES:-com.google.android.youtube,com.netflix.mediaclient,in.startv.hotstar,com.amazon.avod.thirdpartyclient,tv.twitch.android.app}"

last_alert_epoch=0
streak=0
last_pkg=""

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1"
    exit 1
  fi
}

require_cmd adb

if ! adb get-state >/dev/null 2>&1; then
  echo "No adb device connected. Run: adb devices"
  exit 1
fi

IFS=',' read -r -a BLOCK_PACKAGES <<< "$BLOCK_PACKAGES_CSV"

is_blocked_package() {
  local pkg="$1"
  local b
  for b in "${BLOCK_PACKAGES[@]}"; do
    if [[ "$pkg" == "$b" ]]; then
      return 0
    fi
  done
  return 1
}

get_foreground_package() {
  local out
  out="$(adb shell dumpsys activity activities 2>/dev/null | grep -m1 'mResumedActivity' || true)"
  if [[ -z "$out" ]]; then
    out="$(adb shell dumpsys window windows 2>/dev/null | grep -m1 'mCurrentFocus' || true)"
  fi

  # Extract com.package.name from dumpsys lines.
  local pkg
  pkg="$(printf '%s' "$out" | sed -E 's/.* ([a-zA-Z0-9_\.]+)\/.*/\1/' | tr -d '\r')"
  printf '%s' "$pkg"
}

send_alert() {
  local msg="$1"
  adb shell cmd notification post -S bigtext MOMFocusGuard tag "$msg" >/dev/null 2>&1 || true
}

enforce_home() {
  adb shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
}

echo "[MOM-Android] ADB FocusGuard started. interval=${CHECK_INTERVAL_SECONDS}s"

while true; do
  pkg="$(get_foreground_package)"

  if [[ -n "$pkg" ]] && is_blocked_package "$pkg"; then
    if [[ "$pkg" == "$last_pkg" ]]; then
      streak=$((streak + 1))
    else
      streak=1
      last_pkg="$pkg"
    fi

    if (( streak >= STREAK_TO_HOME )); then
      enforce_home
      now="$(date +%s)"
      if (( now - last_alert_epoch >= ALERT_REPEAT_SECONDS )); then
        send_alert "Distraction app blocked: $pkg"
        last_alert_epoch="$now"
      fi
    fi
  else
    streak=0
    last_pkg=""
  fi

  sleep "$CHECK_INTERVAL_SECONDS"
done
