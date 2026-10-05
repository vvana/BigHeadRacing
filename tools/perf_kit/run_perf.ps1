param([string]$Out, [string[]]$Tracks = @('grass','sand','neon','space','snow'), [string]$Method = 'gl_compatibility', [string]$Seconds = '25', [string[]]$Extra = @())
$godot = 'E:\Soft\Godot\Godot_v4.3-stable_win64_console.exe'
$log = 'E:\UnityProjects\BigHeadRacing\tools\perf_kit\perf_log.txt'
foreach ($t in $Tracks) {
    $a = @('--path','E:\UnityProjects\BigHeadRacing','--rendering-method',$Method,'res://tools/MeasurePerf.tscn','--',$Out,$t,$Seconds) + $Extra
    $p = Start-Process $godot -ArgumentList $a -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru
    if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force; "TIMEOUT $t" }
    Get-Content "$log.err" -Encoding UTF8 | Select-String -Pattern 'SCRIPT ERROR|Parse Error' | Select-Object -First 5
}
