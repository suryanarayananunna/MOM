# Setup: Android (ADB Mode)

## Model

This repo provides Android support via an ADB-connected host machine.

- No APK required.
- Works with USB or wireless debugging.
- Monitors foreground Android package and enforces with HOME key action.

## Prerequisites

- Android device with Developer Options enabled
- USB debugging enabled
- `adb` installed on host machine

## Install and Run

```bash
cd platforms/android
chmod +x install_android_guard.sh adb_focus_guard.sh
./install_android_guard.sh
./adb_focus_guard.sh
```

## Verify Device

```bash
adb devices
adb shell getprop ro.product.model
```

## Stop

Press `Ctrl+C` in the terminal running `adb_focus_guard.sh`.
