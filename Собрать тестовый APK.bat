@echo off
chcp 65001 >nul
title Сборка тестового APK (gradle, реклама Yandex)
cd /d "%~dp0"
rem Собирает ТЕСТОВЫЙ APK (пресет "Android (test)": тестовый сервер 9877,
rem демо-блоки рекламы Яндекса) gradle-сборкой Godot — с 23.09.2026 только
rem так: плагин Yandex Mobile Ads (addons/GodotAndroidYandexAds) подтягивает
rem SDK через gradle. Первый запуск качает gradle и библиотеки (5-15 минут,
rem нужен интернет). Результат: dist\test\DustAndFlame.apk (подписан
rem debug-ключом, ставится на телефон как есть).
rem Боевой APK для RuStore: пресет "Android" (--export-release ... dist\DustAndFlame-unsigned.apk),
rem потом "Подписать APK.bat".

set "GODOT=E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "GRADLE_OPTS=-Djava.net.preferIPv4Stack=true"

if not exist "%GODOT%" (
  echo ОШИБКА: не нашёл Godot: %GODOT%
  pause & exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\android_editor_paths.ps1"
echo Импорт ресурсов...
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1
echo Сборка APK (gradle)...
"%GODOT%" --headless --path "%~dp0." --export-debug "Android (test)" dist/test/DustAndFlame.apk 2>&1 | findstr /V /C:"Parameter \"m\" is null" /C:"mesh_get_surface_count"
if exist "%~dp0dist\test\DustAndFlame.apk" (
  echo.
  echo Готово: dist\test\DustAndFlame.apk
  for %%F in ("%~dp0dist\test\DustAndFlame.apk") do echo Размер: %%~zF байт, время: %%~tF
) else (
  echo.
  echo ОШИБКА: APK не собрался — смотри вывод выше.
)
pause
