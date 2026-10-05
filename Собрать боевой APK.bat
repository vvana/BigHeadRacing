@echo off
chcp 65001 >nul
title Сборка боевого APK для RuStore (gradle, реклама Yandex)
cd /d "%~dp0"
rem Боевой APK для RuStore: пресет "Android" (боевой сервер 9977, настоящий
rem блок рекламы R-M-20093870-2). Godot собирает его gradle-сборкой
rem НЕПОДПИСАННЫМ (у пресета package/signed=false: пароля от ключа Godot не знает),
rem затем вызывается "Подписать APK.bat" (ключ dustflame, спросит пароль).
rem Итог: dist\DustAndFlame-release.apk. Версию (version/code, version/name)
rem менять в export_presets.cfg и config/version в project.godot.

set "GODOT=E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "GRADLE_OPTS=-Djava.net.preferIPv4Stack=true"
set "OUT=%~dp0dist\DustAndFlame-unsigned.apk"

if not exist "%GODOT%" (
  echo ОШИБКА: не нашёл Godot: %GODOT%
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\android_editor_paths.ps1"
if exist "%OUT%" del "%OUT%"
echo Импорт ресурсов...
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1
echo Сборка боевого APK (gradle, при первом запуске 5-15 минут)...
rem Полный вывод сборки пишется в dist\build_log.txt (его читает Claude).
"%GODOT%" --headless --path "%~dp0." --export-release "Android" dist/DustAndFlame-unsigned.apk > "%~dp0dist\build_log.txt" 2>&1
findstr /V /C:"Parameter \"m\" is null" /C:"mesh_get_surface_count" "%~dp0dist\build_log.txt"
if not exist "%OUT%" (
  echo.
  echo ОШИБКА: APK не собрался, смотри вывод выше.
  echo Полный вывод сохранён в dist\build_log.txt - скажи Claude, он его прочитает.
  pause
  exit /b 1
)
for %%F in ("%OUT%") do echo Собран: %%~nxF  %%~zF байт  %%~tF
echo.
echo Теперь подпись ключом dustflame.
call "%~dp0Подписать APK.bat"
