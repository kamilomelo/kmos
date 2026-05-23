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
The first two font archives are reused from the `kmos` repo via raw URLs, so you do not need to clone the repo on the Windows machine.

### Set Windows Terminal Default Font

```powershell
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$json = Get-Content -Raw -Path $settings | ConvertFrom-Json

function Set-TerminalFont {
    param([Parameter(Mandatory)]$Target)

    if (-not $Target.font) {
        $Target | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
    }
    $Target.font | Add-Member -NotePropertyName face -NotePropertyValue 'Hack Nerd Font Mono' -Force
    $Target.font | Add-Member -NotePropertyName size -NotePropertyValue 12 -Force
    $Target | Add-Member -NotePropertyName fontFace -NotePropertyValue 'Hack Nerd Font Mono' -Force
    $Target | Add-Member -NotePropertyName fontSize -NotePropertyValue 12 -Force
}

if (-not $json.profiles) {
    $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{
        defaults = [pscustomobject]@{}
        list = @()
    })
}
if (-not $json.profiles.defaults) {
    $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
}

Set-TerminalFont -Target $json.profiles.defaults

foreach ($profile in $json.profiles.list) {
    Set-TerminalFont -Target $profile
}

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $settings -Encoding UTF8
```

Close and reopen Windows Terminal after running that block. The default Terminal font and every explicit Terminal profile, including normal and elevated PowerShell Preview sessions, will use `Hack Nerd Font Mono`.

### Install and Configure Starship

```powershell
winget install --id Starship.Starship --exact --source winget --scope machine

$starshipDir = 'C:\ProgramData\kmos\starship-presets'
New-Item -ItemType Directory -Path $starshipDir -Force | Out-Null

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/starship-presets/holow-light.toml' -OutFile (Join-Path $starshipDir 'holow-light.toml')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/starship-presets/holow-dark.toml' -OutFile (Join-Path $starshipDir 'holow-dark.toml')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/starship-presets/filled-light.toml' -OutFile (Join-Path $starshipDir 'filled-light.toml')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/starship-presets/filled-dark.toml' -OutFile (Join-Path $starshipDir 'filled-dark.toml')

$profilePath = Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
$profileContent = @'
$env:STARSHIP_CONFIG = 'C:\ProgramData\kmos\starship-presets\holow-light.toml'
Invoke-Expression (& starship init powershell)
'@

New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
Set-Content -Path $profilePath -Value $profileContent -Encoding ASCII
```

This installs Starship system-wide, downloads all 4 `kmos` presets, and activates `holow-light.toml` for `PowerShell Preview`.
