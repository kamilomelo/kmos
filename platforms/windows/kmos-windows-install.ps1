[CmdletBinding()]
param(
    [string]$AssetSourceRoot = '',
    [switch]$SkipTitus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($AssetSourceRoot)) {
    $AssetSourceRoot = Join-Path $ScriptRoot 'assets'
}

$ProgramDataRoot = Join-Path $env:ProgramData 'kmos'
$AssetTargetRoot = Join-Path $ProgramDataRoot 'assets'
$ScriptTargetRoot = Join-Path $ProgramDataRoot 'scripts'
$ApplyUserScriptSource = Join-Path $ScriptRoot 'Apply-KmosWindowsUser.ps1'
$ApplyUserScriptTarget = Join-Path $ScriptTargetRoot 'Apply-KmosWindowsUser.ps1'
$FirefoxDeveloperEditionExe = 'C:\Program Files\Firefox Developer Edition\firefox.exe'
$PowerShellPreviewExe = 'C:\Program Files\PowerShell\7-preview\pwsh.exe'
$NvidiaAppExe = 'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIA app.exe'
$GeForceExperienceExe = 'C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe'
$KateExe = 'C:\Program Files\Kate\bin\kate.exe'
$LockScreenWallpaper = Join-Path $AssetTargetRoot 'wallpapers\kmos-wallpaper.png'
$NvidiaAppPage = 'https://www.nvidia.com/en-us/software/nvidia-app/'
$HackNerdFontZipUrl = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip'

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

