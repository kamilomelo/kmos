# Temporary Windows font test status

**Stop: the previous automation test failed.** Do not rerun the old download
block. No automatic font installation or Windows Terminal default is approved
yet. The primary [Windows setup guide](windows_setup.md) remains unchanged.

To help locate the failure, run this **read-only** snippet in Windows PowerShell
inside the VM and share the first error from the failed run as well. This page
contains only an inline snippet; it does not download or run a repo script.

```powershell
& {
Write-Host "Windows: $([Environment]::OSVersion.Version)"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Admin: $(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
Write-Host "Terminal package: $((Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue).Version)"
Write-Host 'Kappa Mono font files:'
Get-ChildItem -LiteralPath (Join-Path $env:WINDIR 'Fonts') -Filter 'KappaMono*.ttf' -ErrorAction SilentlyContinue | Select-Object Name, Length
Write-Host 'Kappa Mono machine registry entries:'
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts').PSObject.Properties |
    Where-Object { $_.Name -like '*Kappa Mono*' } | Select-Object Name, Value
Write-Host 'Terminal settings file:'
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
Write-Host "$settings : $(Test-Path -LiteralPath $settings -PathType Leaf)"
}
```

After the cause of the failed test is known, the corrected installation
instructions will be **inline in Markdown**, not standalone scripts in this
repository. A one-time sign-in action, if used, may still create a script on
the Windows machine at runtime; that is separate from storing script files
in the repository.
