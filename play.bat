@echo off
chcp 65001 >nul
set "GODOT_DIR=E:\Soft\Godot47"
set "PROJ=E:\UnityProjects\BigHeadRacing"
rem Новые картинки и модели из чужих коммитов приходят неимпортированными, а
rem игра без редактора их не импортирует и рисует белым (16.10.2026). Импорт
rem без новых файлов ~4 с; дольше 5 минут - прервать и всё равно запустить.
echo Проверка новых ресурсов...
powershell -NoProfile -Command "$p = Start-Process '%GODOT_DIR%\Godot_v4.7.2-stable_win64_console.exe' -ArgumentList '--headless','--path','%PROJ%','--import' -WindowStyle Hidden -PassThru; if (-not $p.WaitForExit(300000)) { $p.Kill() }"
start "" "%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe" --path "%PROJ%"