function Prompt-ConfirmedPassword {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $password = Read-Host $Prompt -AsSecureString
        if (Prompt-YesNo -Prompt 'Password entered. Is this correct?' -Default $true) {
            return $password
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

    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force | Out-Null
    } else {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Description,
        [int]$DelaySeconds = 5,
        [int]$PromptAfterAttempts = 3
    )

    $attempt = 0
    while ($true) {
        try {
            & $Action
            return
        } catch {
            $attempt += 1
            $message = $_.Exception.Message
            if ($message -like 'PERMANENT:*') {
                throw ($message -replace '^PERMANENT:\s*', '')
            }
            Write-Warn ("{0} failed: {1}" -f $Description, $message)
            if ($attempt -ge $PromptAfterAttempts) {
                if (Prompt-YesNo -Prompt ("Skip {0} after {1} failed attempts?" -f $Description, $attempt) -Default $false) {
                    throw "SKIPPED: $Description"
                }
            }
            Write-Info ("Retrying {0} in {1} seconds. Press Ctrl+C to abort." -f $Description, $DelaySeconds)
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutSeconds = 180
    )

    $attempt = 0
    while ($true) {
        $attempt += 1
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
        if ($process.WaitForExit($TimeoutSeconds * 1000)) {
            if ($process.ExitCode -eq 0) {
                return
            }
            Write-Warn ("{0} failed with exit code {1}." -f $Description, $process.ExitCode)
        } else {
            try {
                $process.Kill()
            } catch {
            }
            Write-Warn ("{0} timed out after {1} seconds." -f $Description, $TimeoutSeconds)
        }

        if ($attempt -ge 3) {
            if (Prompt-YesNo -Prompt ("Skip {0} after {1} failed attempts?" -f $Description, $attempt) -Default $false) {
                Write-Warn ("Skipping {0} by user request." -f $Description)
                return
            }
        }

        Write-Info ("Retrying {0} in 5 seconds. Press Ctrl+C to abort." -f $Description)
        Start-Sleep -Seconds 5
    }
}

function Test-WingetInstalled {
    param(
        [Parameter(Mandatory)][string]$WingetPath,
        [Parameter(Mandatory)][string]$Id
    )

    $output = & $WingetPath list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $text = ($output | Out-String)
    return ($text -notmatch 'No installed package found')
}

function Test-WindowsCapabilityInstalled {
    param([Parameter(Mandatory)][string]$Name)

    $capability = Get-WindowsCapability -Online -Name $Name -ErrorAction SilentlyContinue
    return ($capability -and $capability.State -eq 'Installed')
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

function Repair-WingetSources {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Warn 'Repairing winget sources.'
    & $WingetPath source reset --force --disable-interactivity --accept-source-agreements 2>$null | Out-Null
    & $WingetPath source update --accept-source-agreements 2>$null | Out-Null
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

    $sourcesRepaired = $false
    while ($true) {
        $output = & $WingetPath @arguments 2>&1
        $outputText = ($output | Out-String)
        if ($LASTEXITCODE -eq 0) {
            return
        }

        if (($outputText -match 'source reset' -or
             $outputText -match 'source.*reset' -or
             $outputText -match 'Data required by the source is missing' -or
             $outputText -match 'An unexpected error occurred while executing the command') -and -not $sourcesRepaired) {
            $sourcesRepaired = $true
            Repair-WingetSources -WingetPath $WingetPath
            continue
        }

        if ($outputText -match 'No package found matching input criteria' -or
            $outputText -match 'No package found among the working sources' -or
            $outputText -match 'No available package found') {
            throw "PERMANENT: winget install failed for ${Id}: $($outputText.Trim())"
        }

        try {
            Invoke-WithRetry -Description "winget install $Id" -Action {
                throw "winget install failed for ${Id}: $($outputText.Trim())"
            }
        } catch {
            if ($_.Exception.Message -like 'SKIPPED:*') {
                Write-Warn ("Skipping winget install for {0} by user request." -f $Id)
                return
            }
            throw
        }
    }
}

function Install-PowerShellPreview {
    Write-Step 'Installing latest PowerShell preview'

    if (Test-Path -LiteralPath $PowerShellPreviewExe) {
        Write-Info 'PowerShell preview already installed. Skipping.'
        return
    }

    $release = $null
    Invoke-WithRetry -Description 'fetching PowerShell preview release metadata' -Action {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases' -Headers @{ 'User-Agent' = 'kmos-windows-install' }
    }
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

    Invoke-WithRetry -Description 'downloading PowerShell preview' -Action {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath
    }
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

    $candidate = @{ Id = '9NR5B8GVVM13'; Source = 'msstore'; Name = 'Lenovo Commercial Vantage' }

    if (Test-WingetInstalled -WingetPath $WingetPath -Id $candidate.Id) {
        Write-Info ("{0} already installed. Skipping." -f $candidate.Name)
        return
    }

    Write-Step ("Installing {0}" -f $candidate.Name)
    try {
        $output = & $WingetPath install --id $candidate.Id --exact --source $candidate.Source --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        $outputText = ($output | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw ($outputText.Trim())
        }
    } catch {
        Write-Warn ("Failed to install {0}: {1}" -f $candidate.Name, $_.Exception.Message)
        Write-Warn 'Skipping Lenovo Commercial Vantage and continuing with the rest of the installer.'
    }
}

function Install-FirefoxDeveloperEdition {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Step 'Installing Firefox Developer Edition'
    if (-not (Test-Path -LiteralPath $FirefoxDeveloperEditionExe)) {
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'Mozilla.Firefox.DeveloperEdition' -ExtraArgs @('--scope','machine')
    } else {
        Write-Info 'Firefox Developer Edition already installed. Skipping install.'
    }

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

function Get-NvidiaAppInstallerUrl {
    $response = $null
    Invoke-WithRetry -Description 'fetching NVIDIA App download page' -Action {
        $response = Invoke-WebRequest -Uri $NvidiaAppPage
    }
    $matches = [regex]::Matches($response.Content, 'https://us\.download\.nvidia\.com/[^"''<>\s]+NVIDIA_app[^"''<>\s]+\.exe')
    if ($matches.Count -gt 0) {
        return $matches[0].Value
    }

    return $null
}

function Install-NvidiaSupport {
    param([Parameter(Mandatory)][string]$WingetPath)

    $gpu = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) {
        Write-Info 'No NVIDIA GPU detected.'
        return
    }

    if ((Test-Path -LiteralPath $NvidiaAppExe) -or (Test-Path -LiteralPath $GeForceExperienceExe)) {
        Write-Info 'NVIDIA management software already installed. Skipping.'
        return
    }

    Write-Step 'Installing NVIDIA management software'
    try {
        $installerUrl = Get-NvidiaAppInstallerUrl
        if ($installerUrl) {
            $downloadRoot = Join-Path $ProgramDataRoot 'downloads'
            Ensure-Directory -Path $downloadRoot
            $installerPath = Join-Path $downloadRoot 'NVIDIA_app.exe'
            Invoke-WithRetry -Description 'downloading NVIDIA App installer' -Action {
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            }

            $process = Start-Process -FilePath $installerPath -ArgumentList '/s' -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Info 'Installed NVIDIA App from the official NVIDIA download page.'
                return
            }
            Write-Warn ("NVIDIA App installer exited with code {0}." -f $process.ExitCode)
        }
    } catch {
        Write-Warn ("Failed to install NVIDIA App from NVIDIA.com: {0}" -f $_.Exception.Message)
    }

    try {
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'Nvidia.GeForceExperience' -Source 'winget'
        Write-Info 'Installed NVIDIA GeForce Experience as a fallback. Use it to complete or verify the driver update.'
        return
    } catch {
        Write-Warn ("Failed to install Nvidia.GeForceExperience: {0}" -f $_.Exception.Message)
    }
}

function Install-EditorsAndStarship {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Step 'Installing nano, Kate, and Starship'
    if (-not (Test-Path -LiteralPath $KateExe) -and -not (Test-WingetInstalled -WingetPath $WingetPath -Id 'KDE.Kate')) {
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'KDE.Kate' -ExtraArgs @('--scope','machine')
    } else {
        Write-Info 'Kate already installed. Skipping install.'
    }
    if (-not (Get-Command nano -ErrorAction SilentlyContinue) -and -not (Test-WingetInstalled -WingetPath $WingetPath -Id 'okibcn.nano') -and -not (Test-WingetInstalled -WingetPath $WingetPath -Id 'GNU.Nano')) {
        try {
            Invoke-WingetInstall -WingetPath $WingetPath -Id 'okibcn.nano'
        } catch {
            Write-Warn 'Falling back from okibcn.nano to GNU.Nano.'
            Invoke-WingetInstall -WingetPath $WingetPath -Id 'GNU.Nano'
        }
    } else {
        Write-Info 'nano already installed. Skipping install.'
    }
    if (-not (Get-Command starship -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath 'C:\Program Files\starship\bin\starship.exe') -and -not (Test-WingetInstalled -WingetPath $WingetPath -Id 'Starship.Starship')) {
        Invoke-WingetInstall -WingetPath $WingetPath -Id 'Starship.Starship' -ExtraArgs @('--scope','machine')
    } else {
        Write-Info 'Starship already installed. Skipping install.'
    }

    $starshipDir = 'C:\Program Files\starship\bin'
    if (Test-Path -LiteralPath $starshipDir) {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if ($machinePath -notlike "*$starshipDir*") {
            [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $starshipDir), 'Machine')
        }
    }
}

