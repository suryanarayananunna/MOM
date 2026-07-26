param(
  [int]$CheckIntervalSeconds = 5,
  [int]$AlertRepeatSeconds = 10,
  [int]$StreakToClose = 3,
  [string[]]$BlockedKeywords = @('youtube', 'netflix', 'hotstar', 'prime video', 'disney+', 'twitch')
)

$ErrorActionPreference = 'SilentlyContinue'
$script:LastAlert = Get-Date '2000-01-01'
$script:Streak = 0
$script:LastTitle = ''
$script:LastPid = 0

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class NativeWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

function Get-ActiveWindowInfo {
  $h = [NativeWin]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return $null }

  $sb = New-Object System.Text.StringBuilder 1024
  [void][NativeWin]::GetWindowText($h, $sb, $sb.Capacity)
  [uint32]$pid = 0
  [void][NativeWin]::GetWindowThreadProcessId($h, [ref]$pid)

  if ($pid -eq 0) { return $null }
  $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
  if (-not $proc) { return $null }

  [pscustomobject]@{
    Handle = $h
    Title = ($sb.ToString())
    Pid = [int]$pid
    ProcessName = $proc.ProcessName
  }
}

function Is-BrowserProcess([string]$name) {
  $n = $name.ToLowerInvariant()
  return @('msedge','chrome','firefox','brave','arc') -contains $n
}

function Is-BlockedByTitle([string]$title) {
  $t = $title.ToLowerInvariant()
  foreach ($k in $BlockedKeywords) {
    if ($t.Contains($k.ToLowerInvariant())) { return $true }
  }
  return $false
}

function Show-Alert {
  [console]::Beep(900, 180)
  [console]::Beep(1100, 180)

  if (Get-Module -ListAvailable -Name BurntToast) {
    try {
      Import-Module BurntToast -ErrorAction SilentlyContinue | Out-Null
      New-BurntToastNotification -Text 'MOM FocusGuard', 'Distraction blocked. Back to focus mode.' | Out-Null
    } catch {
      Write-Host 'Alert: Distraction blocked.'
    }
  } else {
    Write-Host 'Alert: Distraction blocked.'
  }
}

function Close-CurrentTab {
  $shell = New-Object -ComObject WScript.Shell
  $shell.SendKeys('^w')
}

Write-Host "[MOM] FocusGuard Windows started. Interval=${CheckIntervalSeconds}s"

while ($true) {
  $w = Get-ActiveWindowInfo
  if ($null -ne $w -and (Is-BrowserProcess $w.ProcessName) -and (Is-BlockedByTitle $w.Title)) {
    $key = "{0}|{1}" -f $w.Pid, $w.Title
    if ($key -eq ("{0}|{1}" -f $script:LastPid, $script:LastTitle)) {
      $script:Streak += 1
    } else {
      $script:Streak = 1
      $script:LastPid = $w.Pid
      $script:LastTitle = $w.Title
    }

    if ($script:Streak -ge $StreakToClose) {
      Close-CurrentTab
      $now = Get-Date
      if (($now - $script:LastAlert).TotalSeconds -ge $AlertRepeatSeconds) {
        Show-Alert
        $script:LastAlert = $now
      }
    }
  } else {
    $script:Streak = 0
    $script:LastTitle = ''
    $script:LastPid = 0
  }

  Start-Sleep -Seconds $CheckIntervalSeconds
}
