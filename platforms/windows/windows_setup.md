# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete. For a single-block alternative for Phases 1–3, see [win_fast_track.md](win_fast_track.md).

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
            $customGiB = (Read-Host 'Total Windows space in GiB (e.g. 33 or 33 GiB; type cancel to stop)').Trim()
            if ($customGiB -eq 'cancel') {
                Write-Host 'Leaving the disk layout unchanged.'
                return
            }
            $requestedGiB = 0.0
            if ($customGiB -match '^(?<number>\d+(?:\.\d+)?)\s*(?:GiB)?$' -and
                [double]::TryParse($Matches['number'], [Globalization.NumberStyles]::AllowDecimalPoint,
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

Set editable KMOS defaults for the current account and register one-time setup
for other accounts before creating additional users. If organization policy
blocks personalization, determine whether the computer is still managed; do
not delete broad Windows policy keys to work around it.

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

$currentName = $env:COMPUTERNAME
Write-Host "Current computer name: $currentName"

$newName = (Read-Host "New computer name (Enter keeps $currentName)").Trim()
if (-not $newName -or $newName -eq $currentName) {
    Write-Host 'Keeping the current computer name; no changes made.'
} elseif (-not (Prompt-YesNo -Prompt "Rename this computer to $newName?" -Default $false)) {
    Write-Host 'Computer name unchanged.'
} else {
    Rename-Computer -NewName $newName -ErrorAction Stop
    Write-Host "Computer renamed to $newName. Use Restart (not Shut down) to apply the name."
}
```

### Stage Wallpaper

```powershell
$wallpaperDir = Join-Path $env:PUBLIC 'Pictures\kmos'
$wallpaperPath = Join-Path $wallpaperDir 'kmos-wallpaper.png'
New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/wallpapers/kmos-wallpaper.png' -OutFile $wallpaperPath
```

Shared wallpaper path:

```powershell
Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
```

### Set Current User Wallpaper and Dark Mode

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

### Capture and Replay the Current User Appearance for New Users

This captures the current account's appearance and replays it at the first
sign-in of **future** accounts. It uses the shared KMOS wallpaper, leaves
personalization editable, and does not reset existing accounts. Run in
Windows PowerShell (Admin) on the account whose appearance you want to copy.
Allow extra time for a new account's first sign-in.

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
```

The block backs up `C:\Users\Default\NTUSER.DAT` once under
`C:\ProgramData\kmos\scripts`, loads the default
profile, prints the registered `Run` command for verification, and unloads
the profile. Only accounts **created afterward** inherit that entry. At their
sign-in it logs a start to `%LOCALAPPDATA%\kmos-appearance.log`, waits 30
seconds for the desktop, applies the appearance, then removes the entry only
after completion; an interrupted run retries on the next sign-in.
That first sign-in took a long time: allow Windows to finish creating the
profile and the runner to finish after the desktop appears. The runner itself
waits 30 seconds; do not shorten the delay without another fresh-account test.

### Shared Lock Screen: Picture for All Accounts at Sign-In

Run this once in Windows PowerShell (Admin) **after** staging the shared image
and applying the current account's desktop appearance. It registers a
machine-wide sign-in entry that runs as each Windows user **once**, setting
that account's KMOS lock-screen Picture without a device-wide lock-screen
policy. Existing accounts receive it at their next sign-in; future accounts
receive it at their first sign-in. Because it does not continuously enforce the
picture, users can subsequently choose another image in Settings. An account
that never signs in does not receive this per-user setting; the pre-sign-in
screen is not independently configured.

```powershell
& {
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from Windows PowerShell (Admin).' }
$image = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Missing KMOS image: $image" }
$dir = Join-Path $env:ProgramData 'kmos\scripts'
$helper = Join-Path $dir 'Apply-KmosLockScreenOnce.ps1'
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$name = 'KMOSLockScreenOnce'
$command = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $helper + '"'
$existing = (Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue).$name
if ($existing -and $existing -ne $command) { throw "Existing $name startup entry differs; not replacing it." }
$content = @'
$ErrorActionPreference = 'Stop'
$marker = 'HKCU:\Software\kmos\LockScreen'
$log = Join-Path $env:LOCALAPPDATA 'kmos-lockscreen.log'
if ((Get-ItemProperty -Path $marker -Name Applied -ErrorAction SilentlyContinue).Applied -eq 1) { exit 0 }
try {
    Add-Content -LiteralPath $log -Value "KMOS lock-screen started $(Get-Date -Format o)"
    Start-Sleep -Seconds 30
    $image = Join-Path $env:PUBLIC 'Pictures\kmos\kmos-wallpaper.png'
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Missing KMOS image: $image" }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
    [Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime] | Out-Null
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    if (-not $asTask) { throw 'Windows Runtime async adapter unavailable' }
    $fileTask = $asTask.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @([Windows.Storage.StorageFile]::GetFileFromPathAsync($image)))
    $file = $fileTask.GetAwaiter().GetResult()
    $action = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file)
    $actionMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    } | Select-Object -First 1
    if (-not $actionMethod) { throw 'Windows Runtime action adapter unavailable' }
    $actionMethod.Invoke($null, @($action)).GetAwaiter().GetResult()
    $spotlight = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $slideshow = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen'
    New-Item -Path $spotlight -Force | Out-Null
    New-Item -Path $slideshow -Force | Out-Null
    New-ItemProperty -Path $spotlight -Name RotatingLockScreenEnabled -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $slideshow -Name SlideshowEnabled -Value 0 -PropertyType DWord -Force | Out-Null
    New-Item -Path $marker -Force | Out-Null
    New-ItemProperty -Path $marker -Name Applied -Value 1 -PropertyType DWord -Force | Out-Null
    Add-Content -LiteralPath $log -Value "KMOS lock-screen completed $(Get-Date -Format o)"
} catch {
    Add-Content -LiteralPath $log -Value "KMOS lock-screen failed: $_"
    exit 1
}
'@
New-Item -ItemType Directory -Path $dir -Force | Out-Null
if (Test-Path -LiteralPath $helper) {
    if ((Get-Content -Raw -LiteralPath $helper).TrimEnd([char[]]@("`r", "`n")) -cne $content) {
        throw "Existing helper differs: $helper. Not overwriting it."
    }
} else {
    Set-Content -LiteralPath $helper -Value $content -Encoding ASCII
}
if (-not $existing) {
    New-ItemProperty -Path $runKey -Name $name -Value $command -PropertyType String | Out-Null
}
Write-Host "Registered $name for all accounts. At next sign-in, wait 30 seconds and inspect %LOCALAPPDATA%\kmos-lockscreen.log."
Write-Host "To stop future runs: Remove-ItemProperty -Path '$runKey' -Name '$name' (Admin). This does not undo accounts already configured."
}
```

After registering, sign out and back in to set the **current** account too.
Allow at least 30 seconds after the desktop loads, then check
`%LOCALAPPDATA%\kmos-lockscreen.log` for `KMOS lock-screen completed`.
Confirm Settings → Personalization → Lock screen shows **Picture**, the
selector remains editable, and **Win+L** shows the KMOS image. Test again
with a new account in the **last phase**. Failed attempts log an error and
retry on the next sign-in. To stop future runs, remove only the
`KMOSLockScreenOnce` value from
`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` as admin;
this does not undo accounts already configured. Do not apply the old
`PersonalizationCSP` lock-screen image keys: they can lock personalization.

---

## Phase 3: Core Tools

Run these on a Windows 11 machine with internet access.

### Ensure WinGet Is Available

WinGet comes with [Microsoft App Installer](https://apps.microsoft.com/detail/9nblggh4nns1).
Install App Installer from that link if it is absent. On a new Windows account,
registration can lag behind first sign-in; run this in the account installing
the tools:

```powershell
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
}
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet is unavailable. Install App Installer and open a new PowerShell window before continuing.'
}
winget --version
if ($LASTEXITCODE -ne 0) { throw 'WinGet did not start; stop before installing tools.' }
```

### Install Core Tools

```powershell
winget install --id Git.Git --exact --source winget --scope machine
if ($LASTEXITCODE -ne 0) { throw "WinGet failed installing Git.Git ($LASTEXITCODE); stop here." }
winget install --id GNU.Nano --exact --source winget --scope machine
if ($LASTEXITCODE -ne 0) { throw "WinGet failed installing GNU.Nano ($LASTEXITCODE); stop here." }
winget install --id KDE.Kate --exact --source winget --scope machine
if ($LASTEXITCODE -ne 0) { throw "WinGet failed installing KDE.Kate ($LASTEXITCODE); stop here." }
winget install --id Mozilla.Firefox.DeveloperEdition --exact --source winget --scope machine
if ($LASTEXITCODE -ne 0) { throw "WinGet failed installing Mozilla.Firefox.DeveloperEdition ($LASTEXITCODE); stop here." }
```

Okular is not included in this unattended core-tool list: the `KDE.Okular`
WinGet-source installer returned HTTP 404 in the VM, and the alternative
Microsoft Store app has not been verified for every account. Do not treat
Okular as installed by this guide.

#### Optional: Lenovo Commercial Vantage

Install this Store-backed app on a Lenovo computer if you want its
hardware-specific management features. It is not required for KMOS on
non-Lenovo hardware.

```powershell
winget install --id 9NR5B8GVVM13 --exact --source msstore --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "Lenovo Commercial Vantage installation failed ($LASTEXITCODE)." }
```

### Install and Verify OpenSSH

Run this one block in **Windows PowerShell (Admin)**. It installs a pinned
Microsoft Win32-OpenSSH MSI if `sshd` is missing; it does **not** use Windows
Update or `Add-WindowsCapability`. The x64 MSI and QEMU host-only firewall
rule worked in the test installation. Other hardware and Windows editions
still need their own SSH login test. **Microsoft labels this MSI Preview and
non-production-ready**; unlike the built-in Windows feature, it requires
manual security updates. Review that tradeoff before deploying it to other
computers.

```powershell
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell (powershell.exe).' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Windows PowerShell as Administrator.' }

$computer = Get-CimInstance Win32_ComputerSystem
$isQemu = $computer.Manufacturer -match 'QEMU' -or $computer.Model -match 'QEMU|Q35'
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    $arch = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)
    if ($arch -eq 9) {
        $asset = 'OpenSSH-Win64-v10.4.0.0.msi'
        $expectedHash = '788D8643464A01EB63640A2FD746F9ED23D106B5A901A35F88DC8CD40E446AC9'
    } elseif ($arch -eq 12) {
        $asset = 'OpenSSH-ARM64-v10.4.0.0.msi'
        $expectedHash = '75FA139D8975EEDB706D9180F454E2148AF09D417692825F383FE00610B00E21'
    } else { throw "Unsupported OpenSSH MSI architecture: $arch" }
    $msi = Join-Path $env:TEMP $asset
    $url = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/$asset"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $msi -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $expectedHash) { throw 'OpenSSH MSI checksum mismatch; do not install.' }
    $install = Start-Process msiexec.exe -ArgumentList "/i `"$msi`"" -Wait -PassThru -ErrorAction Stop
    if ($install.ExitCode -notin @(0, 3010)) { throw "OpenSSH MSI failed: $($install.ExitCode)" }
    if ($install.ExitCode -eq 3010) { throw 'Restart Windows, then rerun this block.' }
}
Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
if ((Get-Service sshd -ErrorAction Stop).Status -ne 'Running') { Start-Service sshd -ErrorAction Stop }
if ($isQemu) {
    if (-not (Get-NetFirewallRule -Name KMOS-SSH-QEMU-Host -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name KMOS-SSH-QEMU-Host -DisplayName 'KMOS SSH from QEMU host only' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Public -RemoteAddress 10.0.2.2 -ErrorAction Stop | Out-Null
    }
} elseif (-not (Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue) -and
          -not (Get-NetFirewallRule -Name KMOS-SSH-In-Private-LAN -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name KMOS-SSH-In-Private-LAN -DisplayName 'KMOS OpenSSH (private LAN)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Private -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null
}
$client = Get-Command ssh.exe -ErrorAction Stop
if (-not (Test-NetConnection -ComputerName localhost -Port 22 -InformationLevel Quiet)) { throw 'SSH server is not listening on port 22.' }
Write-Host "SSH READY locally: client $($client.Source); server listening on port 22."
}
```

`SSH READY locally` does not test authentication or remote reachability.
Keep a local administrator console open until a fresh SSH login succeeds. On
the QEMU test launcher the Linux host connects to `127.0.0.1` port `2222`;
on other machines use the Windows computer's address and check the active
firewall rule's profiles and remote-address scope. Keep passwords private and
verify any unexpected SSH host-key change before accepting it.

### Install All Kappa Fonts and Set Terminal Defaults

Run this **one block** in Windows PowerShell (Admin). It installs the TTF files
in all six Kappa families for all users (27 files in the tested VM), including
**Kappa Page (alpha)**,
then applies Kappa Mono, size 12, as the editable Windows Terminal default for
the installing account. It registers a one-time sign-in action for existing and
future accounts. Each account gets its own settings backup and marker; changing
the font afterward does not trigger a reset. It does not install PowerShell
Preview. The fonts are fetched from the current Kappa repository; existing
files with different contents are not overwritten.

The font install and new-user Terminal appearance worked in the QEMU VM;
other Windows builds and user configurations have **not** been fleet-tested.
The block creates helper scripts **on Windows under ProgramData at runtime**;
no `.ps1` files are stored in this repository. Existing Terminal JSON comments
and formatting may be removed when the settings are merged, but other settings
are preserved and the original is backed up as `settings.json.kmos-backup`.

```powershell
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell (powershell.exe).' }
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
    $items = Invoke-RestMethod -Uri "$api/$family/ttf?ref=main" -ErrorAction Stop
    $files = @($items | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ttf$' -and $_.download_url })
    if (-not $files.Count) { throw "No TTF files for $family" }
    foreach ($item in $files) {
        if ($item.name -isnot [string]) { throw "Unexpected GitHub API response for $family (filename is not a string)" }
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

$code = @'
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
$replaceBackup = "$path.kmos-replace-$PID.bak"
if (Test-Path -LiteralPath $replaceBackup) { throw "Temporary replacement backup already exists; not overwriting: $replaceBackup" }
try {
    [IO.File]::WriteAllText($temp, $updated, ([Text.UTF8Encoding]::new($false)))
    [IO.File]::Replace($temp, $path, $replaceBackup)
    Remove-Item -LiteralPath $replaceBackup -ErrorAction SilentlyContinue
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
Write-Host "Applied Kappa Mono, size 12 to $path; original backed up at $backup"
}
'@
$code = $code.TrimEnd("`r", "`n")
$dir = Join-Path $env:ProgramData 'kmos\terminal-font'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
& icacls.exe $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-11:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect Terminal font runtime directory; no sign-in entry registered.' }
$apply = Join-Path $dir 'Apply-KmosTerminalFont.ps1'
if ((Test-Path -LiteralPath $apply) -and (Get-Content -LiteralPath $apply -Raw).TrimEnd("`r", "`n") -ne $code) { throw "Different runtime script already exists: $apply" }
if (-not (Test-Path -LiteralPath $apply)) { Set-Content -LiteralPath $apply -Value $code -Encoding UTF8 -ErrorAction Stop }

$runner = Join-Path $dir 'Start-KmosTerminalFont.ps1'
$runnerCode = @'
$ErrorActionPreference = 'Stop'
$marker = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font-applied'
if (Test-Path -LiteralPath $marker -PathType Leaf) { return }
$log = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font.log'
try {
    Start-Sleep -Seconds 30
    if (-not (Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue)) { throw 'Windows Terminal package not yet registered for this account; will retry at next sign-in.' }
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
        [IO.File]::WriteAllText($settings, '{}', ([Text.UTF8Encoding]::new($false)))
    }
    & 'C:\ProgramData\kmos\terminal-font\Apply-KmosTerminalFont.ps1' *>> $log
    if (-not $?) { throw 'Terminal font merge failed.' }
    [IO.File]::WriteAllText($marker, (Get-Date -Format o))
    Add-Content -LiteralPath $log -Value 'KMOS Terminal font applied once.'
} catch {
    Add-Content -LiteralPath $log -Value "KMOS Terminal font failed at $(Get-Date -Format o): $_"
    exit 1
}
'@
if ((Test-Path -LiteralPath $runner) -and (Get-Content -LiteralPath $runner -Raw).TrimEnd("`r", "`n") -ne $runnerCode.TrimEnd("`r", "`n")) { throw "Different runtime runner already exists: $runner" }
if (-not (Test-Path -LiteralPath $runner)) { Set-Content -LiteralPath $runner -Value $runnerCode -Encoding UTF8 -ErrorAction Stop }

$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$command = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\ProgramData\kmos\terminal-font\Start-KmosTerminalFont.ps1"'
$existing = (Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -ErrorAction SilentlyContinue).'kmos.terminalFont'
if ($existing -and $existing -ne $command) { throw 'A different kmos.terminalFont sign-in entry exists; not overwriting.' }
if (-not $existing) { New-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -Value $command -PropertyType String -ErrorAction Stop | Out-Null }
if ((Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont').'kmos.terminalFont' -ne $command) { throw 'Sign-in entry could not be verified.' }
Write-Host 'Automatic one-time Terminal font setup registered for existing and future users.'

# Apply now to the installing account; other accounts run the same merge at sign-in.
$marker = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font-applied'
if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
    if (Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue) {
        $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
            [IO.File]::WriteAllText($settings, '{}', ([Text.UTF8Encoding]::new($false)))
        }
        & $apply
        [IO.File]::WriteAllText($marker, (Get-Date -Format o))
    } else { Write-Warning 'Terminal is not yet registered for this account; sign-in setup will retry later.' }
}
}
```

On first sign-in, appearance, lock-screen, and Terminal helpers start
independently and each waits 30 seconds. Allow Windows to finish creating the
profile, then wait for their **completed** log entries before checking the
result; 30 seconds alone does not guarantee completion. None downloads fonts
or initiates a restart at sign-in. If Windows restarts mid-run, a helper without
its completion marker retries at the next sign-in; the Terminal helper may
have no log at all if interrupted during its initial delay. Reopen Terminal
and check **Profiles → Defaults → Appearance** for Kappa Mono, size 12; if it
did not apply, inspect `%LOCALAPPDATA%\kmos-terminal-font.log` for that account.
Individual profiles with their own font overrides may display another font.

### Configure Starship for Windows PowerShell and SSH

Run this one block from a **local Windows PowerShell (Admin)** session, not
through SSH. It installs Starship for the machine, stages four KMOS presets,
configures the Windows-supplied PowerShell's all-users profile, and selects
that PowerShell as the SSH server's default shell. It does **not** install
PowerShell Preview. It can set `LocalMachine` execution policy to
`RemoteSigned` if required to load the all-users profile on an unmanaged
machine; it refuses restrictive organization policies. This affects every
Windows account, so back up the machine or establish a rollback point first,
and keep a local administrator console open until a fresh SSH login works.

```powershell
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use the Windows-supplied PowerShell (powershell.exe).' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open Windows PowerShell as Administrator.' }
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { throw 'Install OpenSSH Server first.' }
$policy = @{}
foreach ($entry in (Get-ExecutionPolicy -List)) { $policy[$entry.Scope.ToString()] = $entry.ExecutionPolicy.ToString() }
if ($policy['MachinePolicy'] -notin @('Undefined','RemoteSigned','Unrestricted','Bypass') -or
    $policy['UserPolicy'] -notin @('Undefined','RemoteSigned','Unrestricted','Bypass') -or
    $policy['CurrentUser'] -notin @('Undefined','RemoteSigned','Unrestricted','Bypass') -or
    $policy['LocalMachine'] -eq 'AllSigned') { throw 'A restrictive higher-priority policy or AllSigned is present. No installation or SSH change attempted.' }

if (-not (Get-Command starship.exe -ErrorAction SilentlyContinue)) {
    winget install --id Starship.Starship --exact --source winget --scope machine
    if ($LASTEXITCODE -ne 0) { throw 'Starship installation failed; SSH shell unchanged.' }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$starship = Get-Command starship.exe -ErrorAction SilentlyContinue
if (-not $starship -or -not (Test-Path -LiteralPath $starship.Source -PathType Leaf)) { throw 'Starship executable not found after installation. Reopen local PowerShell and retry; SSH shell unchanged.' }
if ($starship.Source.StartsWith($env:USERPROFILE,[StringComparison]::OrdinalIgnoreCase)) { throw "Starship is per-user ($($starship.Source)); SSH shell unchanged. Resolve machine-wide install before continuing." }
& $starship.Source --version
if ($LASTEXITCODE -ne 0) { throw 'Starship executable did not start; SSH shell unchanged.' }

$dir = Join-Path $env:ProgramData 'kmos\starship-presets'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
foreach ($preset in @('holow-light','holow-dark','filled-light','filled-dark')) {
    $dest = Join-Path $dir "${preset}.toml"
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/starship-presets/${preset}.toml" -OutFile $dest
    }
}
$config = Join-Path $dir 'holow-light.toml'
$profilePath = $PROFILE.AllUsersAllHosts
$profileDir = Split-Path -Parent $profilePath
$safeExe = $starship.Source.Replace("'","''")
$safeConfig = $config.Replace("'","''")
$profileContent = @"
# KMOS Starship
`$env:STARSHIP_CONFIG = '$safeConfig'
Invoke-Expression (& '$safeExe' init powershell)
"@
if (Test-Path -LiteralPath $profilePath) {
    $existingProfile = Get-Content -Raw -LiteralPath $profilePath
    if ($existingProfile -match '# KMOS Starship') {
        if (-not $existingProfile.Contains("`$env:STARSHIP_CONFIG = '$safeConfig'") -or
            -not $existingProfile.Contains("Invoke-Expression (& '$safeExe' init powershell)")) {
            throw "Existing KMOS Starship profile differs: $profilePath. Not replacing it."
        }
    } else {
        if ($existingProfile -match '(?i)starship.*init\s+powershell') { throw "A different Starship setup already exists in $profilePath; not replacing it." }
        $profileBackup = "$profilePath.kmos-backup"
        if (-not (Test-Path -LiteralPath $profileBackup)) { Copy-Item -LiteralPath $profilePath -Destination $profileBackup -ErrorAction Stop }
        Add-Content -LiteralPath $profilePath -Value "`r`n$profileContent"
        Write-Host "Original all-users profile backed up to $profileBackup"
    }
} else {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Set-Content -LiteralPath $profilePath -Value $profileContent -Encoding ASCII
}

