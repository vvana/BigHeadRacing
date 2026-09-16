@echo off
chcp 65001 >nul
title Подпись APK для RuStore
cd /d "%~dp0"
rem Подписывает собранный релизный APK ключом dustflame и сразу проверяет
rem подпись. JAVA_HOME задаётся здесь же (у apksigner своей Java нет).
rem Прежний релиз 1.1.0 лежит рядом: DustAndFlame-release-1.1.0.apk

set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "APKSIGNER=E:\Android\Sdk\build-tools\34.0.0\apksigner.bat"
set "KS=E:\UnityProjects\dustflame.keystore"
set "IN=%~dp0dist\DustAndFlame-unsigned.apk"
set "OUT=%~dp0dist\DustAndFlame-release.apk"

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
  echo Прежний DustAndFlame-release.apk не тронут.
  pause & exit /b 1
)

echo.
echo === Проверяю подпись ^(ожидается CN=Andrei Sukhoverkhov^):
call "%APKSIGNER%" verify --print-certs "%OUT%"
echo.
echo === ГОТОВО. В RuStore грузить файл:
echo     %OUT%
echo     версия 1.1.1, код 4
pause