function Configure-ComputerName {
    $currentName = $env:COMPUTERNAME
    Write-Step 'Configuring the computer name'
    Write-Info "Current computer name: $currentName"

    $newName = Prompt-ConfirmedText -Prompt 'Enter the desired computer name'
    if ($newName -eq $currentName) {
        Write-Info 'Computer name already matches the requested name.'
        return
    }

    Rename-Computer -NewName $newName -Force
    Write-Warn "Computer renamed to $newName. A reboot will be required for the new name to take effect."
}

function Install-OpenSsh {
    Write-Step 'Installing and enabling OpenSSH client/server'

    if (-not (Test-WindowsCapabilityInstalled -Name 'OpenSSH.Client~~~~0.0.1.0')) {
        Invoke-ProcessWithTimeout -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-Command',
            "Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' | Out-Null"
        ) -Description 'installing OpenSSH client capability'
    } else {
        Write-Info 'OpenSSH client already installed. Skipping capability install.'
    }
    if (-not (Test-WindowsCapabilityInstalled -Name 'OpenSSH.Server~~~~0.0.1.0')) {
        Invoke-ProcessWithTimeout -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-Command',
            "Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null"
        ) -Description 'installing OpenSSH server capability'
    } else {
        Write-Info 'OpenSSH server already installed. Skipping capability install.'
    }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    $existingRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if (-not $existingRule) {
        $existingRule = Get-NetFirewallRule -DisplayName 'OpenSSH Server (SSH)' -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($existingRule) {
        Set-NetFirewallRule -InputObject $existingRule -Enabled True -Direction Inbound -Action Allow | Out-Null
    } else {
        try {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (SSH)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
        } catch {
            Write-Warn ("Could not create the OpenSSH firewall rule: {0}" -f $_.Exception.Message)
        }
    }
}

function Copy-KmosAssets {
    Write-Step 'Staging kmos assets under ProgramData'

    $resolvedSource = (Resolve-Path -LiteralPath $AssetSourceRoot).Path
    Ensure-Directory -Path $AssetTargetRoot
    Copy-Item -Path (Join-Path $resolvedSource '*') -Destination $AssetTargetRoot -Recurse -Force

    Ensure-Directory -Path $ScriptTargetRoot
    Copy-Item -LiteralPath $ApplyUserScriptSource -Destination $ApplyUserScriptTarget -Force
    Write-Info 'Starship presets are available under C:\ProgramData\kmos\assets\starship-presets\'
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
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $RegistryName -Value $fontFileName
}

