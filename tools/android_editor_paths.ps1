# Прописывает в настройки редактора Godot 4.7 (%APPDATA%\Godot\editor_settings-4.7.tres)
# пути Android SDK / Java / debug-ключа, без которых экспорт Android падает
# «Требуется указать верный путь к Android SDK». Зовётся из «Собрать боевой APK.bat»
# и «Собрать тестовый APK.bat». Прежний файл сохраняется как .bak_<дата> (раз в день).
$ErrorActionPreference = 'Stop'
$want = [ordered]@{
    'export/android/android_sdk_path'    = '"E:/Android/Sdk"'
    'export/android/java_sdk_path'       = '"C:/Program Files/Android/Android Studio/jbr"'
    'export/android/debug_keystore'      = '"E:/UnityProjects/StaffinBox/Godot/debug.keystore"'
    'export/android/debug_keystore_user' = '"androiddebugkey"'
    'export/android/debug_keystore_pass' = '"android"'
}
$dir = Join-Path $env:APPDATA 'Godot'
$path = Join-Path $dir 'editor_settings-4.7.tres'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (Test-Path $path) {
    $text = [IO.File]::ReadAllText($path, $utf8)
} else {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $text = "[gd_resource type=`"EditorSettings`" format=3]`r`n`r`n[resource]`r`n"
}
$nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
$lines = [Collections.Generic.List[string]]($text -split "`r?`n")
$changed = $false
foreach ($k in $want.Keys) {
    $line = "$k = $($want[$k])"
    $i = -1
    for ($j = 0; $j -lt $lines.Count; $j++) { if ($lines[$j] -like "$k = *") { $i = $j; break } }
    if ($i -ge 0) {
        if ($lines[$i] -ne $line) { $lines[$i] = $line; $changed = $true }
    } else {
        $r = $lines.IndexOf('[resource]')
        if ($r -lt 0) { $lines.Add('[resource]'); $r = $lines.Count - 1 }
        $lines.Insert($r + 1, $line); $changed = $true
    }
}
if ($changed) {
    if (Test-Path $path) {
        $bak = "$path.bak_$(Get-Date -Format yyyy-MM-dd)"
        if (-not (Test-Path $bak)) { Copy-Item $path $bak }
    }
    [IO.File]::WriteAllText($path, ($lines -join $nl), $utf8)
    Write-Host "Пути Android SDK/Java прописаны в $path"
} else {
    Write-Host "Пути Android SDK/Java в настройках Godot уже на месте."
}
