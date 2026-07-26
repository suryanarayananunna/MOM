#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-6}"
ALARM_REPEAT_SECONDS="${ALARM_REPEAT_SECONDS:-8}"
DRY_RUN="${DRY_RUN:-0}"
RETENTION_DAYS="${RETENTION_DAYS:-3}"

DATA_ROOT="${DATA_ROOT:-$HOME/Library/Application Support/MOMFocusGuard}"
CAPTURE_ROOT="$DATA_ROOT/captures"
RESULT_ROOT="$DATA_ROOT/classifications"
LOG_ROOT="$DATA_ROOT/logs"
LOCK_DIR="$DATA_ROOT/.focusguard.lock"

LLM_EXECUTABLE="${MOM_LOCAL_LLM_EXECUTABLE:-/opt/homebrew/bin/llama-cli}"
LLM_MODEL_PATH="${MOM_LOCAL_LLM_MODEL_PATH:-}"
LLM_THREADS="${MOM_LOCAL_LLM_THREADS:-2}"
LLM_MAX_TOKENS="${MOM_LOCAL_LLM_MAX_TOKENS:-96}"
LLM_TEMPERATURE="${MOM_LOCAL_LLM_TEMPERATURE:-0.1}"
LLM_TIMEOUT_SECONDS="${MOM_LOCAL_LLM_TIMEOUT_SECONDS:-25}"
AWAY_IDLE_SECONDS="${AWAY_IDLE_SECONDS:-45}"
UNPRODUCTIVE_STREAK_TO_CLOSE="${UNPRODUCTIVE_STREAK_TO_CLOSE:-3}"
SAVE_CAPTURES="${SAVE_CAPTURES:-0}"
WEBCAM_CHECK_INTERVAL_SECONDS="${WEBCAM_CHECK_INTERVAL_SECONDS:-120}"
ENABLE_WEBCAM_LLM="${ENABLE_WEBCAM_LLM:-1}"
BROWSER_LLM_CHECK_INTERVAL_SECONDS="${BROWSER_LLM_CHECK_INTERVAL_SECONDS:-90}"
ENABLE_BROWSER_LLM="${ENABLE_BROWSER_LLM:-1}"
SPEAK_QUOTES="${SPEAK_QUOTES:-0}"
SCREEN_FLICKER_ENABLED="${SCREEN_FLICKER_ENABLED:-1}"
BLOCK_STREAMING_SITES="${BLOCK_STREAMING_SITES:-1}"
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-1}"

BROWSERS=("Safari" "Google Chrome" "Microsoft Edge" "Brave Browser" "Arc")
PRODUCTIVE_APPS=("Code" "Cursor" "Terminal" "iTerm2" "Xcode" "PyCharm" "IntelliJ IDEA" "WebStorm")
ALERT_SOUND_PATH="${ALERT_SOUND_PATH:-/System/Library/Sounds/Funk.aiff}"
STREAMING_REGEX='(youtube\.com/watch|youtube\.com/shorts|youtu\.be/|hotstar\.com|netflix\.com|primevideo\.com|hulu\.com|disneyplus\.com|twitch\.tv|instagram\.com|facebook\.com|fb\.com|m\.facebook\.com)'

mkdir -p "$CAPTURE_ROOT" "$RESULT_ROOT" "$LOG_ROOT"
mkdir -p "$DATA_ROOT/tmp"

exec >> "$LOG_ROOT/focus_guard.runtime.log" 2>> "$LOG_ROOT/focus_guard.error.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup() {
  rm -rf "$LOCK_DIR" || true
}

trap cleanup EXIT INT TERM

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another focus_guard instance is already running. Exiting."
  exit 1
fi

run_applescript() {
  osascript -e "$1" 2>/dev/null || true
}

frontmost_app() {
  run_applescript 'tell application "System Events" to get name of first process whose frontmost is true'
}

browser_supported() {
  local app="$1"
  for b in "${BROWSERS[@]}"; do
    if [[ "$b" == "$app" ]]; then
      return 0
    fi
  done
  return 1
}

is_known_productive_app() {
  local app="$1"
  local p
  for p in "${PRODUCTIVE_APPS[@]}"; do
    if [[ "$p" == "$app" ]]; then
      return 0
    fi
  done
  return 1
}

