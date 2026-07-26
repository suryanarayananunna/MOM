#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/focus_guard.sh"
PLIST_TEMPLATE="$ROOT_DIR/scripts/focus_guard.launchd.plist"
TARGET_PLIST="$HOME/Library/LaunchAgents/com.mom.focusguard.plist"
DATA_ROOT="$HOME/Library/Application Support/MOMFocusGuard"
DEFAULT_MODEL_PATH="$ROOT_DIR/Models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
LLAMA_EXECUTABLE="${MOM_LOCAL_LLM_EXECUTABLE:-/opt/homebrew/bin/llama-cli}"
MODEL_PATH="${MOM_LOCAL_LLM_MODEL_PATH:-$DEFAULT_MODEL_PATH}"

warn() {
  echo "[warn] $*"
}

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "$cmd not found. $hint"
  fi
}

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "focus_guard.sh not found at $SCRIPT_PATH"
  exit 1
fi

chmod +x "$SCRIPT_PATH"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$DATA_ROOT/captures" "$DATA_ROOT/classifications" "$DATA_ROOT/logs"

require_cmd osascript "Required for notifications and browser tab control."
require_cmd screencapture "Required for screenshot capture."
require_cmd say "Required for spoken focus alert."
if [[ "$LLAMA_EXECUTABLE" == */* ]]; then
  if [[ ! -x "$LLAMA_EXECUTABLE" ]]; then
    warn "llama executable not found at $LLAMA_EXECUTABLE"
  fi
else
  require_cmd "$LLAMA_EXECUTABLE" "Install llama.cpp or set MOM_LOCAL_LLM_EXECUTABLE."
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  warn "Model file not found at $MODEL_PATH"
  warn "Set MOM_LOCAL_LLM_MODEL_PATH before installation if model path differs."
fi

if ! command -v imagesnap >/dev/null 2>&1; then
  warn "imagesnap not found. Webcam captures will be skipped unless you install imagesnap."
fi

sed \
  -e "s|__SCRIPT_PATH__|$SCRIPT_PATH|g" \
  -e "s|__LLAMA_EXECUTABLE__|$LLAMA_EXECUTABLE|g" \
  -e "s|__LLM_MODEL_PATH__|$MODEL_PATH|g" \
  -e "s|__DATA_ROOT__|$DATA_ROOT|g" \
  "$PLIST_TEMPLATE" > "$TARGET_PLIST"

launchctl unload "$TARGET_PLIST" >/dev/null 2>&1 || true
launchctl load "$TARGET_PLIST"
launchctl start com.mom.focusguard || true

echo "Installed and started com.mom.focusguard"
echo "Runtime logs: $DATA_ROOT/logs/focus_guard.runtime.log"
echo "Error logs:   $DATA_ROOT/logs/focus_guard.error.log"
echo "Artifacts:    $DATA_ROOT/captures and $DATA_ROOT/classifications"
