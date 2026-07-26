# MOM FocusGuard

MOM FocusGuard is a local-first productivity enforcement toolkit that blocks distraction loops with lightweight monitoring and intervention.

This repository is designed as a production-focused project with:
- production-oriented scripts
- cross-platform support in one repo
- privacy-first defaults (no cloud APIs)
- clear architecture and setup documentation

## Key Features

- Local-only execution by default
- Distraction enforcement with tab/window close rules
- Away-from-system detection
- Lightweight mode for low CPU usage
- Sound + screen-flicker alerts
- Platform-specific launch/daemon setup

## Privacy Model

- No data is sent to internet endpoints by default.
- Capture persistence is disabled by default on macOS.
- Optional local artifacts are kept under platform-specific app-data paths.

## Repository Layout

```text
MOM/
  Models/
    Qwen2.5-0.5B-Instruct-Q4_K_M.gguf
  scripts/
    focus_guard.sh
    focus_guard.launchd.plist
    install_focus_guard.sh
  platforms/
    windows/
      focus_guard.ps1
      install_focus_guard.ps1
    android/
      adb_focus_guard.sh
      install_android_guard.sh
  config/
    focus_guard.env.example
  docs/
    architecture.md
    setup-macos.md
    setup-windows.md
    setup-android.md
    troubleshooting.md
```

## Platform Support

| Platform | Status | Runtime |
|---|---|---|
| macOS | Working | launchd + Bash |
| Windows | Working | PowerShell + Task Scheduler |
| Android | Working (ADB mode) | Bash + adb shell |

Android support is implemented via ADB (USB or wireless debugging) from a desktop host. This enables reproducible setup without requiring a custom APK.

## Quick Start

### 1) macOS

```bash
cd scripts
./install_focus_guard.sh
launchctl list | grep com.mom.focusguard
```

### 2) Windows (PowerShell as Administrator)

```powershell
cd platforms/windows
.\install_focus_guard.ps1
Get-ScheduledTask -TaskName MOMFocusGuard
```

### 3) Android (ADB mode, from macOS/Linux shell)

```bash
cd platforms/android
./install_android_guard.sh
./adb_focus_guard.sh
```

## Configuration

Use `config/focus_guard.env.example` as the base for tuning:
- enforcement aggressiveness
- check intervals
- blocked streaming patterns
- alert behavior

## Demo And Validation Flow

1. Start service.
2. Open a productive page and show no intervention.
3. Open YouTube watch / Hotstar / Netflix page and show block + alert.
4. Simulate away mode and show alert behavior.
5. Show logs and explain low-CPU design decisions.

## Engineering Highlights

- Lock-based singleton process control
- Configurable alert throttling
- Streak-based closure to reduce false positives
- Lightweight classification cadence with caching
- Separation of platform-specific launcher/install logic

## Roadmap

- Optional vision-capable local model path
- Optional local dashboard UI for logs and controls
- Optional policy packs by user profile (student, engineer, founder)

## License

MIT (see `LICENSE`).
