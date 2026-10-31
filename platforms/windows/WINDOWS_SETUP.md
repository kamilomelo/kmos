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

#### Capture and Replay the Current User Appearance for New Users

**Verified on a fresh test account in the Windows 11 VM.** This step captures
the current user's appearance and replays it at first login. It uses
the shared KMOS wallpaper file rather than a cached image from the current
user's private profile; dark mode and accent values remain editable afterward.
The earlier Active Setup hand-off failed on a fresh VM account: dark mode
appeared but the wallpaper did not, and neither its retry log nor its per-user
`Run` entry was present. This version instead installs the retry entry into
Windows' default user profile, so it is copied into **future** accounts when
Windows creates them. It does not reset existing accounts. Run in Windows
PowerShell (Admin) on the account whose appearance you want to capture.

```powershell
$scriptDir = 'C:\ProgramData\kmos\scripts'
$scriptPath = Join-Path $scriptDir 'Apply-KmosAppearance.ps1'
$wallpaperPath = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
if (-not (Test-Path -LiteralPath $wallpaperPath -PathType Leaf)) {
    throw "Shared KMOS wallpaper is missing: $wallpaperPath. Run Stage Wallpaper first."
}
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

$desktop = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
$personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$dwm = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM'
$accent = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$colors = Get-ItemProperty 'HKCU:\Control Panel\Colors'

$scriptContent = @"
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '$($wallpaperPath)' -PathType Leaf)) {
    throw 'Shared KMOS wallpaper is missing.'
}

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
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value '$($wallpaperPath)'
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
`$wallpaperApplied = [KmosWallpaper]::SystemParametersInfo(20, 0, '$($wallpaperPath)', 3)
if (`$wallpaperApplied -eq 0) { throw 'Windows rejected the KMOS wallpaper.' }
rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True
"@

Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII

# A first-login restart can interrupt a one-shot RunOnce before wallpaper is
# applied. Keep a per-user Run entry until the delayed replay succeeds.
$runnerPath = Join-Path $scriptDir 'Start-KmosAppearance.ps1'
$runnerContent = @'
$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:LOCALAPPDATA 'kmos-appearance.log'
try {
    Add-Content -Path $logPath -Value "Started KMOS appearance at $(Get-Date -Format o)"
    Start-Sleep -Seconds 30
    & 'C:\ProgramData\kmos\scripts\Apply-KmosAppearance.ps1' *>> $logPath
    if (-not $?) { throw 'KMOS appearance script failed.' }
    Add-Content -Path $logPath -Value 'KMOS appearance script completed.'
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'kmos.appearance' -ErrorAction Stop
} catch {
    Add-Content -Path $logPath -Value "KMOS appearance failed: $_"
    exit 1
}
'@
Set-Content -Path $runnerPath -Value $runnerContent -Encoding ASCII

$defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
if (-not (Test-Path -LiteralPath $defaultHive -PathType Leaf)) {
    throw "Default user profile not found: $defaultHive"
}
$backupHive = Join-Path $scriptDir 'Default-NTUSER.DAT.backup'
if (-not (Test-Path -LiteralPath $backupHive)) {
    Copy-Item -LiteralPath $defaultHive -Destination $backupHive -ErrorAction Stop
}
$hiveName = "KMOS_Default_$PID"
$hiveRoot = "HKU\$hiveName"
$runKey = "$hiveRoot\Software\Microsoft\Windows\CurrentVersion\Run"
$runCommand = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\kmos\scripts\Start-KmosAppearance.ps1'
& reg.exe load $hiveRoot $defaultHive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not load the default user profile: $defaultHive" }
try {
    & reg.exe add $runKey /v kmos.appearance /t REG_SZ /d $runCommand /f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not register KMOS appearance in the default profile.' }
    $registration = & reg.exe query $runKey /v kmos.appearance
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the default-profile startup entry.' }
    if (-not ($registration -match [regex]::Escape($runCommand))) {
        throw 'The default-profile startup entry does not match the runner.'
    }
    $registration
} finally {
    & reg.exe unload $hiveRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not unload $hiveRoot; do not create a user until this is resolved." }
}
# Remove only the obsolete KMOS hand-off from prior versions of this guide.
$oldSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\kmos.appearance'
if (Test-Path -LiteralPath $oldSetupKey) { Remove-Item -LiteralPath $oldSetupKey -Force }
```

The block backs up `C:\Users\Default\NTUSER.DAT` once under
`C:\ProgramData\kmos\scripts`, loads the default
profile, prints the registered `Run` command for verification, and unloads
the profile. Only accounts **created afterward** inherit that entry. At their
sign-in it logs a start to `%LOCALAPPDATA%\kmos-appearance.log`, waits 30
seconds for the desktop, applies the appearance, then removes the entry only
after completion; an interrupted run retries on the next sign-in. The earlier
retry worked when registered manually for an existing test user; the new
default-profile registration subsequently **also worked on a fresh account**.
That first sign-in took a long time: allow Windows to finish creating the
profile and the runner to finish after the desktop appears. The runner itself
waits 30 seconds; do not shorten the delay without another fresh-account test.

#### Retest an interrupted first login (test VM only)

If an existing test account already lost its one-shot startup entry, sign in
as the affected test user and register the retry below. Installing the new
default-profile entry does **not** change an existing account's profile.
Do not use this to reset someone else's personalized desktop. Sign out and
back in, allow up to two minutes on a slow VM, and inspect `%LOCALAPPDATA%\kmos-appearance.log`
if the wallpaper is still missing.

```powershell
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item -Path $runKey -Force | Out-Null
Set-ItemProperty -Path $runKey -Name 'kmos.appearance' -Value 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\kmos\scripts\Start-KmosAppearance.ps1'
```

Mode B procedure:
1. run `Stage Wallpaper`
2. run `Apply Current User Wallpaper and Dark Mode`
3. verify the current user looks exactly right and can still personalize it
4. optionally restart or sign out/sign back in to check that the current user's wallpaper persists
5. for new-user inheritance, run `Capture and Replay the Current User Appearance for New Users` **before** creating those accounts; the default-profile version passed a fresh-account VM test, but first sign-in can be slow

Mode B starts with the current user. It does not include the policy-enforcement block from Mode A.

If wallpaper or personalization behaves inconsistently, restart or sign out
and back in before proceeding. Do not use Mode B on top of Mode A policies;
restore a pre-Mode-A checkpoint first.

This mode leaves wallpaper editable; allow extra time at a new account's first sign-in for Windows profile setup and KMOS appearance replay.

### Shared lock screen: test separately

The lock screen matters for the KMOS look, but this block writes **device-wide**
Windows settings. Test it **separately** from the Mode B desktop check, with a
VM checkpoint first. On the modified Windows 11 Pro VM, the KMOS image appeared
on the lock screen for both the original account and a fresh test account.
News/Spotlight links remained visible. The Spotlight choice in Settings was
already greyed out **before** this block was applied, without a visible
"managed by your organization" message; this test does not establish what
caused that restriction or whether users can change their lock-screen image.
Leave the overlays alone unless a narrow, reversible fix is verified on this
build. If user-editable lock screens are required, do not treat that aspect as
validated; the verified behavior is the **shared image across accounts**.

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

The lock-screen image setting does not disable news/Spotlight links. In the VM,
Settings → Personalization → Lock screen offered **None** as the only lock-screen
status choice, yet the links remained; do not assume the status choice controls
these overlays.

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
```

#### Optional: Lenovo Commercial Vantage

Install this Store-backed app on a Lenovo computer if you want its
hardware-specific management features. It may also install on other hardware,
but it is not required for KMOS or useful for testing Lenovo features in QEMU.
The Store package **did install successfully** in the Windows 11 QEMU VM;
Lenovo hardware features were not tested there.

```powershell
winget install --id 9NR5B8GVVM13 --exact --source msstore --accept-package-agreements --accept-source-agreements
```

### Install and Verify OpenSSH

The **client** lets Windows SSH into other machines; the **server** lets other
machines SSH into Windows. Copy the first block from this guide **inside the
VM** into the built-in **Windows PowerShell (Admin)** (`powershell.exe`, version
5.1), **not PowerShell Preview** (`pwsh.exe`, version 7). The Windows DISM
capability commands can fail with "Class not registered" in Preview. The block
checks its PowerShell edition before touching Windows, then checks each optional feature,
skips those already installed, and installs only missing ones. These are the
**same Windows capabilities** used by the older guide: if Windows cannot
download a missing feature, installation can still take minutes or fail.
Stop on an error rather than continuing to service or firewall setup.

```powershell
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1 (powershell.exe), not PowerShell Preview, for Windows capability installation.'
}
foreach ($name in @('OpenSSH.Client~~~~0.0.1.0', 'OpenSSH.Server~~~~0.0.1.0')) {
    $feature = Get-WindowsCapability -Online -Name $name -ErrorAction Stop
    if (-not $feature) { throw "Windows did not return a capability state for $name. Stop here." }
    if ($feature.State -eq 'Installed') {
        Write-Host "$name is already installed; skipping."
        continue
    }
    if ($feature.State -ne 'NotPresent') { throw "Unexpected $name state: $($feature.State)" }
    Write-Host "Installing $name ..."
    $result = Add-WindowsCapability -Online -Name $name -ErrorAction Stop
    if (-not $result) { throw "$name installation failed; stop here. Do not configure sshd or the firewall." }
    if ($result.RestartNeeded) {
        Write-Warning 'Restart Windows, then rerun this block before configuring sshd.'
        break
    }
    $feature = Get-WindowsCapability -Online -Name $name -ErrorAction Stop
    if ($feature.State -ne 'Installed') { throw "$name did not finish installing: $($feature.State)" }
}
```

**VM finding:** With built-in Windows PowerShell 5.1 on the modified Windows
11 ISO, the OpenSSH Server download failed with `0x80240438` (Windows Update
endpoint unreachable); the server remained `NotPresent`. Do **not** run the
service/firewall block after this error or assume OpenSSH Server is installed.
Microsoft documents this error and the need for a working update source or a
matching Features on Demand package in
[its OpenSSH installation troubleshooting guide](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/cant-install-openssh-features).
Do not clear broad Windows Update or organization policy keys to work around
it.

#### VM fallback: Microsoft Win32-OpenSSH MSI

If Windows Update cannot supply the server, the official
[Win32-OpenSSH release](https://github.com/PowerShell/Win32-OpenSSH/releases/tag/10.4.0.0p1-Preview)
provides a small MSI that installs **both client and server** by default,
without using Windows Features on Demand. This particular release is
explicitly **preview/non-production ready**; use it for this VM test, not
as an unannounced replacement on production machines. You are responsible
for updating a manually installed MSI later. In Windows PowerShell (Admin),
copy the following from this guide inside the VM:

```powershell
$msi = Join-Path $env:TEMP 'OpenSSH-Win64-v10.4.0.0.msi'
Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/OpenSSH-Win64-v10.4.0.0.msi' -OutFile $msi
if ((Get-FileHash -Path $msi -Algorithm SHA256).Hash -ne '788D8643464A01EB63640A2FD746F9ED23D106B5A901A35F88DC8CD40E446AC9') { throw 'OpenSSH download checksum mismatch; do not install.' }
$install = Start-Process msiexec.exe -ArgumentList "/i `"$msi`"" -Wait -PassThru
if ($install.ExitCode -notin @(0, 3010)) { throw "OpenSSH MSI failed: $($install.ExitCode)" }
if ($install.ExitCode -eq 3010) { Write-Warning 'Restart Windows before configuring OpenSSH.' }
```

