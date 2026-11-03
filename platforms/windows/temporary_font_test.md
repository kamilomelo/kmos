# Temporary Kappa fonts and Terminal test

The VM check confirmed **Kappa Mono** was installed for all users, but did not
verify the other families. Run the first inline block in **elevated Windows
PowerShell 5.1 over SSH** to install **all six Kappa families** at once, including
Kappa Page (alpha). It fetches the current TTF files from the Kappa repository,
verifies their font names, and refuses to overwrite a different existing file.
It creates no script file in this repository. Report any error before running
the second block.

```powershell
& {
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }
Add-Type -AssemblyName System.Drawing
if (-not ([System.Management.Automation.PSTypeName]'KmosAllFontApi').Type) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KmosAllFontApi {
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
    public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);
}
'@
}
$api = 'https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts'
$families = @('kappa-text','kappa-page','kappa-mark','kappa-form','kappa-mono','kappa-spin')
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$dir = Join-Path $env:WINDIR 'Fonts'
$work = Join-Path $env:TEMP 'kmos-fonts'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count = 0
foreach ($family in $families) {
    $items = @(Invoke-RestMethod -Uri "$api/$family/ttf?ref=main" -ErrorAction Stop)
    $files = @($items | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ttf$' -and $_.download_url })
    if (-not $files.Count) { throw "No TTF files for $family" }
    foreach ($item in $files) {
        if ($item.name -notmatch '^[A-Za-z0-9._-]+\.ttf$') { throw "Unexpected font filename: $($item.name)" }
        $source = Join-Path $work $item.name
        $target = Join-Path $dir $item.name
        Invoke-WebRequest -UseBasicParsing -Uri $item.download_url -OutFile $source -ErrorAction Stop
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 1024 -or -not (($bytes[0] -eq 0 -and $bytes[1] -eq 1 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -eq 'OTTO')) { throw "Not a valid TTF/OTF: $($item.name)" }
        $private = New-Object System.Drawing.Text.PrivateFontCollection
        try {
            $private.AddFontFile($source)
            $names = @($private.Families | ForEach-Object Name)
            if ($names.Count -ne 1 -or $names[0] -notmatch '^Kappa ') { throw "Unexpected font family: $($item.name) : $names" }
        } finally { $private.Dispose() }
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) { throw "Installed file differs; not overwriting $target" }
        } else { Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop }
        $registered = @((Get-ItemProperty -LiteralPath $key).PSObject.Properties | Where-Object { $_.Value -eq $item.name })
        if (-not $registered.Count) {
            $name = "$($names[0]) $([IO.Path]::GetFileNameWithoutExtension($item.name)) (TrueType)"
            $current = (Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue).$name
            if ($current -and $current -ne $item.name) { throw "Conflicting font registry entry: $name" }
            New-ItemProperty -Path $key -Name $name -Value $item.name -PropertyType String -ErrorAction Stop | Out-Null
        }
        if ([KmosAllFontApi]::AddFontResourceEx($target,0,[IntPtr]::Zero) -lt 1) { throw "Windows could not load $target" }
        $count++
    }
    Write-Host "$family : $($files.Count) fonts registered"
}
$result = [IntPtr]::Zero
[void][KmosAllFontApi]::SendMessageTimeout([IntPtr]0xffff,0x1d,[IntPtr]::Zero,[IntPtr]::Zero,2,5000,[ref]$result)
Write-Host "All six Kappa families: $count font files installed/verified for every user."
}
```

The failed earlier test also did **not** register the automatic Terminal sign-in
step. The next block tests the Terminal settings merge for **the SSH account
only**. It does not yet configure other accounts. Close Windows Terminal for
this account before running it. If it fails, paste the error here.

The second block makes a one-time backup beside the original `settings.json` before editing.
It preserves other JSON settings, but JSON comments and formatting are not
preserved. The font remains editable afterward. This is a VM test, not a
fleet-validated procedure.

