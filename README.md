# MOM FocusGuard

MOM FocusGuard helps people break distraction loops while working.

It is built for people who keep drifting into social media, streaming, or endless scrolling during work/study sessions. The project watches activity, detects unproductive patterns, and nudges you back into focus.

## What Problem This Solves

- Frequent context switching between work and entertainment.
- Losing long blocks of focused time.
- Needing a lightweight, local-first guardrail instead of a heavy app.

## What This Repo Does

- Detects distraction activity (for example streaming/social browsing).
- Detects away-from-system behavior.
- Enforces focus rules (close tab, play sound, visual alert).
- Runs in the background with low resource usage.
- Supports macOS, Windows, and Android (ADB mode) in one repository.

## Privacy And Offline Use

- Local-first by default.
- No cloud API calls are required for core behavior.
- Works without internet for monitoring/enforcement logic.
- Capture persistence is disabled by default on macOS.

## Platform Support

| Platform | Status | Runtime |
|---|---|---|
| macOS | Working | launchd + shell script |
| Windows | Working | PowerShell + Task Scheduler |
| Android | Working (ADB mode) | Host script + adb |

## Quick Setup

### macOS

```bash
cd scripts
./install_focus_guard.sh
launchctl list | grep com.mom.focusguard
```

### Windows (PowerShell as Administrator)

```powershell
cd platforms/windows
.\install_focus_guard.ps1
Get-ScheduledTask -TaskName MOMFocusGuard
```

### Android (ADB mode from host machine)

```bash
cd platforms/android
./install_android_guard.sh
./adb_focus_guard.sh
```

## Configuration

Start from `config/focus_guard.env.example`.

Main things you can tune:
- check intervals
- away detection threshold
- blocked site/app patterns
- alert style and strictness

## Repository Structure

```text
MOM/
  scripts/             # macOS runtime + installer
  platforms/windows/   # Windows runtime + installer
  platforms/android/   # Android ADB runtime + installer
  config/              # env examples and defaults
  docs/                # setup and troubleshooting guides
  Models/              # local model files (kept local, not pushed)
```

## Recommended Reading

- `docs/setup-macos.md`
- `docs/setup-windows.md`
- `docs/setup-android.md`
- `docs/troubleshooting.md`

## License

MIT (see `LICENSE`).
