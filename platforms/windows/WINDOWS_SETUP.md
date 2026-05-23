# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete.

## Phase 1: Core Tools

Run these first on a fresh Windows 11 machine with internet access.

### Install Core Tools

```powershell
winget install --id Git.Git --exact --source winget
winget install --id Microsoft.PowerShell.Preview --exact --source winget
winget install --id GNU.Nano --exact --source winget --scope machine
winget install --id KDE.Kate --exact --source winget --scope machine
winget install --id Mozilla.Firefox.DeveloperEdition --exact --source winget --scope machine
winget install --id 9NR5B8GVVM13 --exact --source msstore --accept-package-agreements --accept-source-agreements
```
Lenovo Commercial Vantage is Store-backed. If you want to run it manually, the winget Store ID is `9NR5B8GVVM13`.

### Install and Enable OpenSSH

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (SSH)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
```

#### Verify SSH

```powershell
Get-Service sshd
ssh localhost
```

### Install Fonts

```powershell
$fontWork = Join-Path $env:TEMP 'kmos-fonts'
New-Item -ItemType Directory -Path $fontWork -Force | Out-Null

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/extra-fonts/ABeeZee.zip' -OutFile (Join-Path $fontWork 'ABeeZee.zip')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/extra-fonts/more_sugar.zip' -OutFile (Join-Path $fontWork 'more_sugar.zip')
Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip' -OutFile (Join-Path $fontWork 'Hack.zip')
Invoke-WebRequest -Uri 'https://github.com/google/fonts/raw/main/ofl/comfortaa/Comfortaa%5Bwght%5D.ttf' -OutFile (Join-Path $fontWork 'Comfortaa-wght.ttf')

Expand-Archive -LiteralPath (Join-Path $fontWork 'ABeeZee.zip') -DestinationPath (Join-Path $fontWork 'ABeeZee') -Force
Expand-Archive -LiteralPath (Join-Path $fontWork 'more_sugar.zip') -DestinationPath (Join-Path $fontWork 'MoreSugar') -Force
Expand-Archive -LiteralPath (Join-Path $fontWork 'Hack.zip') -DestinationPath (Join-Path $fontWork 'Hack') -Force

explorer.exe (Join-Path $fontWork 'ABeeZee')
explorer.exe (Join-Path $fontWork 'MoreSugar')
explorer.exe (Join-Path $fontWork 'Hack')
explorer.exe $fontWork
```

This is the minimal manual set for Windows:
- ABeeZee Regular
- Hack Nerd Regular
- More Sugar Thin
- Comfortaa

Then install these manually with `Install for all users`:
- `ABeeZee\ABeeZee-Regular.ttf`
- `MoreSugar\MoreSugar-Thin.ttf`
- `Hack\HackNerdFontMono-Regular.ttf`
- `Comfortaa-wght.ttf`

The first two font archives are reused from the `kmos` repo via raw URLs, so you do not need to clone the repo on the Windows machine.