```powershell
& {
$ErrorActionPreference = 'Stop'
$path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Terminal settings not found: $path" }
$original = [IO.File]::ReadAllText($path)
$out = New-Object System.Text.StringBuilder
$quoted = $false; $escaped = $false; $line = $false; $block = $false
for ($i = 0; $i -lt $original.Length; $i++) {
    $c = $original[$i]
    $next = if ($i + 1 -lt $original.Length) { $original[$i + 1] } else { [char]0 }
    if ($line) {
        if ($c -eq "`r" -or $c -eq "`n") { $line = $false; [void]$out.Append($c) }
        continue
    }
    if ($block) {
        if ($c -eq '*' -and $next -eq '/') { $block = $false; $i++ }
        continue
    }
    if ($quoted) {
        [void]$out.Append($c)
        if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
        continue
    }
    if ($c -eq '"') { $quoted = $true; [void]$out.Append($c); continue }
    if ($c -eq '/' -and $next -eq '/') { $line = $true; $i++; continue }
    if ($c -eq '/' -and $next -eq '*') { $block = $true; $i++; continue }
    [void]$out.Append($c)
}
if ($quoted -or $block) { throw 'Unterminated JSON string or comment; settings unchanged.' }
$text = $out.ToString()
$out = New-Object System.Text.StringBuilder
$quoted = $false; $escaped = $false
for ($i = 0; $i -lt $text.Length; $i++) {
    $c = $text[$i]
    if ($quoted) {
        [void]$out.Append($c)
        if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
        continue
    }
    if ($c -eq '"') { $quoted = $true; [void]$out.Append($c); continue }
    if ($c -eq ',') {
        $j = $i + 1
        while ($j -lt $text.Length -and [char]::IsWhiteSpace($text[$j])) { $j++ }
        if ($j -lt $text.Length -and $text[$j] -in @('}', ']')) { continue }
    }
    [void]$out.Append($c)
}
try { $settings = ConvertFrom-Json -InputObject $out.ToString() -ErrorAction Stop }
catch { throw "Could not parse Terminal settings; original unchanged: $_" }
if ($settings -isnot [pscustomobject]) { throw 'Unexpected Terminal settings format; original unchanged.' }
if (-not $settings.PSObject.Properties['profiles']) { $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles -isnot [pscustomobject]) { throw 'Unexpected profiles format; original unchanged.' }
if (-not $settings.profiles.PSObject.Properties['defaults']) { $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles.defaults -isnot [pscustomobject]) { throw 'Unexpected defaults format; original unchanged.' }
if (-not $settings.profiles.defaults.PSObject.Properties['font']) { $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles.defaults.font -isnot [pscustomobject]) { throw 'Unexpected font format; original unchanged.' }
$font = $settings.profiles.defaults.font
if ($font.PSObject.Properties['face']) { $font.face = 'Kappa Mono' } else { $font | Add-Member -NotePropertyName face -NotePropertyValue 'Kappa Mono' }
if ($font.PSObject.Properties['size']) { $font.size = 12 } else { $font | Add-Member -NotePropertyName size -NotePropertyValue 12 }
foreach ($old in @('fontFace','fontSize')) {
    if ($settings.profiles.defaults.PSObject.Properties[$old]) { $settings.profiles.defaults.PSObject.Properties.Remove($old) }
}
$updated = ConvertTo-Json -InputObject $settings -Depth 100 -ErrorAction Stop
$check = ConvertFrom-Json -InputObject $updated -ErrorAction Stop
if ($check.profiles.defaults.font.face -ne 'Kappa Mono' -or $check.profiles.defaults.font.size -ne 12) { throw 'Merged font could not be verified; original unchanged.' }
$backup = "$path.kmos-backup"
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop }
$temp = "$path.kmos-$PID.tmp"
try {
    [IO.File]::WriteAllText($temp, $updated, ([Text.UTF8Encoding]::new($false)))
    [IO.File]::Replace($temp, $path, $null)
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
Write-Host "Applied Kappa Mono, size 12 to $path; original backed up at $backup"
}
```

Then reopen Windows Terminal for **this account** and check Settings → Profiles
→ Defaults → Appearance. The existing new-user account will not change from
this test; it needs the separate sign-in automation after this merge succeeds.
