param([string]$Scene, [string[]]$Extra = @())
$godot = 'E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe'
$d = 'E:\UnityProjects\BigHeadRacing\tools\shots_dbg'
$a = @('--path','E:\UnityProjects\BigHeadRacing',"res://tools/$Scene.tscn",'--','E:/UnityProjects/BigHeadRacing/tools/shots_dbg') + $Extra
$p = Start-Process $godot -ArgumentList $a -RedirectStandardOutput "$d\s.txt" -RedirectStandardError "$d\s.err" -PassThru
if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force; 'TIMEOUT' }
Get-Content "$d\s.txt" -Encoding UTF8 | Select-String 'SHOT|\[gfx\]|TEST' | Select-Object -First 12
Get-Content "$d\s.err" -Encoding UTF8 | Select-String 'SCRIPT ERROR|Parse Error' | Select-Object -First 8
