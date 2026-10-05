param([string[]]$Tests)
# Прогон headless-стендов подряд: последняя строка с PASS/FAIL каждого.
$godot = 'E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe'
$d = 'E:\UnityProjects\BigHeadRacing\tools\shots_dbg'
foreach ($t in $Tests) {
    $p = Start-Process $godot -ArgumentList '--headless','--path','E:\UnityProjects\BigHeadRacing',"res://tools/$t.tscn" -RedirectStandardOutput "$d\t_$t.txt" -RedirectStandardError "$d\t_$t.err" -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(240000)) { Stop-Process -Id $p.Id -Force; "$t : TIMEOUT" }
    $v = Get-Content "$d\t_$t.txt" -Encoding UTF8 | Select-String 'PASS|FAIL' | Select-Object -Last 2
    "$t : " + (($v | ForEach-Object { $_.Line }) -join ' || ')
    Get-Content "$d\t_$t.err" -Encoding UTF8 | Select-String 'SCRIPT ERROR|Parse Error' | Select-Object -First 2
}
