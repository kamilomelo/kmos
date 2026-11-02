# WinGet check (temporary test page)

This is a **read-only check**, kept separate from the Windows setup guide.
Open this page on the Windows machine, copy the block into the same Windows
PowerShell account where `winget` failed, and send back the output. It does
not install PowerShell or change Windows settings.

```powershell
& {
$package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
$alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
$windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$command = Get-Command winget.exe -ErrorAction SilentlyContinue

Write-Host "Windows build: $([Environment]::OSVersion.Version)"
Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
if ($package) {
    Write-Host "App Installer: $($package.Version) ($($package.Status))"
} else {
    Write-Host 'App Installer: NOT REGISTERED FOR THIS ACCOUNT'
}
Write-Host "WinGet command: $(if ($command) { $command.Source } else { 'NOT FOUND' })"
Write-Host "WinGet alias file exists: $(Test-Path -LiteralPath $alias)"
Write-Host "WindowsApps in this PowerShell PATH: $(($env:Path -split ';') -contains $windowsApps)"
if (Test-Path -LiteralPath $alias) {
    try {
        Write-Host 'Direct alias version:'
        & $alias --version
    } catch {
        Write-Host "Direct alias failed: $($_.Exception.Message)"
    }
}
}
```

WinGet comes from **App Installer**, not from a newer PowerShell. If the
package is missing, the stable [Microsoft App Installer Store listing](https://apps.microsoft.com/detail/9nblggh4nns1)
is the supported installation path. Do not install a PowerShell preview to
solve a WinGet command-lookup problem.
