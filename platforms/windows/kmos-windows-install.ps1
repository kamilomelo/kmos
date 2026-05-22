[CmdletBinding()]
param(
    [string]$AssetSourceRoot = (Join-Path $PSScriptRoot '..\archlinux\assets'),
    [switch]$SkipTitus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProgramDataRoot = Join-Path $env:ProgramData 'kmos'
$AssetTargetRoot = Join-Path $ProgramDataRoot 'assets'
$ScriptTargetRoot = Join-Path $ProgramDataRoot 'scripts'
$ApplyUserScriptSource = Join-Path $PSScriptRoot 'Apply-KmosWindowsUser.ps1'
$ApplyUserScriptTarget = Join-Path $ScriptTargetRoot 'Apply-KmosWindowsUser.ps1'
$FirefoxDeveloperEditionExe = 'C:\Program Files\Firefox Developer Edition\firefox.exe'
$LockScreenWallpaper = Join-Path $AssetTargetRoot 'wallpapers\kmos-wallpaper.png'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('==> ' + $Message) -ForegroundColor Cyan
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('> ' + $Message) -ForegroundColor Gray
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning $Message
}

function Fail {
    param([Parameter(Mandatory)][string]$Message)
    throw $Message
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-Administrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail 'Run this script from an elevated PowerShell session.'
    }
}

function Prompt-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )

    while ($true) {
        $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        switch -Regex ($answer.Trim()) {
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

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('String','DWord','QWord','Binary','MultiString','ExpandString')]
        [string]$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Resolve-Winget {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        return $winget.Source
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
    } catch {
        Write-Warn 'Could not force App Installer registration. Winget-dependent steps may fail.'
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Fail 'winget is required for the Windows installer.'
    }

    return $winget.Source
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)][string]$WingetPath,
        [Parameter(Mandatory)][string]$Id,
        [string]$Source = 'winget',
        [string[]]$ExtraArgs = @()
    )

    $arguments = @(
        'install',
        '--id', $Id,
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    if ($Source) {
        $arguments += @('--source', $Source)
    }

    if ($ExtraArgs.Count -gt 0) {
        $arguments += $ExtraArgs
    }

    & $WingetPath @arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "winget install failed for $Id"
    }
}

function Install-PowerShellPreview {
    Write-Step 'Installing latest PowerShell preview'

    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases' -Headers @{ 'User-Agent' = 'kmos-windows-install' }
    $preview = $release | Where-Object { $_.prerelease -and -not $_.draft } | Select-Object -First 1
    if (-not $preview) {
        Fail 'Could not determine the latest PowerShell preview release.'
    }

    $architecture = if ([Environment]::Is64BitOperatingSystem -and $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $pattern = "PowerShell-*-win-$architecture.zip"
    $asset = $preview.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
    if (-not $asset) {
        Fail "Could not find a PowerShell preview ZIP for architecture $architecture."
    }

    Ensure-Directory -Path $ProgramDataRoot
    $downloadPath = Join-Path $ProgramDataRoot $asset.name
    $extractRoot = Join-Path $env:ProgramFiles 'PowerShell'
    $installPath = Join-Path $extractRoot '7-preview'

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath
    Ensure-Directory -Path $extractRoot

    if (Test-Path -LiteralPath $installPath) {
        Remove-Item -LiteralPath $installPath -Recurse -Force
    }

    Expand-Archive -LiteralPath $downloadPath -DestinationPath $installPath -Force

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$installPath*") {
        [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $installPath), 'Machine')
    }

    Write-Info "PowerShell preview staged in $installPath"
}

function Show-PartitionSizes {
    param(
        [Parameter(Mandatory)][uint64]$Current,
        [Parameter(Mandatory)][uint64]$Min,
        [Parameter(Mandatory)][uint64]$Max
    )

    Write-Info ("Current C: size: {0:N2} GiB" -f ($Current / 1GB))
    Write-Info ("Minimum supported C: size: {0:N2} GiB" -f ($Min / 1GB))
    Write-Info ("Maximum supported C: size: {0:N2} GiB" -f ($Max / 1GB))
}