active_tab_url() {
  local app="$1"
  case "$app" in
    "Safari")
      run_applescript 'tell application "Safari"
        if (count of windows) = 0 then return ""
        return URL of current tab of front window
      end tell'
      ;;
    "Google Chrome"|"Microsoft Edge"|"Brave Browser"|"Arc")
      run_applescript "tell application \"$app\"
        if (count of windows) = 0 then return \"\"
        return URL of active tab of front window
      end tell"
      ;;
    *)
      echo ""
      ;;
  esac
}

active_tab_title() {
  local app="$1"
  case "$app" in
    "Safari")
      run_applescript 'tell application "Safari"
        if (count of windows) = 0 then return ""
        return name of current tab of front window
      end tell'
      ;;
    "Google Chrome"|"Microsoft Edge"|"Brave Browser"|"Arc")
      run_applescript "tell application \"$app\"
        if (count of windows) = 0 then return \"\"
        return title of active tab of front window
      end tell"
      ;;
    *)
      echo ""
      ;;
  esac
}

is_youtube_url() {
  local url_lc
  url_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$url_lc" == *"youtube.com"* ]] || [[ "$url_lc" == *"youtu.be"* ]]
}

is_youtube_exploration_url() {
  local url_lc
  url_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  if ! is_youtube_url "$url_lc"; then
    return 1
  fi

  # Do not auto-close while user is on YouTube home/search/channel browsing.
  if [[ "$url_lc" == *"youtube.com/"* ]] && [[ "$url_lc" != *"watch?v="* ]] && [[ "$url_lc" != *"/shorts/"* ]]; then
    return 0
  fi

  return 1
}

is_streaming_url() {
  local url_lc
  url_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$url_lc" =~ $STREAMING_REGEX ]]
}

close_active_tab() {
  local app="$1"
  case "$app" in
    "Safari")
      run_applescript 'tell application "Safari"
        if (count of windows) > 0 then close current tab of front window
      end tell'
      ;;
    "Google Chrome"|"Microsoft Edge"|"Brave Browser"|"Arc")
      run_applescript "tell application \"$app\"
        if (count of windows) > 0 then close active tab of front window
      end tell"
      ;;
  esac
}

capture_screenshot() {
  local output_path="$1"
  if ! screencapture -x "$output_path" >/dev/null 2>&1; then
    : > "$output_path.unavailable"
    log "screenshot capture unavailable"
    return
  fi

  if [[ ! -s "$output_path" ]]; then
    : > "$output_path.unavailable"
    log "screenshot capture produced empty file"
  fi
}

capture_webcam() {
  local output_path="$1"
  if command -v imagesnap >/dev/null 2>&1; then
    if ! imagesnap -q -w 0.2 "$output_path" >/dev/null 2>&1; then
      : > "$output_path.unavailable"
      log "webcam capture unavailable via imagesnap"
    fi
    return
  fi

  if command -v ffmpeg >/dev/null 2>&1; then
    if ! ffmpeg -f avfoundation -framerate 1 -i "0:none" -frames:v 1 -y "$output_path" >/dev/null 2>&1; then
      : > "$output_path.unavailable"
      log "webcam capture unavailable via ffmpeg"
    fi
    return
  fi

  : > "$output_path.unavailable"
  log "webcam capture unavailable: imagesnap/ffmpeg not found"
}

play_focus_feedback() {
  if [[ -f "$ALERT_SOUND_PATH" ]]; then
    afplay "$ALERT_SOUND_PATH" >/dev/null 2>&1 &
  else
    printf '\a'
  fi

  if [[ "$SCREEN_FLICKER_ENABLED" == "1" ]]; then
    # macOS can flash screen on alert sounds when this preference is enabled.
    defaults write com.apple.universalaccess flashScreen -bool true >/dev/null 2>&1 || true
    defaults -currentHost write com.apple.universalaccess flashScreen -bool true >/dev/null 2>&1 || true
    osascript -e 'beep 2' >/dev/null 2>&1 || true
    osascript -e 'beep 2' >/dev/null 2>&1 || true
  fi

  if [[ "$SPEAK_QUOTES" == "1" ]]; then
    say -v Samantha -r 215 "Back to focus mode now." >/dev/null 2>&1 &
  fi
}

notify_user() {
  local title="$1"
  local body="$2"
  local escaped_title="${title//\"/\\\"}"
  local escaped_body="${body//\"/\\\"}"
  run_applescript "display notification \"$escaped_body\" with title \"$escaped_title\""
}

