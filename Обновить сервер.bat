@echo off
rem Deploy game code to the VDS server (139.100.234.166) and restart it.
rem See server/README.md. Key: Desktop\shift-journal\vps_root_key.
cd /d "%~dp0"
set KEY=%USERPROFILE%\Desktop\shift-journal\vps_root_key

echo === 1/3 Packing code (scripts, scenes, project.godot, assets)...
tar czf "%TEMP%\bhr_code.tgz" scripts scenes project.godot assets
if errorlevel 1 goto fail

echo === 2/3 Uploading to VDS...
scp -i "%KEY%" "%TEMP%\bhr_code.tgz" root@139.100.234.166:/tmp/code.tgz
if errorlevel 1 goto fail

echo === 3/3 Unpacking, importing assets, restarting server...
rem Service is stopped BEFORE --import: on 960 MB RAM a running server next
rem to the import once pushed the VDS into swap for ~20 minutes (2026-08-26).
ssh -i "%KEY%" root@139.100.234.166 "systemctl stop bighead-server; cd /opt/bighead && tar xzf /tmp/code.tgz && rm /tmp/code.tgz && chown -R bighead:bighead /opt/bighead && sudo -u bighead HOME=/home/bighead godot --headless --path /opt/bighead --import >/dev/null 2>&1; systemctl start bighead-server && sleep 3 && systemctl is-active bighead-server && grep -n 'PROTOCOL :=' /opt/bighead/scripts/Net.gd"
if errorlevel 1 goto fail

echo.
rem The number below must match Net.PROTOCOL in the code you just uploaded.
echo === DONE. Server updated. Expected above: 'active' and 'PROTOCOL := 10'.
pause
exit /b 0

:fail
echo.
echo === FAILED. See error above.
pause
exit /b 1