if ($policy['MachinePolicy'] -eq 'Undefined' -and $policy['LocalMachine'] -notin @('RemoteSigned','Unrestricted','Bypass')) {
    $oldLocalPolicy = $policy['LocalMachine']
    Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    Write-Host "LocalMachine policy was $oldLocalPolicy; now RemoteSigned. Record previous value for rollback."
}
if ((Get-ExecutionPolicy) -notin @('RemoteSigned','Unrestricted','Bypass')) { throw 'Effective policy still blocks PowerShell profiles; SSH shell unchanged.' }

$key = 'HKLM:\SOFTWARE\OpenSSH'
$shell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $shell -PathType Leaf)) { throw "Windows-supplied PowerShell not found: $shell" }
$oldShell = (Get-ItemProperty -Path $key -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
if ($oldShell -ne $shell) {
    $backup = Join-Path $env:ProgramData ('kmos\OpenSSH-before-DefaultShell-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.reg')
    & reg.exe export 'HKLM\SOFTWARE\OpenSSH' $backup /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Registry backup failed; SSH shell unchanged.' }
    New-ItemProperty -Path $key -Name DefaultShell -Value $shell -PropertyType String -Force | Out-Null
    Write-Host "Prior DefaultShell: $oldShell (blank means unset); registry backup: $backup"
}
Write-Host "KMOS READY TO TEST locally and over a fresh SSH session; all-users profile: $profilePath; SSH shell: $shell"
}
```

The block preserves an existing PowerShell profile (backing it up before
appending) and exports the OpenSSH registry key before changing `DefaultShell`.
Record any previous execution policy and SSH shell values printed for
rollback. Open a **new local Windows PowerShell** window and verify the KMOS
Starship prompt. Then use a **fresh authenticated SSH login** and verify that
it opens Windows PowerShell with the same prompt. If SSH still opens `cmd.exe`,
restart `sshd` from the local console and reconnect; this can interrupt SSH
sessions. Do not claim success until both fresh sessions have been checked.
If either test fails, use the saved rollback point or restore only the prior
settings rather than repeatedly changing machine-wide configuration. If the
previous `DefaultShell` was absent, remove only that value to restore the
default; importing a registry export alone does not remove newly added values.
Windows Terminal's default profile choice is still a per-account preference.

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

## Phase 5: Optional Chris Titus WinUtil

In an elevated Windows PowerShell session, optionally launch:

```powershell
irm christitus.com/win | iex
```

No particular WinUtil tweak is required by KMOS. Review any settings you choose
before applying them, especially if the machine is managed by an organization.

---

## Phase 6: Additional Users

This is the **last phase**. Create users only after the machine's appearance,
core tools, optional hardware steps, and required reboots are complete.

### Create a Local Administrator

```powershell
$username = Read-Host 'Enter the new local username'
$password = Read-Host 'Enter the password for the new user' -AsSecureString

New-LocalUser -Name $username -Password $password -FullName $username -Description 'kmos local administrator'
Add-LocalGroupMember -Group 'Administrators' -Member $username
```

After creating the user:
- sign in as that user; allow several minutes for Windows to create the
  profile, then wait for completion of all three helpers; if Windows restarts
  during first sign-in, sign in again so interrupted helpers can retry
- verify the editable KMOS desktop wallpaper and dark mode; if missing, check
  `%LOCALAPPDATA%\kmos-appearance.log` rather than changing it manually
- verify the KMOS lock-screen image with **Win+L**, and verify Settings shows
  **Picture** with an editable selector; if missing, check
  `%LOCALAPPDATA%\kmos-lockscreen.log`
- open **Windows Terminal → Settings → Profiles → Defaults → Appearance** and
  verify **Kappa Mono**, size **12**, after its log shows completion; if missing,
  check `%LOCALAPPDATA%\kmos-terminal-font.log` for that account (the font
  files are system-wide, while this editable preference is applied at sign-in)
- open a fresh Windows PowerShell session and verify the KMOS Starship prompt