user_idle_seconds() {
  local idle_ns
  idle_ns="$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { print $NF; exit }')"
  if [[ -z "$idle_ns" ]]; then
    echo 0
    return
  fi

  /usr/bin/python3 - "$idle_ns" <<'PY'
import sys

raw = sys.argv[1].strip()
try:
    value = int(raw, 0)
except Exception:
    print(0)
    raise SystemExit(0)

print(max(0, value // 1_000_000_000))
PY
}

extract_json_object() {
  local input_file="$1"
  local output_file="$2"

  /usr/bin/python3 - "$input_file" "$output_file" <<'PY'
import json
import sys

inp = sys.argv[1]
out = sys.argv[2]
text = open(inp, "r", encoding="utf-8", errors="ignore").read()

start = text.find("{")
if start < 0:
    sys.exit(1)

depth = 0
in_string = False
escaped = False
for i, ch in enumerate(text[start:], start=start):
    if in_string:
        if escaped:
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == '"':
            in_string = False
        continue
    if ch == '"':
        in_string = True
    elif ch == '{':
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0:
            snippet = text[start:i+1]
            obj = json.loads(snippet)
            with open(out, "w", encoding="utf-8") as f:
                json.dump(obj, f)
            sys.exit(0)

sys.exit(1)
PY
}

run_llm_classification() {
  local webcam_path="$1"
  local raw_output_path="$2"
  local parsed_output_path="$3"

  if [[ -z "$LLM_MODEL_PATH" ]] || [[ ! -f "$LLM_MODEL_PATH" ]]; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"model_missing"}' > "$parsed_output_path"
    : > "$raw_output_path"
    return
  fi

  if [[ "$LLM_EXECUTABLE" == */* ]]; then
    if [[ ! -x "$LLM_EXECUTABLE" ]]; then
      printf '{"classification":"unknown","confidence":0.0,"reason":"llm_executable_missing"}' > "$parsed_output_path"
      : > "$raw_output_path"
      return
    fi
  elif ! command -v "$LLM_EXECUTABLE" >/dev/null 2>&1; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"llm_executable_missing"}' > "$parsed_output_path"
    : > "$raw_output_path"
    return
  fi

  local prompt
  prompt=$(cat <<EOF
You are a local productivity classifier.
Return a single JSON object only.

Rules:
- classify as "unproductive" when user appears away from system, looking away for long,
  using phone, or generally distracted.
- classify as "productive" when user appears focused on work/study.
- classify as "unknown" if image is unclear.

Input:
webcam_file: ${webcam_path}

Output schema:
{"classification":"productive|unproductive|unknown","confidence":0.0,"reason":"short"}
EOF
)

  local timeout_cmd=("$LLM_EXECUTABLE" -m "$LLM_MODEL_PATH" --threads "$LLM_THREADS" --temp "$LLM_TEMPERATURE" -n "$LLM_MAX_TOKENS" -c 2048 --no-conversation --single-turn --simple-io --no-display-prompt -p "$prompt")

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${LLM_TIMEOUT_SECONDS}s" "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${LLM_TIMEOUT_SECONDS}s" "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  else
    "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  fi

  if ! extract_json_object "$raw_output_path" "$parsed_output_path"; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"parse_failed"}' > "$parsed_output_path"
  fi
}

run_browser_llm_classification() {
  local app="$1"
  local url="$2"
  local tab_title="$3"
  local raw_output_path="$4"
  local parsed_output_path="$5"

  if [[ -z "$LLM_MODEL_PATH" ]] || [[ ! -f "$LLM_MODEL_PATH" ]]; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"model_missing"}' > "$parsed_output_path"
    : > "$raw_output_path"
    return
  fi

  if [[ "$LLM_EXECUTABLE" == */* ]]; then
    if [[ ! -x "$LLM_EXECUTABLE" ]]; then
      printf '{"classification":"unknown","confidence":0.0,"reason":"llm_executable_missing"}' > "$parsed_output_path"
      : > "$raw_output_path"
      return
    fi
  elif ! command -v "$LLM_EXECUTABLE" >/dev/null 2>&1; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"llm_executable_missing"}' > "$parsed_output_path"
    : > "$raw_output_path"
    return
  fi

  local prompt
  prompt=$(cat <<EOF
You are a productivity classifier for browser activity.
Return exactly one JSON object only.

Rules:
- classify "unproductive" for obvious entertainment/doom-scrolling/distraction.
- classify "productive" for clear study/work/learning tasks.
- classify "unknown" only when context is insufficient.

Input:
frontmost_app: ${app}
active_url: ${url}
active_tab_title: ${tab_title}

Output schema:
{"classification":"productive|unproductive|unknown","confidence":0.0,"reason":"short"}
EOF
)

  local timeout_cmd=("$LLM_EXECUTABLE" -m "$LLM_MODEL_PATH" --threads "$LLM_THREADS" --temp "$LLM_TEMPERATURE" -n "$LLM_MAX_TOKENS" -c 2048 --no-conversation --single-turn --simple-io --no-display-prompt -p "$prompt")

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${LLM_TIMEOUT_SECONDS}s" "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${LLM_TIMEOUT_SECONDS}s" "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  else
    "${timeout_cmd[@]}" > "$raw_output_path" 2>&1 || true
  fi

  if ! extract_json_object "$raw_output_path" "$parsed_output_path"; then
    printf '{"classification":"unknown","confidence":0.0,"reason":"parse_failed"}' > "$parsed_output_path"
  fi
}

