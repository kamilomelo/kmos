# Runs once per account at sign-in; never resets a later personal font choice.
$ErrorActionPreference = 'Stop'
$marker = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font-applied'
if (Test-Path -LiteralPath $marker -PathType Leaf) { return }
$package = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue
$paths = @()
if ($package) {
    $paths += (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
}
$unpackaged = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
if (Test-Path -LiteralPath $unpackaged -PathType Leaf) { $paths += $unpackaged }
if (-not $paths.Count) { throw 'Windows Terminal is not registered for this account; retry at next sign-in.' }

foreach ($path in $paths) {
    $dir = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $original = if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::ReadAllText($path) } else { '{}' }
    # Windows Terminal uses JSON with comments and trailing commas. Strip them
    # only for parsing; back up the original before writing a valid JSON merge.
    $clean = New-Object System.Text.StringBuilder
    $quoted = $false; $escaped = $false; $lineComment = $false; $blockComment = $false
    for ($i = 0; $i -lt $original.Length; $i++) {
        $c = $original[$i]
        $next = if ($i + 1 -lt $original.Length) { $original[$i + 1] } else { [char]0 }
        if ($lineComment) {
            if ($c -eq "`n" -or $c -eq "`r") { $lineComment = $false; [void]$clean.Append($c) }
            continue
        }
        if ($blockComment) {
            if ($c -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }
            continue
        }
        if ($quoted) {
            [void]$clean.Append($c)
            if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
            continue
        }
        if ($c -eq '"') { $quoted = $true; [void]$clean.Append($c); continue }
        if ($c -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
        [void]$clean.Append($c)
    }
    if ($quoted -or $blockComment) { throw "Unterminated JSON string/comment: $path" }
    $stripped = $clean.ToString()
    $clean = New-Object System.Text.StringBuilder
    $quoted = $false; $escaped = $false
    for ($i = 0; $i -lt $stripped.Length; $i++) {
        $c = $stripped[$i]
        if ($quoted) {
            [void]$clean.Append($c)
            if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
            continue
        }
        if ($c -eq '"') { $quoted = $true; [void]$clean.Append($c); continue }
        if ($c -eq ',') {
            $j = $i + 1
            while ($j -lt $stripped.Length -and [char]::IsWhiteSpace($stripped[$j])) { $j++ }
            if ($j -lt $stripped.Length -and $stripped[$j] -in @('}', ']')) { continue }
        }
        [void]$clean.Append($c)
    }
    $json = $clean.ToString()
    try { $settings = ConvertFrom-Json -InputObject $json -ErrorAction Stop } catch { throw "Cannot parse Terminal settings $path : $_" }
    if (-not $settings -or $settings -isnot [pscustomobject]) { throw "Unexpected Terminal settings shape: $path" }
    if (-not $settings.PSObject.Properties['profiles']) { $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
    if ($settings.profiles -isnot [pscustomobject]) { throw "Unexpected profiles shape: $path" }
    if (-not $settings.profiles.PSObject.Properties['defaults']) { $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
    if ($settings.profiles.defaults -isnot [pscustomobject]) { throw "Unexpected defaults shape: $path" }
    if (-not $settings.profiles.defaults.PSObject.Properties['font']) { $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }
    if ($settings.profiles.defaults.font -isnot [pscustomobject]) { throw "Unexpected font shape: $path" }
    $font = $settings.profiles.defaults.font
    if ($font.PSObject.Properties['face']) { $font.face = 'Kappa Mono' } else { $font | Add-Member -NotePropertyName face -NotePropertyValue 'Kappa Mono' }
    if ($font.PSObject.Properties['size']) { $font.size = 12 } else { $font | Add-Member -NotePropertyName size -NotePropertyValue 12 }
    # Old fontFace/fontSize would override the modern font object in some builds.
    foreach ($old in @('fontFace','fontSize')) { if ($settings.profiles.defaults.PSObject.Properties[$old]) { $settings.profiles.defaults.PSObject.Properties.Remove($old) } }
    $updated = ConvertTo-Json -InputObject $settings -Depth 100 -ErrorAction Stop
    $backup = "$path.kmos-backup"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop }
    }
    $temp = "$path.kmos-$PID.tmp"
    try {
        [IO.File]::WriteAllText($temp, $updated, ([Text.UTF8Encoding]::new($false)))
        Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop
    } finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
}
[IO.File]::WriteAllText($marker, (Get-Date -Format o))
Write-Host 'Windows Terminal defaults set to Kappa Mono, size 12 for this account (one time).'
