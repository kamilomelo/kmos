# Run elevated in Windows PowerShell. Installs the frozen Kappa families for all users.
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell (powershell.exe).' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KmosFontApi {
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
    public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
}
'@
$fontsDir = Join-Path $env:WINDIR 'Fonts'
$fontKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$families = @('kappa-text', 'kappa-mark', 'kappa-form', 'kappa-mono', 'kappa-spin')
$api = 'https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts'
$work = Join-Path $env:TEMP 'kmos-fonts'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$installed = 0
foreach ($family in $families) {
    $items = @(Invoke-RestMethod -Uri "$api/$family/ttf?ref=main" -ErrorAction Stop)
    $ttfs = @($items | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ttf$' -and $_.download_url })
    if (-not $ttfs.Count) { throw "No TTF files found for $family" }
    foreach ($item in $ttfs) {
        if ($item.name -notmatch '^[A-Za-z0-9._-]+\.ttf$') { throw "Unexpected font filename: $($item.name)" }
        $source = Join-Path $work $item.name
        $target = Join-Path $fontsDir $item.name
        Invoke-WebRequest -UseBasicParsing -Uri $item.download_url -OutFile $source -ErrorAction Stop
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 1024 -or -not (($bytes[0] -eq 0 -and $bytes[1] -eq 1 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or
            ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'OTTO'))) { throw "Not a TrueType/OpenType font: $($item.name)" }
        $private = New-Object System.Drawing.Text.PrivateFontCollection
        try {
            $private.AddFontFile($source)
            $names = @($private.Families | ForEach-Object Name)
            if ($names.Count -ne 1 -or $names[0] -notmatch '^Kappa ') { throw "Unexpected font family in $($item.name): $names" }
        } finally { $private.Dispose() }
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) {
                throw "Different font already installed: $target. Do not overwrite it."
            }
        } else {
            Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
        }
        $valueName = "$($names[0]) $([IO.Path]::GetFileNameWithoutExtension($item.name)) (TrueType)"
        $existing = (Get-ItemProperty -LiteralPath $fontKey -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($existing -and $existing -ne $item.name) { throw "Conflicting registry entry for $valueName" }
        if (-not $existing) { New-ItemProperty -LiteralPath $fontKey -Name $valueName -Value $item.name -PropertyType String -ErrorAction Stop | Out-Null }
        if ((Get-ItemProperty -LiteralPath $fontKey -Name $valueName -ErrorAction Stop).$valueName -ne $item.name) { throw "Font registration could not be verified: $valueName" }
        if ([KmosFontApi]::AddFontResourceEx($target, 0, [IntPtr]::Zero) -lt 1) { throw "Windows could not load $target" }
        $installed++
    }
}
$result = [IntPtr]::Zero
[void][KmosFontApi]::SendMessageTimeout([IntPtr]0xffff, 0x1d, [IntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]$result)
if ($installed -lt $families.Count) { throw "Only $installed Kappa files were registered" }
Write-Host "Registered $installed Kappa fonts for all users. Kappa Page (alpha) was not installed."
}
