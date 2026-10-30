# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete.

## Phase 1: Optional Disk Resize

For a fresh Windows-only disk, this optional step can leave approximately half
of the **whole disk** available for another OS. The default is to leave the
disk unchanged. If you opt in, choose half (default), a custom **total Windows
footprint** in GiB (C: plus the other Windows partitions), or cancel. A final
confirmation defaults to No. Partition alignment may prevent an exact 50/50
split; this does not move existing recovery partitions or guarantee one
contiguous free-space region. Back up important data first.

Paste this whole block into an elevated PowerShell session and run it as one piece.

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

function Prompt-ResizeMode {
    while ($true) {
        Write-Host '1) Half the whole disk for Windows (default)'
        Write-Host '2) Custom total Windows footprint in GiB'
        Write-Host '3) Cancel without changes'
        $answer = (Read-Host 'Choose [1/2/3; Enter = 1]').Trim().ToLowerInvariant()
        switch ($answer) {
            { $_ -in @('', '1', 'half') } { return 'half' }
            { $_ -in @('2', 'custom') } { return 'custom' }
            { $_ -in @('3', 'cancel') } { return 'cancel' }
        }
        Write-Host 'Enter 1, 2, or 3.'
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
    $partitions = @(Get-Partition -DiskNumber $disk.Number)
    $otherPartitionBytes = [uint64](($partitions | Where-Object { $_.PartitionNumber -ne $systemPartition.PartitionNumber } | Measure-Object -Property Size -Sum).Sum)

    Show-PartitionSizes -Current $currentSize -Min $supported.SizeMin -Max $supported.SizeMax
    Write-Host ("Whole disk: {0:N2} GiB; other partitions: {1:N2} GiB" -f ($disk.Size / 1GB), ($otherPartitionBytes / 1GB))
    $partitions | Format-Table PartitionNumber, DriveLetter, Type, Size

    $choice = Prompt-ResizeMode
    if ($choice -eq 'cancel') {
        Write-Host 'Leaving the disk layout unchanged.'
        return
    }

    if ($choice -eq 'half') {
        $targetWindowsBytes = [math]::Floor(([double]$disk.Size / 2) / 1MB) * 1MB
    } else {
        while ($true) {
            $customGiB = (Read-Host 'Total Windows space in GiB (C: plus other partitions; type cancel to stop)').Trim()
            if ($customGiB -eq 'cancel') {
                Write-Host 'Leaving the disk layout unchanged.'
                return
            }
            $requestedGiB = 0.0
            if ($customGiB -match '^\d+(\.\d+)?$' -and
                [double]::TryParse($customGiB, [Globalization.NumberStyles]::AllowDecimalPoint,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$requestedGiB) -and
                $requestedGiB -gt 0 -and $requestedGiB -le ($disk.Size / 1GB)) {
                $targetWindowsBytes = [math]::Floor(($requestedGiB * 1GB) / 1MB) * 1MB
                break
            }
            Write-Host 'Enter a positive number no larger than the whole disk, or cancel.'
        }
    }

    if ($targetWindowsBytes -le $otherPartitionBytes) {
        throw 'Other partitions already use the requested Windows space; no changes made.'
    }
    $targetSize = [uint64]([math]::Floor(($targetWindowsBytes - $otherPartitionBytes) / 1MB) * 1MB)
    if ($targetSize -lt $supported.SizeMin -or $targetSize -gt $supported.SizeMax) {
        throw ("Requested C: size {0:N2} GiB is outside the supported shrink range; no changes made." -f ($targetSize / 1GB))
    }

    if ($targetSize -ge $currentSize) {
        throw 'Requested size is not smaller than the current C: partition.'
    }

    Write-Host ("C: after resize: {0:N2} GiB" -f ($targetSize / 1GB))
    Write-Host ("All listed partitions after resize: {0:N2} GiB" -f (($targetSize + $otherPartitionBytes) / 1GB))
    Write-Host ("Space outside partitions (not necessarily contiguous): {0:N2} GiB" -f (($disk.Size - $targetSize - $otherPartitionBytes) / 1GB))
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
    Rename-Computer -NewName $newName -Force -ErrorAction Stop
    Write-Host "Computer renamed to $newName. Use Restart (not Shut down) to apply the name."
}
```

### Existing organization policies

Do **not** delete broad Windows policy keys as a routine setup step. If an old
organization's policy blocks personalization, first determine whether the
computer is still managed. Back up the specific setting and resolve it with
the administrator or remove only the identified stale policy; a blanket
registry cleanup can erase unrelated security or management settings. Neither
Mode A nor Mode B requires such a cleanup on a fresh Windows installation.

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

Use this if you want Windows to try to enforce the kmos look by policy. This path does not capture a user profile and does not replay anything for later users. It is best-effort on Windows and may still need a manual check after reboot.

**VM finding (2026-10-30):** On a modified Windows 11 Pro ISO, the lock-screen
image appeared, but the desktop wallpaper needed a manual Fit → Fill change
to display. Switching Background from Picture to Solid Color then hid the
wallpaper and blocked switching back. Lock-screen news/weather cards also
remained. Mode A is **not validated or recommended for deployment** on this
build; test it only in a disposable VM with a rollback point. Do not use the
old broad policy cleanup as a repair. Lock-screen status/widgets are separate
from the lock-screen image.

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
4. verify the machine kept the enforced appearance
5. create users only after that check passes

Mode A ends here. Do not run the Mode B blocks in this mode.

### Mode B: Unlocked Appearance

Use this if you want to set the current user once and then replay that look for new users later. This mode keeps personalization editable and does not use the policy-enforcement block from Mode A.

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
1. run `Stage Wallpaper`
2. run `Apply Current User Wallpaper and Dark Mode`
3. run `Apply Lock Screen by PowerShell` (optional and best-effort)
4. verify the current user looks exactly right and can still personalize it
5. run `Capture and Replay the Current User Appearance for New Users`
6. restart or sign out/sign back in
7. create new users after that

Mode B starts with the current user. It does not include the policy-enforcement block from Mode A.

If wallpaper or personalization behaves inconsistently, restart or sign out
and back in before proceeding. Do not use Mode B on top of Mode A policies;
restore a pre-Mode-A checkpoint first.

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

$fontApiBase = 'https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts'
$families = @('kappa-text', 'kappa-mark', 'kappa-form', 'kappa-mono', 'kappa-spin')

foreach ($family in $families) {
    $familyDir = Join-Path $fontWork $family
    New-Item -ItemType Directory -Path $familyDir -Force | Out-Null
    $items = Invoke-RestMethod -Uri "$fontApiBase/$family/ttf?ref=main"

    foreach ($item in $items) {
        if ($item.download_url -and $item.name -like '*.ttf') {
            Invoke-WebRequest -Uri $item.download_url -OutFile (Join-Path $familyDir $item.name)
        }
    }

    explorer.exe $familyDir
}

explorer.exe $fontWork
```

This installs the current Kappa font system for Windows:
- `Kappa Text`
- `Kappa Mark`
- `Kappa Form`
- `Kappa Mono`
- `Kappa Spin`

### Set Windows Terminal Default Font

```powershell
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$json = Get-Content -Raw -Path $settings | ConvertFrom-Json

function Set-TerminalFont {
    param([Parameter(Mandatory)]$Target)

    if (-not $Target.font) {
        $Target | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
    }
    $Target.font | Add-Member -NotePropertyName face -NotePropertyValue 'Kappa Mono' -Force
    $Target.font | Add-Member -NotePropertyName size -NotePropertyValue 12 -Force
    $Target | Add-Member -NotePropertyName fontFace -NotePropertyValue 'Kappa Mono' -Force
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

Close and reopen Windows Terminal after running that block. The default Terminal font and every explicit Terminal profile, including normal and elevated PowerShell Preview sessions, will use `Kappa Mono`.

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