llm_field() {
  local json_path="$1"
  local field="$2"
  /usr/bin/python3 - "$json_path" "$field" <<'PY'
import json
import sys

path = sys.argv[1]
field = sys.argv[2]
try:
    obj = json.load(open(path, "r", encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit(0)

value = obj.get(field, "")
print(value)
PY
}

record_result() {
  local result_path="$1"
  local timestamp="$2"
  local app="$3"
  local url="$4"
  local tab_title="$5"
  local screenshot_path="$6"
  local webcam_path="$7"
  local rule_classification="$8"
  local llm_classification="$9"
  local llm_confidence="${10}"
  local llm_reason="${11}"
  local final_classification="${12}"
  local idle_seconds="${13}"
  local away_mode="${14}"

  cat > "$result_path" <<EOF
{
  "timestamp": "${timestamp}",
  "frontmost_app": "${app}",
  "active_url": "${url}",
  "active_tab_title": "${tab_title}",
  "screenshot_path": "${screenshot_path}",
  "webcam_path": "${webcam_path}",
  "rule_classification": "${rule_classification}",
  "llm_classification": "${llm_classification}",
  "llm_confidence": "${llm_confidence}",
  "llm_reason": "${llm_reason}",
  "final_classification": "${final_classification}",
  "idle_seconds": "${idle_seconds}",
  "away_mode": "${away_mode}"
}
EOF
}

cleanup_old_artifacts() {
  find "$CAPTURE_ROOT" -type f -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$RESULT_ROOT" -type f -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
}

main_loop() {
  log "Focus guard started. interval=${INTERVAL_SECONDS}s"
  log "Data root: $DATA_ROOT"
  log "Away threshold: ${AWAY_IDLE_SECONDS}s"
  log "Close streak threshold: ${UNPRODUCTIVE_STREAK_TO_CLOSE}"
  log "Capture saving enabled: ${SAVE_CAPTURES}"
  log "Webcam check interval: ${WEBCAM_CHECK_INTERVAL_SECONDS}s"
  log "Browser LLM check interval: ${BROWSER_LLM_CHECK_INTERVAL_SECONDS}s"
  log "Screen flicker enabled: ${SCREEN_FLICKER_ENABLED}"
  log "Notifications enabled: ${ENABLE_NOTIFICATIONS}"
  log "Streaming site blocking: ${BLOCK_STREAMING_SITES}"

  local alarm_active=0
  local last_alarm_epoch=0
  local last_unproductive_browser_key=""
  local unproductive_streak=0
  local last_webcam_check_epoch=0
  local cached_llm_classification="unknown"
  local cached_llm_confidence="0.0"
  local cached_llm_reason="not_checked_yet"
  local last_browser_llm_check_epoch=0
  local cached_browser_llm_key=""
  local cached_browser_llm_classification="unknown"
  local cached_browser_llm_confidence="0.0"
  local cached_browser_llm_reason="not_checked_yet"

  while true; do
    cleanup_old_artifacts

    local app
    app="$(frontmost_app)"
    local url=""
    local tab_title=""
    if [[ -n "$app" ]] && browser_supported "$app"; then
      url="$(active_tab_url "$app")"
      tab_title="$(active_tab_title "$app")"
    fi

    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local day_key
    day_key="$(date '+%Y-%m-%d')"

    local result_dir="$RESULT_ROOT/$day_key"
    mkdir -p "$result_dir"

    local screenshot_path="capture_disabled"
    local webcam_path="capture_disabled"
    if [[ "$SAVE_CAPTURES" == "1" ]]; then
      local capture_dir="$CAPTURE_ROOT/$day_key"
      mkdir -p "$capture_dir"
      screenshot_path="$capture_dir/${timestamp}-screen.png"
      webcam_path="$capture_dir/${timestamp}-webcam.jpg"
      capture_screenshot "$screenshot_path"
    fi

    local llm_raw_path="$result_dir/${timestamp}-llm.raw.txt"
    local llm_json_path="$result_dir/${timestamp}-llm.json"
    local browser_llm_raw_path="$result_dir/${timestamp}-browser-llm.raw.txt"
    local browser_llm_json_path="$result_dir/${timestamp}-browser-llm.json"
    local result_path="$result_dir/${timestamp}-result.json"

    local idle_seconds
    idle_seconds="$(user_idle_seconds)"

    local now_epoch
    now_epoch="$(date +%s)"

    local llm_classification
    local llm_confidence
    local llm_reason
    local browser_llm_classification="unknown"
    local browser_llm_confidence="0.0"
    local browser_llm_reason="not_browser"

    llm_classification="$cached_llm_classification"
    llm_confidence="$cached_llm_confidence"
    llm_reason="$cached_llm_reason"

    if (( now_epoch - last_webcam_check_epoch >= WEBCAM_CHECK_INTERVAL_SECONDS )); then
      local webcam_input_path="$webcam_path"
      if [[ "$SAVE_CAPTURES" != "1" ]]; then
        webcam_input_path="$DATA_ROOT/tmp/${timestamp}-webcam.jpg"
      fi

      capture_webcam "$webcam_input_path"

      if [[ "$ENABLE_WEBCAM_LLM" == "1" ]] && [[ -s "$webcam_input_path" ]]; then
        run_llm_classification "$webcam_input_path" "$llm_raw_path" "$llm_json_path"
        llm_classification="$(llm_field "$llm_json_path" classification | tr '[:upper:]' '[:lower:]')"
        llm_confidence="$(llm_field "$llm_json_path" confidence)"
        llm_reason="$(llm_field "$llm_json_path" reason)"
      else
        llm_classification="unknown"
        llm_confidence="0.0"
        llm_reason="webcam_unavailable_or_llm_disabled"
      fi

      cached_llm_classification="$llm_classification"
      cached_llm_confidence="$llm_confidence"
      cached_llm_reason="$llm_reason"
      last_webcam_check_epoch="$now_epoch"

      if [[ "$SAVE_CAPTURES" != "1" ]]; then
        rm -f "$webcam_input_path" "$webcam_input_path.unavailable" >/dev/null 2>&1 || true
        webcam_path="capture_disabled"
      fi
    else
      local age=$((now_epoch - last_webcam_check_epoch))
      llm_reason="cached_${age}s:${cached_llm_reason}"
    fi

    if [[ "$ENABLE_BROWSER_LLM" == "1" ]] && [[ -n "$app" ]] && browser_supported "$app" && [[ -n "$url" ]]; then
      local browser_key="${app}|${url}|${tab_title}"
      if [[ "$browser_key" != "$cached_browser_llm_key" ]] || (( now_epoch - last_browser_llm_check_epoch >= BROWSER_LLM_CHECK_INTERVAL_SECONDS )); then
        run_browser_llm_classification "$app" "$url" "$tab_title" "$browser_llm_raw_path" "$browser_llm_json_path"
        browser_llm_classification="$(llm_field "$browser_llm_json_path" classification | tr '[:upper:]' '[:lower:]')"
        browser_llm_confidence="$(llm_field "$browser_llm_json_path" confidence)"
        browser_llm_reason="$(llm_field "$browser_llm_json_path" reason)"
        cached_browser_llm_key="$browser_key"
        cached_browser_llm_classification="$browser_llm_classification"
        cached_browser_llm_confidence="$browser_llm_confidence"
        cached_browser_llm_reason="$browser_llm_reason"
        last_browser_llm_check_epoch="$now_epoch"
      else
        local bage=$((now_epoch - last_browser_llm_check_epoch))
        browser_llm_classification="$cached_browser_llm_classification"
        browser_llm_confidence="$cached_browser_llm_confidence"
        browser_llm_reason="cached_${bage}s:${cached_browser_llm_reason}"
      fi
    fi

    local rule_classification="unknown"
    local away_mode="0"

    if [[ "$BLOCK_STREAMING_SITES" == "1" ]] && [[ -n "$app" ]] && browser_supported "$app" && [[ -n "$url" ]] && is_streaming_url "$url"; then
      rule_classification="unproductive"
    fi

    if [[ "$idle_seconds" =~ ^[0-9]+$ ]] && (( idle_seconds >= AWAY_IDLE_SECONDS )); then
      away_mode="1"
      rule_classification="unproductive"
    fi

    local final_classification="unknown"
    local close_tab_allowed="1"
    local close_reason=""

    if [[ "$rule_classification" == "unproductive" ]]; then
      if [[ "$browser_llm_classification" == "productive" ]]; then
        final_classification="productive"
        close_tab_allowed="0"
        close_reason="browser_llm_override_productive"
      else
        final_classification="unproductive"
      fi
    elif [[ "$llm_classification" == "unproductive" ]]; then
      final_classification="unproductive"
    elif [[ "$llm_classification" == "productive" ]]; then
      final_classification="productive"
    elif [[ -n "$app" ]] && is_known_productive_app "$app"; then
      final_classification="productive"
    else
      final_classification="unknown"
    fi

    if [[ -n "$app" ]] && browser_supported "$app" && [[ -n "$url" ]]; then
      llm_classification="$browser_llm_classification"
      llm_confidence="$browser_llm_confidence"
      llm_reason="$browser_llm_reason"
    fi

    record_result "$result_path" "$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')" "$app" "$url" "$tab_title" "$screenshot_path" "$webcam_path" "$rule_classification" "$llm_classification" "$llm_confidence" "$llm_reason" "$final_classification" "$idle_seconds" "$away_mode"

    if [[ "$final_classification" == "unproductive" ]]; then
      log "Unproductive detected app=$app url=$url title=$tab_title rule=$rule_classification llm=$llm_classification confidence=$llm_confidence idle=${idle_seconds}s away=$away_mode"

      if [[ -n "$app" ]] && browser_supported "$app"; then
        local browser_key="${app}|${url}"
        if [[ "$browser_key" == "$last_unproductive_browser_key" ]]; then
          unproductive_streak=$((unproductive_streak + 1))
        else
          last_unproductive_browser_key="$browser_key"
          unproductive_streak=1
        fi
      else
        unproductive_streak=0
        last_unproductive_browser_key=""
      fi

      if [[ -n "$app" ]] && browser_supported "$app"; then
        if (( unproductive_streak < UNPRODUCTIVE_STREAK_TO_CLOSE )); then
          close_tab_allowed="0"
          close_reason="streak_${unproductive_streak}_below_threshold"
        fi

        if [[ -n "$url" ]] && is_youtube_exploration_url "$url"; then
          close_tab_allowed="0"
          close_reason="youtube_exploration"
        fi
      fi

      local tab_closed_this_cycle=0
      if [[ "$DRY_RUN" != "1" ]] && [[ "$away_mode" != "1" ]] && [[ "$close_tab_allowed" == "1" ]] && [[ -n "$app" ]] && browser_supported "$app"; then
        close_active_tab "$app"
        tab_closed_this_cycle=1
        log "Closed tab app=$app url=$url"
      elif [[ -n "$close_reason" ]]; then
        log "Close deferred app=$app url=$url reason=$close_reason"
      fi

      local should_alert=0
      if [[ "$away_mode" == "1" ]] || [[ "$tab_closed_this_cycle" == "1" ]]; then
        should_alert=1
      fi

      if [[ "$should_alert" == "1" ]]; then
        local now
        now="$(date +%s)"
        if (( now - last_alarm_epoch >= ALARM_REPEAT_SECONDS )); then
          play_focus_feedback
          if [[ "$ENABLE_NOTIFICATIONS" == "1" ]]; then
            if [[ "$away_mode" == "1" ]]; then
              notify_user "Focus Guard" "Away from system (${idle_seconds}s). Return to work."
            else
              notify_user "Focus Guard" "Distraction blocked. Back to focus mode."
            fi
          fi
          last_alarm_epoch="$now"
        fi
        alarm_active=1
      fi
    else
      unproductive_streak=0
      last_unproductive_browser_key=""
      if [[ "$alarm_active" -eq 1 ]] && [[ "$final_classification" == "productive" ]]; then
        log "Focus restored app=$app url=$url"
        notify_user "Focus Restored" "Great. Keep going."
        alarm_active=0
      fi
    fi

    sleep "$INTERVAL_SECONDS"
  done
}

main_loop
