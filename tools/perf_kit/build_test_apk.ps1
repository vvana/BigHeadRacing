# Сборка ТЕСТОВОГО APK из оболочки Claude (то же, что «Собрать тестовый APK.bat»,
# но с обходом ограничений контейнера: JAVA_TOOL_OPTIONS, Godot после экспорта
# не выходит сам — гасим его и демон gradle). Результат: dist\test\DustAndFlame.apk.
# Ставить на телефон ТОЛЬКО из Bash: adb install -r dist/test/DustAndFlame.apk
Set-Location 'E:\UnityProjects\BigHeadRacing'
$h0 = (Get-FileHash export_presets.cfg).Hash
$apk = 'E:\UnityProjects\BigHeadRacing\dist\test\DustAndFlame.apk'
$old = if (Test-Path $apk) { (Get-Item $apk).LastWriteTime } else { [datetime]::MinValue }
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=E:/UnityProjects/jtmp'
$t0 = Get-Date
$godot = 'E:\Soft\Godot47\Godot_v4.7.2-stable_win64_console.exe'
$p = Start-Process $godot -ArgumentList '--headless','--path','E:\UnityProjects\BigHeadRacing','--export-debug','"Android (test)"','dist/test/DustAndFlame.apk' -RedirectStandardOutput tools\perf_kit\export_log.txt -RedirectStandardError tools\perf_kit\export_log.err -PassThru
$last = -1; $stable = 0
for ($i = 0; $i -lt 100; $i++) {
  Start-Sleep -Seconds 5
  if ($p.HasExited) { break }
  $it = Get-Item $apk -ErrorAction SilentlyContinue
  if ($it -and $it.LastWriteTime -gt $old) { $s = $it.Length; if ($s -gt 0 -and $s -eq $last) { $stable++ } else { $stable = 0 }; $last = $s; if ($stable -ge 3) { break } }
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Get-Process java -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $t0 } | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Item $apk | Select-Object Name, Length, LastWriteTime
"export_presets.cfg не тронут: " + ((Get-FileHash export_presets.cfg).Hash -eq $h0)
Get-Content tools\perf_kit\export_log.err -Encoding UTF8 | Select-String 'SCRIPT ERROR|Parse Error' | Select-Object -First 5
