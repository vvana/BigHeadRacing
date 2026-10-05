Set-Location 'E:\UnityProjects\BigHeadRacing'
$h0 = (Get-FileHash export_presets.cfg).Hash
$apk = 'E:\UnityProjects\BigHeadRacing\tools\perf_kit\perf.apk'
$old = if (Test-Path $apk) { (Get-Item $apk).LastWriteTime } else { [datetime]::MinValue }
py tools\perf_kit\mk_perf_preset.py make
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=E:/UnityProjects/jtmp'
$t0 = Get-Date
$godot = 'E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe'
$p = Start-Process $godot -ArgumentList '--headless','--path','E:\UnityProjects\BigHeadRacing','--export-debug','"Android (perf)"','tools/perf_kit/perf.apk' -RedirectStandardOutput tools\perf_kit\export_log.txt -RedirectStandardError tools\perf_kit\export_log.txt.err -PassThru
$last = -1; $stable = 0
for ($i = 0; $i -lt 100; $i++) {
  Start-Sleep -Seconds 5
  if ($p.HasExited) { break }
  $it = Get-Item $apk -ErrorAction SilentlyContinue
  if ($it -and $it.LastWriteTime -gt $old) { $s = $it.Length; if ($s -gt 0 -and $s -eq $last) { $stable++ } else { $stable = 0 }; $last = $s; if ($stable -ge 3) { break } }
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Get-Process java -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $t0 } | ForEach-Object { Stop-Process -Id $_.Id -Force }
py tools\perf_kit\mk_perf_preset.py restore
"hash same: " + ((Get-FileHash export_presets.cfg).Hash -eq $h0)
Get-Item $apk | Select-Object Name, Length, LastWriteTime
# Ставить на телефон ТОЛЬКО из Bash (adb из PowerShell сбивает авторизацию): adb install -r tools/perf_kit/perf.apk
