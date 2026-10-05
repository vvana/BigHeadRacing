@echo off
chcp 65001 >nul
title Подпись APK для RuStore
cd /d "%~dp0"
rem Подписывает собранный релизный APK ключом dustflame и сразу проверяет
rem подпись. JAVA_HOME задаётся здесь же (у apksigner своей Java нет).
rem Имя итогового файла содержит версию: dist\DustAndFlame-<версия>-release.apk
rem (версия и код — из пресета "Android" в export_presets.cfg). Прежние релизы
rem лежат рядом: DustAndFlame-1.1.0-release.apk, ...

set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "APKSIGNER=E:\Android\Sdk\build-tools\34.0.0\apksigner.bat"
set "KS=E:\UnityProjects\dustflame.keystore"
set "IN=%~dp0dist\DustAndFlame-unsigned.apk"
rem Версия и код — первые version/name и version/code в export_presets.cfg
rem (пресет "Android" идёт раньше "Android (test)").
set "VER="
set "CODE="
for /f "tokens=2 delims==" %%V in ('findstr /b /c:"version/name=" "%~dp0export_presets.cfg"') do if not defined VER set "VER=%%~V"
for /f "tokens=2 delims==" %%C in ('findstr /b /c:"version/code=" "%~dp0export_presets.cfg"') do if not defined CODE set "CODE=%%C"
if not defined VER (
  echo ОШИБКА: не нашёл version/name в export_presets.cfg
  pause & exit /b 1
)
set "OUT=%~dp0dist\DustAndFlame-%VER%-release.apk"

if not exist "%JAVA_HOME%\bin\java.exe" (
  echo ОШИБКА: не нашёл Java по пути %JAVA_HOME%
  echo Открой этот .bat блокнотом и поправь строку set "JAVA_HOME=..."
  pause & exit /b 1
)
if not exist "%APKSIGNER%" (
  echo ОШИБКА: не нашёл apksigner: %APKSIGNER%
  pause & exit /b 1
)
if not exist "%KS%" (
  echo ОШИБКА: не нашёл хранилище ключей: %KS%
  pause & exit /b 1
)
if not exist "%IN%" (
  echo ОШИБКА: нет собранного APK: %IN%
  echo Сначала нужно собрать релиз ^(пресет "Android"^).
  pause & exit /b 1
)

echo === Подписываю сборку:
for %%F in ("%IN%") do echo     %%~nxF   %%~zF байт   %%~tF
echo.
echo Сейчас спросит ПАРОЛЬ от хранилища dustflame.keystore.
echo Пароль вводится вслепую: символы не видны, набери и нажми Enter.
echo Если потом спросит "Key password for signer #1" - тот же пароль
echo или просто Enter, если он совпадает с паролем хранилища.
echo.
call "%APKSIGNER%" sign --ks "%KS%" --ks-key-alias dustflame --out "%OUT%" "%IN%"
if errorlevel 1 (
  echo.
  echo === НЕ ПОДПИСАЛОСЬ. Причина выше ^(чаще всего неверный пароль^).
  echo Прежний подписанный файл не тронут.
  pause & exit /b 1
)

echo.
echo === Проверяю подпись ^(ожидается CN=Andrei Sukhoverkhov^):
call "%APKSIGNER%" verify --print-certs "%OUT%"
echo.
echo === ГОТОВО. В RuStore грузить файл:
echo     %OUT%
echo     версия %VER%, код %CODE%
pause
