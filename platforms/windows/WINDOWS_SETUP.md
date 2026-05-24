# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete.

## Phase 1: Optional Disk Resize

Paste this whole block and run it as one piece. This is the same resize logic used in the original `kmos-windows-install.ps1`.

```powershell
function Prompt-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )

    while ($true) {
        $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
        $answer = Read-Host "$Prompt $suffix"
        if ($null -eq $answer) {
            return $Default
        }

        $answer = $answer.Trim()
        if ($answer.Length -eq 0) {
            return $Default
        }

        switch -Regex ($answer.ToLowerInvariant()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
        }
    }
}

function Prompt-Choice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string[]]$Choices
    )

    while ($true) {
        $joined = ($Choices | ForEach-Object { $_ }) -join '/'
        $answer = Read-Host "$Prompt [$joined]"
        if ($Choices -contains $answer) {
            return $answer
        }
    }
}

function Show-PartitionSizes {
    param(
        [Parameter(Mandatory)][uint64]$Current,
        [Parameter(Mandatory)][uint64]$Min,
        [Parameter(Mandatory)][uint64]$Max
    )

    Write-Host ("Current C: size: {0:N2} GiB" -f ($Current / 1GB))
    Write-Host ("Minimum supported C: size: {0:N2} GiB" -f ($Min / 1GB))
    Write-Host ("Maximum supported C: size: {0:N2} GiB" -f ($Max / 1GB))
}

function Resize-SystemPartitionIfRequested {
    if (-not (Prompt-YesNo -Prompt 'Shrink the current disk to leave space for another OS?' -Default $false)) {
        Write-Host 'Leaving the disk layout unchanged.'
        return
    }

    $systemPartition = Get-Partition -DriveLetter 'C'
    $supported = Get-PartitionSupportedSize -DriveLetter 'C'
    $disk = Get-Disk -Number $systemPartition.DiskNumber
    $currentSize = [uint64]$systemPartition.Size
    $otherPartitionBytes = [uint64](($disk | Get-Partition | Where-Object { $_.DriveLetter -ne 'C' } | Measure-Object -Property Size -Sum).Sum)

    Show-PartitionSizes -Current $currentSize -Min $supported.SizeMin -Max $supported.SizeMax

    $choice = Prompt-Choice -Prompt 'Choose resize mode' -Choices @('half','custom')
    if ($choice -eq 'half') {
        $targetSize = [uint64](($disk.Size / 2) - $otherPartitionBytes)
        $targetSize = [uint64]([math]::Floor($targetSize / 1MB) * 1MB)
    } else {
        while ($true) {
            $customGiB = Read-Host 'Enter the new size for C: in GiB'
            if ($customGiB -match '^\d+(\.\d+)?$') {
                $targetSize = [uint64]([double]$customGiB * 1GB)
                break
            }
        }
    }

    if ($targetSize -lt $supported.SizeMin -or $targetSize -gt $supported.SizeMax) {
        throw ("Requested C: size {0:N2} GiB is outside the supported range." -f ($targetSize / 1GB))
    }

    if ($targetSize -ge $currentSize) {
        throw 'Requested size is not smaller than the current C: partition.'
    }

    Write-Host ("C: will be resized to {0:N2} GiB" -f ($targetSize / 1GB))
    if (-not (Prompt-YesNo -Prompt 'Apply this partition resize now?' -Default $false)) {
        Write-Host 'Skipping partition resize.'
        return
    }

    Resize-Partition -DriveLetter 'C' -Size $targetSize
    Write-Host 'Partition resize completed.'
}

Resize-SystemPartitionIfRequested
```

---

## Phase 2: Appearance

Run this before creating additional Windows users so new accounts inherit the same visual defaults.

### Set Computer Name

```powershell
function Prompt-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )

    while ($true) {
        $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
        $answer = Read-Host "$Prompt $suffix"
        if ($null -eq $answer) {
            return $Default
        }

        $answer = $answer.Trim()
        if ($answer.Length -eq 0) {
            return $Default
        }

        switch -Regex ($answer.ToLowerInvariant()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
        }
    }
}

function Prompt-ConfirmedText {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ConfirmLabel = 'Is this correct?'
    )

    while ($true) {
        $value = ''
        while ([string]::IsNullOrWhiteSpace($value)) {
            $value = (Read-Host $Prompt).Trim()
        }

        if (Prompt-YesNo -Prompt ("{0}: {1}. {2}" -f $Prompt, $value, $ConfirmLabel) -Default $true) {
            return $value
        }
    }
}

$currentName = $env:COMPUTERNAME
Write-Host "Current computer name: $currentName"

$newName = Prompt-ConfirmedText -Prompt 'Enter the desired computer name'
if ($newName -eq $currentName) {
    Write-Host 'Computer name already matches the requested name.'
} else {
    Rename-Computer -NewName $newName -Force
    Write-Host "Computer renamed to $newName. A reboot will be required for the new name to take effect."
}
```

