@echo off
rem Deploy game code to the LIVE VDS server (139.100.234.166, UDP 9977 gate /
rem 9978-9980 rooms / 9990 friends) and restart it.
rem !!! The LIVE server plays with the version published in RuStore. Deploy
rem !!! here ONLY the code that matches the published build (same protocol).
rem !!! To check changes use the TEST server: "Обновить тестовый сервер.bat".
rem See server/README.md. Key: Desktop\shift-journal\vps_root_key.
cd /d "%~dp0"
set KEY=%USERPROFILE%\Desktop\shift-journal\vps_root_key

echo ***********************************************************************
echo *  LIVE server = the RuStore version plays here. Players in a race     *
echo *  will be dropped. For testing changes use the TEST server instead.  *
echo *  The previous code is kept on the VDS as /opt/bighead-prev.tgz.     *
echo ***********************************************************************
findstr /n "PROTOCOL :=" scripts\Net.gd
set /p ANSWER=Type YES to deploy this code to the LIVE server:
if /i not "%ANSWER%"=="YES" goto abort

echo === 1/3 Packing code (scripts, scenes, project.godot, assets)...
tar czf "%TEMP%\bhr_code.tgz" scripts scenes project.godot assets
if errorlevel 1 goto fail

echo === 2/3 Uploading to VDS...
scp -i "%KEY%" "%TEMP%\bhr_code.tgz" root@139.100.234.166:/tmp/code.tgz
if errorlevel 1 goto fail

echo === 3/3 Backing up old code, unpacking, importing assets, restarting server...
rem Service is stopped BEFORE --import: on 960 MB RAM a running server next
rem to the import once pushed the VDS into swap for ~20 minutes (2026-08-26).
rem Rolling backup of the previous code (without the import cache):
rem restore = "systemctl stop bighead-server; rm -rf /opt/bighead; mkdir /opt/bighead;
rem tar xzf /opt/bighead-prev.tgz -C /opt; chown -R bighead:bighead /opt/bighead;
rem import as user bighead; systemctl start bighead-server".
ssh -i "%KEY%" root@139.100.234.166 "systemctl stop bighead-server; tar czf /opt/bighead-prev.tgz -C /opt --exclude=bighead/.godot bighead; cd /opt/bighead && tar xzf /tmp/code.tgz && rm /tmp/code.tgz && chown -R bighead:bighead /opt/bighead && sudo -u bighead HOME=/home/bighead godot --headless --path /opt/bighead --import >/dev/null 2>&1; systemctl start bighead-server && sleep 3 && systemctl is-active bighead-server && grep -n 'PROTOCOL :=' /opt/bighead/scripts/Net.gd"
if errorlevel 1 goto fail

echo.
rem The number below must match Net.PROTOCOL in the code you just uploaded.
echo === DONE. LIVE server updated. Expected above: 'active' and the PROTOCOL
echo === number printed before the YES prompt.
pause
exit /b 0

:abort
echo.
echo === Cancelled. Nothing was changed on the VDS.
pause
exit /b 2

:fail
echo.
echo === FAILED. See error above.
pause
exit /b 1
