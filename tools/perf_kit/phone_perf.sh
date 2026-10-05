#!/bin/bash
# Запуск замерной сборки на телефоне: будит экран, снимает блокировку,
# держит экран включённым и ждёт конца серии; строки PERF — в $1.
ADB=/e/Android/Sdk/platform-tools/adb.exe
OUT=${1:-phone_perf.txt}
PKG=ru.dustandflame.game.perf
$ADB shell input keyevent KEYCODE_WAKEUP
sleep 2
if $ADB shell dumpsys window | grep -q "isKeyguardShowing=true"; then
  $ADB shell input swipe 360 1400 360 300 300; $ADB shell wm dismiss-keyguard
  sleep 1
fi
$ADB shell am force-stop $PKG
$ADB logcat -c
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in $(seq 1 260); do
  sleep 3
  $ADB shell input keyevent KEYCODE_WAKEUP
  $ADB logcat -d -s godot:V 2>/dev/null | grep -a -E "PERF|PROF" > "$OUT"
  if grep -q "PERF-SUITE: конец" "$OUT"; then break; fi
done
$ADB shell dumpsys battery | grep -E 'temperature' >> "$OUT"
$ADB shell am force-stop $PKG
echo DONE >> "$OUT"