### Remove Old Organization Policy Locks

```powershell
$policyPaths = @(
    'HKCU:\Software\Policies\Microsoft\Windows\Personalization',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization',
    'HKCU:\Software\Policies\Microsoft\Windows\CloudContent',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
    'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
)

foreach ($path in $policyPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

$policyValues = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'; Name = 'NoChangingWallPaper' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'; Name = 'NoChangingWallPaper' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoActiveDesktop' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoActiveDesktopChanges' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoActiveDesktop' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoActiveDesktopChanges' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'Wallpaper' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'WallpaperStyle' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'Wallpaper' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'WallpaperStyle' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WallPaper' }
)

foreach ($item in $policyValues) {
    Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
}

$themesDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
Remove-Item -Path (Join-Path $themesDir 'TranscodedWallpaper*') -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $themesDir 'CachedFiles') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $themesDir 'slideshow.ini') -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $themesDir '*.theme') -Force -ErrorAction SilentlyContinue

gpupdate /target:user /force
gpupdate /target:computer /force
rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True
```

If personalization is still blocked after this cleanup, reboot once before continuing with Phase 2.

### Stage Wallpaper

```powershell
$wallpaperDir = Join-Path $env:PUBLIC 'Pictures\kmos'
$wallpaperPath = Join-Path $wallpaperDir 'kmos-wallpaper.png'
New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/wallpapers/kmos-wallpaper.png' -OutFile $wallpaperPath
```

Shared wallpaper path:

```powershell
Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
```

### Mode A: Enforced Corporate Appearance

Use this if every user must get the same first-login look with no generic Windows appearance. This is the reliable path, but it will restrict personalization changes.

#### Enforce Wallpaper, Lock Screen, and Colors

```powershell
$wallpaperPath = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
$fileUrl = 'file:///' + (($wallpaperPath -replace '\\', '/') -replace ' ', '%20')

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -Name 'Wallpaper' -Value $wallpaperPath
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '6'
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value $wallpaperPath
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreenSlideshow' -Value 1 -Type DWord
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImagePath' -Value $wallpaperPath
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageUrl' -Value $fileUrl
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageStatus' -Value 1 -Type DWord
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type DWord
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSpotlightCollectionOnDesktop' -Value 1 -Type DWord
```

Mode A procedure:
1. run `Stage Wallpaper`
2. run `Enforce Wallpaper, Lock Screen, and Colors`
3. reboot or sign out/sign back in
4. create users after the machine shows the enforced appearance correctly

Mode A is the reliable corporate-feel path.

### Mode B: Unlocked Appearance

Use this if users must be free to change wallpaper, lock screen, and colors later. This mode keeps personalization editable, but wallpaper inheritance for new users is still less reliable than colors.

#### Apply Current User Wallpaper and Dark Mode

```powershell
$wallpaperPath = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value 0 -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 0 -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'ColorPrevalence' -Value 0 -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
Set-RegistryValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background' -Value '0 0 0'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '6'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value $wallpaperPath
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'AccentColor' -Value 4285887861 -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'AccentColorInactive' -Value 4282400832 -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'AccentColorMenu' -Value 4285887861 -Type DWord

Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class KmosWallpaper {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern int SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
"@ -ErrorAction SilentlyContinue | Out-Null
[void][KmosWallpaper]::SystemParametersInfo(20, 0, $wallpaperPath, 3)
rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True
```

#### Apply Lock Screen by PowerShell

```powershell
$wallpaperPath = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
$fileUrl = 'file:///' + (($wallpaperPath -replace '\\', '/') -replace ' ', '%20')

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImagePath' -Value $wallpaperPath
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageUrl' -Value $fileUrl
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageStatus' -Value 1 -Type DWord
```

This lock-screen step is best-effort. If Windows ignores it, use Settings for the lock screen only.

#### Capture and Replay the Current User Appearance for New Users

This step captures the current user's appearance values after you have the look exactly right, then replays those same values for each new user at first login. It should transmit the same wallpaper path, dark mode, and accent values without policy-locking them afterward.

