# Troubleshooting

## Service appears running but no blocking occurs

- Confirm latest runtime logs.
- Confirm block rules are enabled in configuration.
- Confirm the app/site matches a policy pattern.

## macOS screenshot capture unavailable

- Grant Screen Recording permission.
- Restart terminal and reload launch agent.

## High CPU usage

- Increase webcam/model check interval.
- Disable spoken alerts.
- Disable capture persistence.
- Lower model threads.

## Windows notifications not visible

- Install BurntToast module.
- Ensure notifications are enabled in system settings.

## Android ADB script not detecting device

- Run `adb devices` and accept trust prompt on phone.
- Reconnect cable or restart adb server:

```bash
adb kill-server
adb start-server
adb devices
```
