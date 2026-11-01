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
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/windows/assets/wallpapers/kmos-wallpaper.png' -OutFile $wallpaperPath
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
The block was tested on a new VM account; allow extra time for its first
sign-in.

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
after completion; an interrupted run retries on the next sign-in. The default-profile registration passed a fresh-account VM test.
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

Run these on a fresh Windows 11 machine with internet access.

### Install Core Tools

```powershell
winget install --id Git.Git --exact --source winget
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
machines SSH into Windows. **Copy and run this one block** from the guide
inside the VM, in the Windows-supplied **Windows PowerShell (Admin)**
(`powershell.exe`). It installs both when needed, starts `sshd`, creates
only a missing firewall rule, and prints `SSH READY locally` after a client
and server check. Rerunning it skips work already completed.

On a normal Windows machine it uses the supported Windows optional features,
which Windows services through updates. On this QEMU test VM, whose Windows
Update feature download failed with `0x80240438`, it instead uses a pinned
Microsoft Win32-OpenSSH MSI. That release is **Preview/non-production ready**
and needs manual updates; do not use the QEMU fallback on a real machine.
The VM-only Public-network firewall rule permits port 22 **only from QEMU's
host gateway `10.0.2.2`**, not from arbitrary network machines.

```powershell
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell (powershell.exe).'
}
$computer = Get-CimInstance Win32_ComputerSystem
$isKmosVm = $computer.Manufacturer -match 'QEMU' -or $computer.Model -match 'QEMU|Q35'
if ($isKmosVm) {
    $msiClient = Join-Path $env:ProgramFiles 'OpenSSH\ssh.exe'
    if (-not (Test-Path $msiClient) -or -not (Get-Service sshd -ErrorAction SilentlyContinue)) {
        $msi = Join-Path $env:TEMP 'OpenSSH-Win64-v10.4.0.0.msi'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/OpenSSH-Win64-v10.4.0.0.msi' -OutFile $msi
        if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne '788D8643464A01EB63640A2FD746F9ED23D106B5A901A35F88DC8CD40E446AC9') { throw 'OpenSSH download checksum mismatch; do not install.' }
        $install = Start-Process msiexec.exe -ArgumentList "/i `"$msi`"" -Wait -PassThru
        if ($install.ExitCode -notin @(0, 3010)) { throw "OpenSSH MSI failed: $($install.ExitCode)" }
        if ($install.ExitCode -eq 3010) { throw 'Restart Windows, then rerun this block.' }
    }
} else {
    foreach ($name in @('OpenSSH.Client~~~~0.0.1.0', 'OpenSSH.Server~~~~0.0.1.0')) {
        $feature = Get-WindowsCapability -Online -Name $name -ErrorAction Stop
        if (-not $feature) { throw "Cannot check $name; stop here." }
        if ($feature.State -eq 'Installed') { continue }
        if ($feature.State -ne 'NotPresent') { throw "Unexpected $name state: $($feature.State)" }
        $result = Add-WindowsCapability -Online -Name $name -ErrorAction Stop
        if (-not $result) { throw "$name installation failed; stop here." }
        if ($result.RestartNeeded) { throw 'Restart Windows, then rerun this block.' }
        if ((Get-WindowsCapability -Online -Name $name).State -ne 'Installed') { throw "$name did not finish installing." }
    }
}
Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
if ((Get-Service sshd -ErrorAction Stop).Status -ne 'Running') { Start-Service sshd -ErrorAction Stop }
if ($isKmosVm) {
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

If the install fails, stop; the block does not continue to firewall setup.
On a real machine, check the existing firewall rule's scope before allowing
remote access. `SSH READY locally` tests the client and listening server, not
authentication or remote reachability. If Windows reports a restart is
needed, restart and run the **same block** again.

This only configures the **Windows guest**. The test VM launcher, when started
with `./start-win11.sh --boot`, forwards **host `127.0.0.1:2222` → guest port `22`** on the
next VM boot. This host-only forward does not expose SSH to other network
machines. From the Linux host, test with `ssh -p 2222 <Windows-user>@127.0.0.1`
and enter the Windows account password only into your own SSH prompt. If the
connection is refused, check the guest's active network profile against the
Windows firewall rule before changing its scope.

**VM result:** With the narrow Public-network rule, the Linux host received the Windows
OpenSSH 10.4 server banner and host keys through `127.0.0.1:2222`. Host-to-VM
network reachability is verified. An authenticated SSH sign-in from the Linux
host to the VM's `itadmin` account also succeeded. From Windows in the VM,
`ssh kamilo@10.0.2.2` reached an authenticated shell on the Linux host as
well. **Both SSH directions passed in this VM.** Keep passwords private and
remember that the Preview MSI must be updated manually.

### Install Fonts

```powershell
$fontWork = Join-Path $env:TEMP 'kmos-fonts'
New-Item -ItemType Directory -Path $fontWork -Force | Out-Null

$fontApiBase = 'https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts'
$families = @('kappa-text', 'kappa-page', 'kappa-mark', 'kappa-form', 'kappa-mono', 'kappa-spin')

foreach ($family in $families) {
    $familyDir = Join-Path $fontWork $family
    New-Item -ItemType Directory -Path $familyDir -Force | Out-Null
    $items = Invoke-RestMethod -Uri "$fontApiBase/$family/ttf?ref=main"

    foreach ($item in $items) {
        if ($item.download_url -and $item.name -like '*.ttf') {
            Invoke-WebRequest -Uri $item.download_url -OutFile (Join-Path $familyDir $item.name)
        }
    }

}

explorer.exe $fontWork
```

This **downloads** the current Kappa font system to a temporary folder; it
does not install it. To install all downloaded styles for **all Windows
accounts** in one pass, search for `*.ttf` in the open `kmos-fonts` folder
(including its subfolders), select the results with **Ctrl+A**, then right-click
→ **Show more options** → **Install for all users** and approve the administrator
prompt. This also selects the optional Kappa Page alpha; omit its files if you
do not want it. This batch-selection shortcut has not yet been tested in the
VM. The tested alternative is to open each family subfolder, select its `.ttf`
files, and choose **Install for all users**. The five frozen-baseline families
are:
- `Kappa Text`
- `Kappa Mark`
- `Kappa Form`
- `Kappa Mono`
- `Kappa Spin`

The download also includes `Kappa Page` (four `.ttf` files). It is a usable
**alpha**, not a frozen baseline; install it only if you want to test the new
print/document family. Existing font installations do not change just because
you rerun the download block.

### Set Windows Terminal Default Font

Open **Windows Terminal → dropdown arrow → Settings → Profiles → Defaults →
Appearance**. Set **Font face** to `Kappa Mono` and **Font size** to `12`, then
click **Save**. Close and reopen Terminal to verify it. Defaults apply to
profiles without their own font override; if a profile still shows another
font, change that profile's **Appearance** setting individually. This changes
only the current Windows account's Terminal preferences, not other users'
settings. Using Terminal Settings avoids rewriting the whole `settings.json`
or discarding existing personalization.

### Install Starship

Starship is a separate program, not a PowerShell installation. Installing it
alone does **not** enable its prompt in Windows PowerShell or over SSH.
Machine-wide profile and SSH-shell configuration must be tested in the clean
VM before it is added to this guide.

```powershell
winget install --id Starship.Starship --exact --source winget --scope machine
```

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
- verify the Terminal font; test Starship only after its PowerShell and SSH setup has been verified
