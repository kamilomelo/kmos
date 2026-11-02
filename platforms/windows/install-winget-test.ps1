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

function Install-WindowsAppRuntime18 {
    param($Folder)
    $archCode = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)
    if ($archCode -eq 9) { $arch = 'x64' }
    elseif ($archCode -eq 12) { $arch = 'arm64' }
    else { throw "Unsupported Windows architecture: $archCode" }

    $installer = Join-Path $Folder 'WindowsAppRuntimeInstall.exe'
    $url = "https://aka.ms/windowsappsdk/1.8/1.8.260921001/windowsappruntimeinstall-$arch.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer -ErrorAction Stop
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch '(^|,)\s*CN=Microsoft Corporation(,|$)') {
        throw 'Windows App Runtime installer is not validly signed by Microsoft.'
    }
    $process = Start-Process -FilePath $installer -ArgumentList '--quiet' -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw "Windows App Runtime installer failed with exit code $($process.ExitCode)." }
    $runtime = Get-AppxPackage -Name Microsoft.WindowsAppRuntime.1.8 |
        Where-Object { $_.Version -ge [version]'8000.616.304.0' -and $_.Architecture -eq $arch }
    if (-not $runtime) { throw 'Windows App Runtime 1.8 did not register for this account at the required version.' }
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
        $handled = @{}
        $approved = $false
        $installed = $false
        foreach ($attempt in 1..4) {
            try {
                Add-AppxPackage -Path $bundle -ErrorAction Stop
                $installed = $true
                break
            } catch {
                $reason = Get-DeploymentReason $_
                if ($reason -notmatch '(?i)framework.{0,120}(could not be found|not found|minimum version)|depends on a framework') {
                    Write-Host $reason
                    throw 'App Installer deployment is blocked; see the Windows reason above.'
                }
                if ($reason -match '(?i)Microsoft\.WindowsAppRuntime\.1\.8') { $needed = 'Windows App Runtime 1.8' }
                elseif ($reason -match '(?i)Microsoft\.VCLibs') { $needed = 'Microsoft VCLibs Desktop' }
                elseif ($reason -match '(?i)Microsoft\.UI\.Xaml\.2\.8') { $needed = 'Microsoft UI.Xaml 2.8' }
                else {
                    Write-Host $reason
                    throw 'App Installer needs another dependency; see the Windows reason above.'
                }
                if ($handled.ContainsKey($needed)) {
                    Write-Host $reason
                    throw "Installing $needed did not resolve the App Installer dependency."
                }
                if (-not $approved) {
                    $answer = Read-Host "Install required Microsoft frameworks (starting with $needed) and retry? [y/N]"
                    if ($answer -ne 'y') { throw 'Framework installation declined; WinGet not installed.' }
                    $approved = $true
                }
                Write-Host "Installing $needed from Microsoft's official source."
                if ($needed -eq 'Windows App Runtime 1.8') { Install-WindowsAppRuntime18 $work }
                else { Install-MicrosoftFrameworks $work $reason }
                $handled[$needed] = $true
            }
        }
        if (-not $installed) { throw 'App Installer did not install after the available Microsoft prerequisites.' }
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
