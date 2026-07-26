# Setup: Windows

## Prerequisites

- Windows 10/11
- PowerShell 5.1+
- Optional: BurntToast module for rich notifications

## Install

Open PowerShell as Administrator:

```powershell
cd platforms/windows
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install_focus_guard.ps1
```

## Verify

```powershell
Get-ScheduledTask -TaskName MOMFocusGuard
Get-Process -Name powershell | Select-Object -First 5
```

## Stop

```powershell
Unregister-ScheduledTask -TaskName MOMFocusGuard -Confirm:$false
```

## Notes

- Uses active window title + browser process checks.
- Uses low-overhead loop and alert throttling.
