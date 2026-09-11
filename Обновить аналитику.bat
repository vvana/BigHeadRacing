@echo off
rem Deploy the analytics web panel (server/metrics) to the VDS and restart it.
rem See server/metrics/README.md. Key: Desktop\shift-journalps_root_key.
cd /d "%~dp0"
set KEY=%USERPROFILE%\Desktop\shift-journalps_root_key

echo === 1/3 Uploading server.js and unit file...
scp -i "%KEY%" server\metrics\server.js root@139.100.234.166:/tmp/bhr-server.js
if errorlevel 1 goto fail
scp -i "%KEY%" server\metricshr-metrics.service root@139.100.234.166:/tmp/bhr-metrics.service
if errorlevel 1 goto fail

echo === 2/3 Installing to /opt/bhr-metrics...
ssh -i "%KEY%" root@139.100.234.166 "mkdir -p /opt/bhr-metrics/data && mv /tmp/bhr-server.js /opt/bhr-metrics/server.js && mv /tmp/bhr-metrics.service /etc/systemd/system/bhr-metrics.service && chown -R bighead:bighead /opt/bhr-metrics && systemctl daemon-reload && systemctl enable bhr-metrics >/dev/null 2>&1; systemctl restart bhr-metrics"
if errorlevel 1 goto fail

echo === 3/3 Checking...
ssh -i "%KEY%" root@139.100.234.166 "sleep 2; systemctl is-active bhr-metrics && curl -s -m 5 http://127.0.0.1:8090/healthz && echo. && grep -o '\"token\": \"[^\"]*\"' /opt/bhr-metrics/config.json"
if errorlevel 1 goto fail

echo.
echo === DONE. Panel: http://139.100.234.166:8090/?k=TOKEN (token printed above).
pause
exit /b 0

:fail
echo.
echo === FAILED. See error above.
pause
exit /b 1