function Install-HackNerdFont {
    param([Parameter(Mandatory)][string]$WorkRoot)

    $fontRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $regularInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'Hack Nerd Font Mono (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $boldInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'Hack Nerd Font Mono Bold (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $italicInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'Hack Nerd Font Mono Italic (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $boldItalicInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'Hack Nerd Font Mono Bold Italic (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    if ($regularInstalled -and $boldInstalled -and $italicInstalled -and $boldItalicInstalled) {
        Write-Info 'Hack Nerd Font Mono already installed. Skipping.'
        return
    }

    $hackZip = Join-Path $WorkRoot 'Hack.zip'
    $hackDir = Join-Path $WorkRoot 'HackNerdFont'
    Ensure-Directory -Path $hackDir

    Invoke-WithRetry -Description 'downloading Hack Nerd Font' -Action {
        Invoke-WebRequest -Uri $HackNerdFontZipUrl -OutFile $hackZip
    }
    Expand-Archive -LiteralPath $hackZip -DestinationPath $hackDir -Force

    Install-FontFile -SourcePath (Join-Path $hackDir 'HackNerdFontMono-Regular.ttf') -RegistryName 'Hack Nerd Font Mono (TrueType)'
    Install-FontFile -SourcePath (Join-Path $hackDir 'HackNerdFontMono-Bold.ttf') -RegistryName 'Hack Nerd Font Mono Bold (TrueType)'
    Install-FontFile -SourcePath (Join-Path $hackDir 'HackNerdFontMono-Italic.ttf') -RegistryName 'Hack Nerd Font Mono Italic (TrueType)'
    Install-FontFile -SourcePath (Join-Path $hackDir 'HackNerdFontMono-BoldItalic.ttf') -RegistryName 'Hack Nerd Font Mono Bold Italic (TrueType)'
}

function Install-ExtraFonts {
    Write-Step 'Installing kmos custom fonts'

    $fontRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $abeezeeInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'ABeeZee (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $abeezeeItalicInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'ABeeZee Italic (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $moreSugarInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'More Sugar Thin (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    $hackInstalled = (Get-ItemProperty -Path $fontRegistry -Name 'Hack Nerd Font Mono (TrueType)' -ErrorAction SilentlyContinue) -ne $null
    if ($abeezeeInstalled -and $abeezeeItalicInstalled -and $moreSugarInstalled -and $hackInstalled) {
        Write-Info 'kmos custom fonts already installed. Skipping.'
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $workRoot = Join-Path $ProgramDataRoot 'font-staging'
    Ensure-Directory -Path $workRoot
    $abeezeeDir = Join-Path $workRoot 'ABeeZee'
    $moreSugarDir = Join-Path $workRoot 'MoreSugar'
    Ensure-Directory -Path $abeezeeDir
    Ensure-Directory -Path $moreSugarDir

    Expand-Archive -LiteralPath (Join-Path $AssetTargetRoot 'extra-fonts\ABeeZee.zip') -DestinationPath $abeezeeDir -Force
    Expand-Archive -LiteralPath (Join-Path $AssetTargetRoot 'extra-fonts\more_sugar.zip') -DestinationPath $moreSugarDir -Force
    Install-HackNerdFont -WorkRoot $workRoot

    Install-FontFile -SourcePath (Join-Path $abeezeeDir 'ABeeZee-Regular.ttf') -RegistryName 'ABeeZee (TrueType)'
    Install-FontFile -SourcePath (Join-Path $abeezeeDir 'ABeeZee-Italic.ttf') -RegistryName 'ABeeZee Italic (TrueType)'
    Install-FontFile -SourcePath (Join-Path $moreSugarDir 'MoreSugar-Thin.ttf') -RegistryName 'More Sugar Thin (TrueType)'
    & "$env:SystemRoot\System32\rundll32.exe" user32.dll,UpdatePerUserSystemParameters | Out-Null
}

function Configure-LockScreenAndPolicies {
    Write-Step 'Applying lock screen and Windows personalization policies'

    if (Test-Path -LiteralPath $LockScreenWallpaper) {
        $lockScreenFileUrl = 'file:///' + (($LockScreenWallpaper -replace '\\', '/') -replace ' ', '%20')
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value $LockScreenWallpaper
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreenSlideshow' -Value 1 -Type DWord
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImagePath' -Value $LockScreenWallpaper
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageUrl' -Value $lockScreenFileUrl
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'LockScreenImageStatus' -Value 1 -Type DWord
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'DesktopImagePath' -Value $LockScreenWallpaper
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'DesktopImageUrl' -Value $lockScreenFileUrl
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP' -Name 'DesktopImageStatus' -Value 1 -Type DWord
    }

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Type DWord
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type DWord
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSpotlightCollectionOnDesktop' -Value 1 -Type DWord
}

function Register-ActiveSetup {
    Write-Step 'Registering per-user kmos defaults'

    $keyPath = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\kmos.windows'
    $stub = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\kmos\scripts\Apply-KmosWindowsUser.ps1" -AssetRoot "C:\ProgramData\kmos\assets"'
    Set-RegistryValue -Path $keyPath -Name 'Version' -Value '1,0,2,0'
    Set-RegistryValue -Path $keyPath -Name 'IsInstalled' -Value 1 -Type DWord
    Set-RegistryValue -Path $keyPath -Name 'StubPath' -Value $stub
}

function Apply-CurrentUserDefaults {
    Write-Step 'Applying current-user defaults'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyUserScriptTarget -AssetRoot $AssetTargetRoot
}

function Apply-DefaultUserDefaults {
    Write-Step 'Applying default-user defaults'

    $defaultProfileRoot = Join-Path $env:SystemDrive 'Users\Default'
    $defaultNtUser = Join-Path $defaultProfileRoot 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $defaultNtUser)) {
        Write-Warn 'Default user hive was not found. Skipping default-user customization.'
        return
    }

    $loaded = $false
    try {
        & reg.exe load HKU\kmosDefault $defaultNtUser | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'Could not load the default user hive. Skipping default-user customization.'
            return
        }
        $loaded = $true

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyUserScriptTarget `
            -AssetRoot $AssetTargetRoot `
            -RegistryRoot 'Registry::HKEY_USERS\kmosDefault' `
            -HomePath $defaultProfileRoot `
            -SkipBrowserDefault
    } finally {
        if ($loaded) {
            & reg.exe unload HKU\kmosDefault | Out-Null
        }
    }
}

function Prompt-NewAdministrator {
    if (-not (Prompt-YesNo -Prompt 'Create a new local administrator user?' -Default $false)) {
        return
    }

    while ($true) {
        $username = Prompt-ConfirmedText -Prompt 'New username'
        $password = Prompt-ConfirmedPassword -Prompt 'New password'
        $existing = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Warn "User $username already exists. Skipping creation."
        } else {
            New-LocalUser -Name $username -Password $password -PasswordNeverExpires -AccountNeverExpires | Out-Null
            Add-LocalGroupMember -Group 'Administrators' -Member $username
            Write-Info "Created administrator account $username. Active Setup will apply kmos user settings on first logon."
        }

        if (-not (Prompt-YesNo -Prompt 'Add another local administrator user?' -Default $false)) {
            break
        }
    }
}

function Invoke-ChrisTitusUtility {
    if ($SkipTitus) {
        return
    }

    Write-Step 'Launching Chris Titus Windows utility'
    Invoke-WithRetry -Description 'fetching Chris Titus Windows utility' -Action {
        Invoke-Expression ((Invoke-RestMethod 'https://christitus.com/win').ToString())
    }
}

function main {
    Assert-Administrator
    $winget = Resolve-Winget

    Install-PowerShellPreview
    Resize-SystemPartitionIfRequested
    Copy-KmosAssets
    Configure-ComputerName
    Install-OpenSsh
    Install-FirefoxDeveloperEdition -WingetPath $winget
    Import-FirefoxDefaultAssociations
    Install-EditorsAndStarship -WingetPath $winget
    Install-ExtraFonts
    Configure-LockScreenAndPolicies
    Register-ActiveSetup
    Apply-DefaultUserDefaults
    Apply-CurrentUserDefaults
    Prompt-NewAdministrator
    Install-LenovoVantage -WingetPath $winget
    Install-NvidiaSupport -WingetPath $winget
    Invoke-ChrisTitusUtility

    Write-Host 'kmos Windows provisioning completed.' -ForegroundColor Green
}

main
