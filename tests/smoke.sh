#!/usr/bin/env bash
# Spúšťa sa v emulátore (android-emulator-runner): inštalácia debug APK, nastavenie zariadenia, smoke test, logcat.
set -uo pipefail
mkdir -p smoke-out
adb wait-for-device
# jazyk zariadenia (Accept-Language webview) – reštart frameworku a počkanie, kým systém odpovedá
LOCALE="${LOCALE:-sk-SK}"
if [ "$(adb shell getprop persist.sys.locale | tr -d '\r')" != "$LOCALE" ]; then
  adb shell setprop persist.sys.locale "$LOCALE"
  adb shell setprop ctl.restart zygote
  sleep 15
  for i in $(seq 1 60); do
    if adb shell cmd package list packages >/dev/null 2>&1 && [ -n "$(adb shell pidof com.android.systemui | tr -d '\r')" ]; then break; fi
    sleep 3
  done
  sleep 15
fi
adb shell wm dismiss-keyguard || true
adb shell input keyevent 82 || true
echo "jazyk: $(adb shell getprop persist.sys.locale | tr -d '\r')"
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