```powershell
$scriptDir = 'C:\ProgramData\kmos\scripts'
$scriptPath = Join-Path $scriptDir 'Apply-KmosAppearance.ps1'
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

$desktop = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
$personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$dwm = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM'
$accent = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$colors = Get-ItemProperty 'HKCU:\Control Panel\Colors'

$scriptContent = @"
function Set-RegistryValue {
    param(
        [string]`$Path,
        [string]`$Name,
        `$Value,
        [string]`$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath `$Path)) {
        New-Item -Path `$Path -Force | Out-Null
    }

    try {
        Set-ItemProperty -Path `$Path -Name `$Name -Value `$Value -Force -ErrorAction Stop | Out-Null
    } catch {
        New-ItemProperty -Path `$Path -Name `$Name -Value `$Value -PropertyType `$Type -Force | Out-Null
    }
}

Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value $($personalize.AppsUseLightTheme) -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value $($personalize.SystemUsesLightTheme) -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'ColorPrevalence' -Value $($personalize.ColorPrevalence) -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value $($personalize.EnableTransparency) -Type DWord
Set-RegistryValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background' -Value '$($colors.Background)'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '$($desktop.WallpaperStyle)'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '$($desktop.TileWallpaper)'
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value '$($desktop.WallPaper)'
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'AccentColor' -Value $($dwm.AccentColor) -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'AccentColorInactive' -Value $($dwm.AccentColorInactive) -Type DWord
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'AccentColorMenu' -Value $($accent.AccentColorMenu) -Type DWord

Add-Type @'
using System.Runtime.InteropServices;
public class KmosWallpaper {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern int SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
'@
[void][KmosWallpaper]::SystemParametersInfo(20, 0, '$($desktop.WallPaper)', 3)
rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True
"@

Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII

$activeSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\kmos.appearance'
New-Item -Path $activeSetupKey -Force | Out-Null
Set-ItemProperty -Path $activeSetupKey -Name Version -Value '1,0,0,0'
New-ItemProperty -Path $activeSetupKey -Name IsInstalled -Value 1 -PropertyType DWord -Force | Out-Null
Set-ItemProperty -Path $activeSetupKey -Name StubPath -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Force | Out-Null; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'kmos.appearance' -Value 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File `'$scriptPath`''`""
```

This uses `Active Setup` only to register a per-user `RunOnce`. The actual appearance replay then happens after the new user's shell is up, which is more reliable for wallpaper than running too early in the sign-in sequence.

Mode B procedure:
1. run `Remove Old Organization Policy Locks`
2. run `Stage Wallpaper`
3. run `Apply Current User Wallpaper and Dark Mode`
4. run `Apply Lock Screen by PowerShell`
5. verify the current user looks exactly right
6. run `Capture and Replay the Current User Appearance for New Users`

If wallpaper or personalization still behaves inconsistently after unlocking old policy keys, reboot or sign out/sign back in before continuing with the rest of Mode B.

This mode is unlocked, but wallpaper inheritance is still the weak point on Windows.

---

## Phase 3: Core Tools

Run these on a fresh Windows 11 machine with internet access.

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

---

## Phase 4: NVIDIA

Run this only on machines that actually have an NVIDIA GPU.

For CAD / Fusion / Autodesk machines, prefer the official `NVIDIA Studio Driver`.

### Detect NVIDIA GPU

```powershell
Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object Name, DriverVersion
```

If nothing is returned, skip this phase.

### Install Studio Driver

```powershell
Start-Process 'https://www.nvidia.com/Download/index.aspx'
```

Then in the browser:
- select the installed NVIDIA GPU
- choose `Studio Driver`
- download and install it
- reboot if the NVIDIA installer asks for it

If NVIDIA offers both notebook OEM-certified and generic Studio packages, prefer the OEM-certified path for Lenovo laptops.

### Verify Driver Install

```powershell
nvidia-smi
```

If `nvidia-smi` is not in `PATH`, try:

```powershell
& 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
```

---

## Phase 5: Chris Titus WinUtil

Open an elevated PowerShell or Windows Terminal session and run:

```powershell
irm christitus.com/win | iex
```

Then apply the WinUtil tweaks you want from its interface.

---

## Phase 6: Additional Users

Create additional Windows users only after Phases 2 and 3 are complete, and after any reboot required by Phase 2 or Phase 4.

### Create a Local Administrator

```powershell
$username = Read-Host 'Enter the new local username'
$password = Read-Host 'Enter the password for the new user' -AsSecureString

New-LocalUser -Name $username -Password $password -FullName $username -Description 'kmos local administrator'
Add-LocalGroupMember -Group 'Administrators' -Member $username
```

After creating the user:
- sign in once as that user
- verify dark mode and colors were inherited
- if the wallpaper did not inherit, set the same staged wallpaper manually once from:
  `C:\Users\Public\Pictures\kmos\kmos-wallpaper.png`
- verify dark mode and colors were inherited
- verify `PowerShell Preview`, Terminal font, and Starship are working
