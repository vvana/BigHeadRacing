@echo off
rem Deploy the WORKING COPY (current code) to the TEST server on the VDS
rem (139.100.234.166, UDP 9877 gate / 9878-9880 rooms / 9890 friends) and
rem restart it. The LIVE server (/opt/bighead, ports 9977/9990) plays the
rem RuStore version and is NOT touched here - that one is updated by
rem "Обновить сервер.bat" (only when a new store build is published).
rem Test builds (presets "... (test)", play.bat) talk to this server.
rem See server/README.md. Key: Desktop\shift-journal\vps_root_key.
cd /d "%~dp0"
set KEY=%USERPROFILE%\Desktop\shift-journal\vps_root_key
set DIR=/opt/bighead-test
set SVC=bighead-test
set USR=bighead-test

echo === 1/3 Packing code (scripts, scenes, project.godot, assets)...
tar czf "%TEMP%\bhr_test_code.tgz" scripts scenes project.godot assets
if errorlevel 1 goto fail

echo === 2/3 Uploading to VDS...
scp -i "%KEY%" "%TEMP%\bhr_test_code.tgz" root@139.100.234.166:/tmp/code_test.tgz
if errorlevel 1 goto fail

echo === 3/3 Unpacking, importing assets, restarting TEST server...
rem The live server keeps running meanwhile; --import only re-imports
rem changed assets (cache in %DIR%/.godot), so it is light unless a big
rem asset pack was added - then expect a minute or two of swap.
ssh -i "%KEY%" root@139.100.234.166 "systemctl stop %SVC%; cd %DIR% && tar xzf /tmp/code_test.tgz && rm /tmp/code_test.tgz && chown -R %USR%:%USR% %DIR% && sudo -u %USR% HOME=/home/%USR% godot --headless --path %DIR% --import >/dev/null 2>&1; systemctl start %SVC% && sleep 3 && systemctl is-active %SVC% && grep -n 'PROTOCOL :=' %DIR%/scripts/Net.gd && ss -lun | grep -E ':(9877|9890) '"
if errorlevel 1 goto fail

echo.
echo === DONE. TEST server updated. Expected above: 'active', the PROTOCOL
echo === number of the code you just uploaded, and two UDP sockets 9877/9890.
pause
exit /b 0

:fail
echo.
echo === FAILED. See error above.
pause
exit /b 1