The pinned SHA-256 is from the release asset. Do not run the service/firewall
block if the checksum or MSI installation fails.

Only after **both** Windows components show `Installed` **or** the MSI succeeds,
run this separate block in
Windows PowerShell (Admin). Windows may already have created its own inbound
SSH firewall rule when the server was installed. This block does **not** create
a duplicate; if no rule exists, it adds one limited to the **Private** network
profile and **local subnet**. Review existing rules before using SSH on a
real network.

```powershell
Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
if ((Get-Service sshd -ErrorAction Stop).Status -ne 'Running') { Start-Service sshd -ErrorAction Stop }
$rule = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
if (-not $rule) { $rule = Get-NetFirewallRule -Name KMOS-SSH-In-Private-LAN -ErrorAction SilentlyContinue }
if (-not $rule) {
    $rule = New-NetFirewallRule -Name KMOS-SSH-In-Private-LAN -DisplayName 'KMOS OpenSSH (private LAN)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Private -RemoteAddress LocalSubnet -ErrorAction Stop
}
$rule | Select-Object Name, Enabled, Profile, Action
Get-Service sshd
```

If an existing rule is disabled, the block reports it but does not override
that deliberate setting. Verify both sides with this **read-only** block;
it prints a single clear result instead of the longer network-test output:

```powershell
$client = Get-Command ssh.exe -ErrorAction Stop
if ((Get-Service sshd -ErrorAction Stop).Status -ne 'Running') { throw 'SSH server is not running.' }
if (-not (Test-NetConnection -ComputerName localhost -Port 22 -InformationLevel Quiet)) { throw 'SSH server is not listening on port 22.' }
Write-Host "SSH READY locally: client $($client.Source); server listening on port 22."
```

This checks that the client is available and the server accepts local TCP
connections; it does not test authentication or remote reachability.

This only configures the **Windows guest**. QEMU's user-mode network still
needs separate host-side port forwarding to allow SSH from the host into the
VM; that is not part of these Windows blocks.

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
