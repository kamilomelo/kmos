& {
$ErrorActionPreference = 'Stop'
$aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
$work = Join-Path $env:TEMP ('kmos-winget-' + [guid]::NewGuid().ToString('N'))

function Find-WinGet {
    param($Package)
    $paths = @((Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1), $aliasPath)
    if ($Package -and $Package.InstallLocation) { $paths += (Join-Path $Package.InstallLocation 'winget.exe') }
    foreach ($path in ($paths | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $version = & $path --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $version -match '^v?\d+\.') { return $path }
        } catch { continue }
    }
    return $null
}

function Get-DeploymentReason {
    param($Failure)
    $reason = $Failure.Exception.Message
    try {
        if ($reason -match '\[ActivityId\]\s+([0-9a-fA-F-]{36})') {
            $events = @(Get-AppxLog -ActivityId $Matches[1] -ErrorAction Stop)
        } else {
            $events = @(Get-AppxLog -ErrorAction Stop)
        }
        $reason += "`n" + (($events | Select-Object -ExpandProperty Message) -join "`n")
    } catch { }
    return $reason
}

function Install-MicrosoftFrameworks {
    param($Folder, $Reason)
    $archCode = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)
    if ($archCode -eq 9) { $arch = 'x64' }
    elseif ($archCode -eq 12) { $arch = 'arm64' }
    else { throw "Unsupported Windows architecture: $archCode" }

    if ($Reason -match '(?i)Microsoft\.VCLibs') {
        $vc = Join-Path $Folder 'Microsoft.VCLibs.Desktop.appx'
        Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx" -OutFile $vc -ErrorAction Stop
        Add-AppxPackage -Path $vc -ErrorAction Stop
    }

    if ($Reason -match '(?i)Microsoft\.UI\.Xaml\.2\.8') {
        $versions = (Invoke-RestMethod -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.ui.xaml/index.json' -ErrorAction Stop).versions
        $version = $versions | Where-Object { $_ -match '^2\.8\.\d+$' } | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
        if (-not $version) { throw 'No stable Microsoft.UI.Xaml 2.8 package was found.' }
        $zip = Join-Path $Folder 'Microsoft.UI.Xaml.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.ui.xaml/$version/microsoft.ui.xaml.$version.nupkg" -OutFile $zip -ErrorAction Stop
        $expanded = Join-Path $Folder 'xaml'
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded -ErrorAction Stop
        $xaml = Join-Path $expanded "tools\AppX\$arch\Release\Microsoft.UI.Xaml.2.8.appx"
        if (-not (Test-Path -LiteralPath $xaml -PathType Leaf)) { throw 'Microsoft.UI.Xaml package has no matching Windows architecture.' }
        Add-AppxPackage -Path $xaml -ErrorAction Stop
    }
}

$package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
$working = Find-WinGet $package
if (-not $working -and $package) {
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
    } catch { Write-Host 'Registration failed; trying the stable App Installer package.' }
    $package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
    $working = Find-WinGet $package
}
if (-not $working) {
    New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
    try {
        $bundle = Join-Path $work 'AppInstaller.msixbundle'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/getwinget' -OutFile $bundle -ErrorAction Stop
        try {
            Add-AppxPackage -Path $bundle -ErrorAction Stop
        } catch {
            $reason = Get-DeploymentReason $_
            if ($reason -notmatch '(?i)Microsoft\.(VCLibs|UI\.Xaml\.2\.8)' -or
                $reason -notmatch '(?i)framework.{0,120}(could not be found|not found|minimum version)|depends on a framework') {
                Write-Host $reason
                throw 'App Installer failed for a reason other than the two known Microsoft frameworks.'
            }
            Write-Host 'App Installer requires Microsoft VCLibs Desktop and/or UI.Xaml 2.8.'
            $answer = Read-Host 'Install those Microsoft framework packages and retry? [y/N]'
            if ($answer -ne 'y') { throw 'Framework installation declined; WinGet not installed.' }
            Install-MicrosoftFrameworks $work $reason
            Add-AppxPackage -Path $bundle -ErrorAction Stop
        }
        $package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
        $working = Find-WinGet $package
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if (-not $working) { throw 'WinGet did not start after installing App Installer.' }
Set-Alias -Name winget -Value $working -Scope Global
winget --version
if ($LASTEXITCODE -ne 0) { throw 'WinGet did not start through its command name.' }
Write-Host 'WINGET READY: continue Phase 3 in this PowerShell window.'
}
