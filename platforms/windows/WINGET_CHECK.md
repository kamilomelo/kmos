# WinGet bootstrap (test before adding to the setup guide)

Open this page on the Windows machine. Paste **one block** into the
Windows-supplied **Windows PowerShell (Admin)** window in which you will
continue Phase 3. No other PowerShell installation is needed. The block tries
the existing WinGet first, registers App Installer if necessary, and downloads
Microsoft's stable App Installer package only if WinGet still cannot start.
It also handles a missing `WindowsApps` PATH entry or disabled execution alias
for **this PowerShell window**, without changing account-wide PATH or aliases.

This is a **Windows test block**, not yet a verified part of the setup guide.
It uses Windows' built-in MSIX installer and no third-party bootstrap modules.

```powershell
& {
$ErrorActionPreference = 'Stop'
$windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$aliasPath = Join-Path $windowsApps 'winget.exe'

function Find-WorkingWinGet {
    param($Package)
    $paths = @(
        (Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        $aliasPath
    )
    if ($Package) { $paths += (Join-Path $Package.InstallLocation 'winget.exe') }
    foreach ($path in ($paths | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $version = & $path --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $version -match '^v?\d+\.') {
                return $path
            }
        } catch { continue }
    }
    return $null
}

$package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
$working = Find-WorkingWinGet $package
if (-not $working -and $package) {
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
    } catch {
        Write-Host 'Registration failed; trying the official stable App Installer package instead.'
    }
    $package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
    $working = Find-WorkingWinGet $package
}
if (-not $working) {
    $bundle = Join-Path $env:TEMP 'kmos-stable-AppInstaller.msixbundle'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/getwinget' -OutFile $bundle -ErrorAction Stop
    try {
        Add-AppxPackage -Path $bundle -ErrorAction Stop
    } catch {
        $failure = $_
        Write-Host "App Installer deployment failed: $($failure.Exception.Message)"
        if ($failure.Exception.Message -match '\[ActivityId\]\s+([0-9a-fA-F-]{36})') {
            try {
                Get-AppPackageLog -ActivityID $Matches[1] -ErrorAction Stop |
                    Where-Object { $_.Message -match 'depend|framework|conflict|cannot install|0x' } |
                    Select-Object -Last 6 -ExpandProperty Message | ForEach-Object { Write-Host $_ }
            } catch { Write-Host 'Windows did not provide an App Installer deployment log.' }
        }
        throw 'App Installer could not be installed; see the dependency or conflict reason above.'
    } finally {
        Remove-Item -LiteralPath $bundle -ErrorAction SilentlyContinue
    }
    $package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
    $working = Find-WorkingWinGet $package
}
if (-not $working) {
    throw 'WinGet could not start from the installed App Installer. No other system settings were changed; stop here.'
}
Set-Alias -Name winget -Value $working -Scope Global
winget --version
if ($LASTEXITCODE -ne 0) { throw 'WinGet did not start through the command name; stop here.' }
Write-Host 'WINGET READY: continue with Phase 3 in this PowerShell window.'
}
```

If this block stops with an error, send the **dependency or conflict reason**
it prints; `0x80073CF3` alone does not identify which package Windows needs.
Do not install PowerShell Preview. `https://aka.ms/getwinget` is
[Microsoft's stable App Installer download](https://github.com/microsoft/winget-cli/blob/master/doc/troubleshooting/README.md#executing-winget-exits-with-no-message).