function Resize-SystemPartitionIfRequested {
    if (-not (Prompt-YesNo -Prompt 'Shrink the current disk to leave space for another OS?' -Default $false)) {
        Write-Info 'Leaving the disk layout unchanged.'
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
        Fail ("Requested C: size {0:N2} GiB is outside the supported range." -f ($targetSize / 1GB))
    }

    if ($targetSize -ge $currentSize) {
        Fail 'Requested size is not smaller than the current C: partition.'
    }

    Write-Info ("C: will be resized to {0:N2} GiB" -f ($targetSize / 1GB))
    if (-not (Prompt-YesNo -Prompt 'Apply this partition resize now?' -Default $false)) {
        Write-Info 'Skipping partition resize.'
        return
    }

    Resize-Partition -DriveLetter 'C' -Size $targetSize
    Write-Info 'Partition resize completed.'
}

function Test-LenovoSystem {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    return $computer.Manufacturer -match 'Lenovo'
}

function Install-LenovoVantage {
    param([Parameter(Mandatory)][string]$WingetPath)

    if (-not (Test-LenovoSystem)) {
        Write-Info 'Skipping Lenovo Vantage because this machine is not a Lenovo system.'
        return
    }

    if (-not (Prompt-YesNo -Prompt 'Install Lenovo Vantage?' -Default $true)) {
        return
    }

    $edition = (Get-ComputerInfo).WindowsProductName
    $candidates = if ($edition -match 'Home') {
        @(
            @{ Id = '9WZDNCRFJ4MV'; Source = 'msstore'; Name = 'Lenovo Vantage' }
        )
    } else {
        @(
            @{ Id = '9NR5B8GVVM13'; Source = 'msstore'; Name = 'Lenovo Commercial Vantage' },
            @{ Id = '9WZDNCRFJ4MV'; Source = 'msstore'; Name = 'Lenovo Vantage' }
        )
    }

    foreach ($candidate in $candidates) {
        try {
            Write-Step ("Installing {0}" -f $candidate.Name)
            Invoke-WingetInstall -WingetPath $WingetPath -Id $candidate.Id -Source $candidate.Source
            return
        } catch {
            Write-Warn ("Failed to install {0}: {1}" -f $candidate.Name, $_.Exception.Message)
        }
    }
}

function Install-FirefoxDeveloperEdition {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Step 'Installing Firefox Developer Edition'
    Invoke-WingetInstall -WingetPath $WingetPath -Id 'Mozilla.Firefox.DeveloperEdition' -ExtraArgs @('--scope','machine')

    if (Test-Path -LiteralPath $FirefoxDeveloperEditionExe) {
        try {
            Start-Process -FilePath $FirefoxDeveloperEditionExe -ArgumentList '-setDefaultBrowser' -Wait -WindowStyle Hidden
        } catch {
            Write-Warn 'Could not force Firefox Developer Edition as the current-user default browser.'
        }
    }
}

function Get-FirefoxAssociationMap {
    $roots = Get-ChildItem -Path 'HKLM:\SOFTWARE\Clients\StartMenuInternet' -ErrorAction SilentlyContinue
    foreach ($root in $roots) {
        $capPath = Join-Path $root.PSPath 'Capabilities'
        $fileAssociations = Get-ItemProperty -Path (Join-Path $capPath 'FileAssociations') -ErrorAction SilentlyContinue
        $urlAssociations = Get-ItemProperty -Path (Join-Path $capPath 'URLAssociations') -ErrorAction SilentlyContinue
        if ($fileAssociations -and $urlAssociations -and $fileAssociations.'.html' -match 'Firefox') {
            return @{
                '.htm' = $fileAssociations.'.htm'
                '.html' = $fileAssociations.'.html'
                'http' = $urlAssociations.'http'
                'https' = $urlAssociations.'https'
            }
        }
    }

    return $null
}

