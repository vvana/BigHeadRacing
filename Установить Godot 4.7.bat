@echo off
chcp 65001 >nul
title Установка шаблонов экспорта Godot 4.7.2
cd /d "%~dp0"
rem Кладёт шаблоны экспорта Godot 4.7.2 в ВАШ профиль
rem (%APPDATA%\Godot\export_templates\4.7.2.stable) и прописывает пути Android SDK
rem в настройки редактора 4.7. Нужно один раз: Claude работает в отдельном
rem (контейнерном) профиле и ваш профиль обновить не может. Архив шаблонов —
rem E:\Soft\Godot47\templates.tpz (1,28 ГБ), редактор — E:\Soft\Godot47.

set "TPZ=E:\Soft\Godot47\templates.tpz"
set "DST=%APPDATA%\Godot\export_templates\4.7.2.stable"

if exist "%DST%\version.txt" (
  echo Шаблоны 4.7.2 уже стоят: %DST%
  goto paths
)
if not exist "%TPZ%" (
  echo ОШИБКА: не нашёл архив шаблонов %TPZ%
  pause & exit /b 1
)
echo Распаковываю шаблоны ^(1,3 ГБ, около минуты^)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -A System.IO.Compression.FileSystem; $tmp='%TEMP%\godot47tpl'; if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }; [IO.Compression.ZipFile]::ExtractToDirectory('%TPZ%', $tmp); New-Item -ItemType Directory -Force (Split-Path '%DST%') | Out-Null; Move-Item (Join-Path $tmp 'templates') '%DST%'"
if not exist "%DST%\version.txt" (
  echo ОШИБКА: шаблоны не распаковались.
  pause & exit /b 1
)
echo Готово: %DST%

:paths
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\android_editor_paths.ps1"
echo.
echo Godot 4.7.2 готов к сборкам. Редактор: E:\Soft\Godot47\Godot_v4.7.2-stable_win64.exe
pause
