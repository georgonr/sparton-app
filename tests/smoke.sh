#!/usr/bin/env bash
# Spúšťa sa v emulátore (android-emulator-runner): inštalácia debug APK, nastavenie zariadenia, smoke test, logcat.
set -uo pipefail
mkdir -p smoke-out
adb wait-for-device
adb shell settings put global window_animation_scale 0 || true
adb shell settings put system screen_off_timeout 1800000 || true
# čistý stavový riadok na snímkach (režim ukážky: 9:41, plná batéria a signál)
adb shell settings put global sysui_demo_allowed 1 || true
adb shell am broadcast -a com.android.systemui.demo -e command enter || true
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 || true
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile show -e datatype none -e level 4 || true
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false || true
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb logcat -c || true
node tests/smoke.mjs
code=$?
adb shell am broadcast -a com.android.systemui.demo -e command exit || true
adb logcat -d -v time | grep -E "eu\.sparton|Capacitor|chromium|AndroidRuntime|FirebaseMessaging" | grep -viE "password|heslo|token=" > smoke-out/logcat.txt || true
exit $code