function Import-FirefoxDefaultAssociations {
    Write-Step 'Importing Firefox default associations for future users'
    $associationMap = Get-FirefoxAssociationMap
    if (-not $associationMap) {
        Write-Warn 'Could not discover Firefox Developer Edition ProgIDs. Leaving future browser defaults unchanged.'
        return
    }

    $defaultsRoot = Join-Path $ProgramDataRoot 'defaults'
    Ensure-Directory -Path $defaultsRoot
    $xmlPath = Join-Path $defaultsRoot 'FirefoxDeveloperEdition.xml'

    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="$($associationMap['.htm'])" ApplicationName="Firefox Developer Edition" />
  <Association Identifier=".html" ProgId="$($associationMap['.html'])" ApplicationName="Firefox Developer Edition" />
  <Association Identifier="http" ProgId="$($associationMap['http'])" ApplicationName="Firefox Developer Edition" />
  <Association Identifier="https" ProgId="$($associationMap['https'])" ApplicationName="Firefox Developer Edition" />
</DefaultAssociations>
"@

    Set-Content -LiteralPath $xmlPath -Value $xml -Encoding UTF8
    & dism.exe /Online "/Import-DefaultAppAssociations:$xmlPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'DISM did not accept the default-browser association import.'
    }
}

function Install-NvidiaSupport {
    param([Parameter(Mandatory)][string]$WingetPath)

    $gpu = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) {
        Write-Info 'No NVIDIA GPU detected.'
        return
    }

    Write-Step 'Installing NVIDIA management software'
    $candidates = @(
        @{ Id = 'NVIDIACorporation.NVIDIAapp'; Source = 'winget' },
        @{ Id = 'Nvidia.GeForceExperience'; Source = 'winget' }
    )

    foreach ($candidate in $candidates) {
        try {
            Invoke-WingetInstall -WingetPath $WingetPath -Id $candidate.Id -Source $candidate.Source
            Write-Info ('Installed {0}. Use it to complete or verify the driver update if Windows does not apply the latest NVIDIA package itself.' -f $candidate.Id)
            return
        } catch {
            Write-Warn ("Failed to install {0}: {1}" -f $candidate.Id, $_.Exception.Message)
        }
    }
}

function Install-EditorsAndStarship {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Step 'Installing nano, Kate, and Starship'
    Invoke-WingetInstall -WingetPath $WingetPath -Id 'KDE.Kate'
    try {
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'okibcn.nano'
    } catch {
        Write-Warn 'Falling back from okibcn.nano to GNU.Nano.'
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'GNU.Nano'
    }
    Invoke-WingetInstall -WingetPath $WingetPath -Id 'Starship.Starship'
}

function Install-OpenSsh {
    Write-Step 'Installing and enabling OpenSSH client/server'

    Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' | Out-Null
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null

    Set-Service -Name ssh-agent -StartupType Automatic
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name ssh-agent
    Start-Service -Name sshd

    if (-not (Get-NetFirewallRule -DisplayName 'OpenSSH Server (SSH)' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (SSH)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }
}

function Copy-KmosAssets {
    Write-Step 'Staging kmos assets under ProgramData'

    $resolvedSource = (Resolve-Path -LiteralPath $AssetSourceRoot).Path
    Ensure-Directory -Path $AssetTargetRoot
    Copy-Item -Path (Join-Path $resolvedSource '*') -Destination $AssetTargetRoot -Recurse -Force

    Ensure-Directory -Path $ScriptTargetRoot
    Copy-Item -LiteralPath $ApplyUserScriptSource -Destination $ApplyUserScriptTarget -Force
}

function Install-FontFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$RegistryName
    )

    $fontsPath = Join-Path $env:WINDIR 'Fonts'
    $fontFileName = Split-Path -Leaf $SourcePath
    $destination = Join-Path $fontsPath $fontFileName
    Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $RegistryName -Value $fontFileName -PropertyType String -Force | Out-Null
}

