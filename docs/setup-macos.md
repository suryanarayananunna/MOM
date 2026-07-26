# Setup: macOS

## Prerequisites

- macOS 13+
- Bash/Zsh
- `launchctl`
- Optional: `imagesnap`
- Optional: `llama-cli` and local model file

## Install

```bash
cd scripts
chmod +x install_focus_guard.sh focus_guard.sh
./install_focus_guard.sh
```

## Verify

```bash
launchctl list | grep com.mom.focusguard
ps -axo pid,command | grep focus_guard.sh | grep -v grep
```

## Runtime Logs

- `~/Library/Application Support/MOMFocusGuard/logs/focus_guard.runtime.log`
- `~/Library/Application Support/MOMFocusGuard/logs/focus_guard.error.log`

## Stop

```bash
launchctl unload ~/Library/LaunchAgents/com.mom.focusguard.plist
```