function Install-ExtraFonts {
    Write-Step 'Installing kmos custom fonts'
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $workRoot = Join-Path $ProgramDataRoot 'font-staging'
    Ensure-Directory -Path $workRoot
    $abeezeeDir = Join-Path $workRoot 'ABeeZee'
    $moreSugarDir = Join-Path $workRoot 'MoreSugar'
    Ensure-Directory -Path $abeezeeDir
    Ensure-Directory -Path $moreSugarDir

    Expand-Archive -LiteralPath (Join-Path $AssetTargetRoot 'extra-fonts\ABeeZee.zip') -DestinationPath $abeezeeDir -Force
    Expand-Archive -LiteralPath (Join-Path $AssetTargetRoot 'extra-fonts\more_sugar.zip') -DestinationPath $moreSugarDir -Force

    Install-FontFile -SourcePath (Join-Path $abeezeeDir 'ABeeZee-Regular.ttf') -RegistryName 'ABeeZee (TrueType)'
    Install-FontFile -SourcePath (Join-Path $abeezeeDir 'ABeeZee-Italic.ttf') -RegistryName 'ABeeZee Italic (TrueType)'
    Install-FontFile -SourcePath (Join-Path $moreSugarDir 'MoreSugar-Thin.ttf') -RegistryName 'More Sugar Thin (TrueType)'
    & "$env:SystemRoot\System32\rundll32.exe" user32.dll,UpdatePerUserSystemParameters | Out-Null
}

function Configure-LockScreenAndPolicies {
    Write-Step 'Applying lock screen and Windows personalization policies'

    if (Test-Path -LiteralPath $LockScreenWallpaper) {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value $LockScreenWallpaper
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreenSlideshow' -Value 1 -Type DWord
    }

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Type DWord
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type DWord
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSpotlightCollectionOnDesktop' -Value 1 -Type DWord
}

function Register-ActiveSetup {
    Write-Step 'Registering per-user kmos defaults'

    $keyPath = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\kmos.windows'
    $stub = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\kmos\scripts\Apply-KmosWindowsUser.ps1" -AssetRoot "C:\ProgramData\kmos\assets"'
    Set-RegistryValue -Path $keyPath -Name 'Version' -Value '1,0,0,0'
    Set-RegistryValue -Path $keyPath -Name 'IsInstalled' -Value 1 -Type DWord
    Set-RegistryValue -Path $keyPath -Name 'StubPath' -Value $stub
}

function Apply-CurrentUserDefaults {
    Write-Step 'Applying current-user defaults'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyUserScriptTarget -AssetRoot $AssetTargetRoot
}

function Prompt-NewAdministrator {
    if (-not (Prompt-YesNo -Prompt 'Create a new local administrator user?' -Default $false)) {
        return
    }

    $username = ''
    while ([string]::IsNullOrWhiteSpace($username)) {
        $username = Read-Host 'New username'
    }

    $password = Read-Host 'New password' -AsSecureString
    $existing = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "User $username already exists. Skipping creation."
        return
    }

    New-LocalUser -Name $username -Password $password -PasswordNeverExpires -AccountNeverExpires | Out-Null
    Add-LocalGroupMember -Group 'Administrators' -Member $username
    Write-Info "Created administrator account $username. Active Setup will apply kmos user settings on first logon."
}

function Invoke-ChrisTitusUtility {
    if ($SkipTitus) {
        return
    }

    Write-Step 'Launching Chris Titus Windows utility'
    Invoke-Expression ((Invoke-RestMethod 'https://christitus.com/win').ToString())
}

function main {
    Assert-Administrator
    $winget = Resolve-Winget

    Install-PowerShellPreview
    Resize-SystemPartitionIfRequested
    Copy-KmosAssets
    Install-LenovoVantage -WingetPath $winget
    Install-FirefoxDeveloperEdition -WingetPath $winget
    Import-FirefoxDefaultAssociations
    Install-NvidiaSupport -WingetPath $winget
    Install-EditorsAndStarship -WingetPath $winget
    Install-OpenSsh
    Install-ExtraFonts
    Configure-LockScreenAndPolicies
    Register-ActiveSetup
    Apply-CurrentUserDefaults
    Prompt-NewAdministrator
    Invoke-ChrisTitusUtility

    Write-Host 'kmos Windows provisioning completed.' -ForegroundColor Green
}

main
