@echo off
setlocal
if /i "%~1"=="--help" goto help
set "KMOS_SSH_INSTALLER=%~f0"

rem Elevate without asking the user to type a command or supply a password here.
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "try { $p = Start-Process -FilePath $env:KMOS_SSH_INSTALLER -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Host $_; exit 1 }"
    exit /b %errorlevel%
)

rem Run only the PowerShell section below; the installer is a single file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath $env:KMOS_SSH_INSTALLER; $m = [regex]::Match($s, '(?m)^# KMOS-SSH-POWERSHELL\r?\n'); if (-not $m.Success) { throw 'Installer payload not found.' }; & ([scriptblock]::Create($s.Substring($m.Index + $m.Length)))"
set "result=%errorlevel%"
echo.
if not "%result%"=="0" echo OpenSSH setup failed. Read the error above before retrying.
pause
exit /b %result%

:help
echo Usage: double-click Install-KmosOpenSSH.cmd
echo Checks Windows OpenSSH Client and Server, installs missing components,
echo starts the server, and checks the inbound firewall rule.
echo An administrator approval prompt appears only when needed.
exit /b 0

# KMOS-SSH-POWERSHELL
$ErrorActionPreference = 'Stop'

function Ensure-Capability {
    param([string]$Name)

    $capability = Get-WindowsCapability -Online -Name $Name -ErrorAction Stop
    if ($capability.State -eq 'Installed') {
        Write-Host "$Name is already installed; skipping."
        return
    }
    if ($capability.State -ne 'NotPresent') {
        throw "Unexpected state for $Name`: $($capability.State). No changes to this component were made."
    }

    Write-Host "Installing $Name ..."
    $result = Add-WindowsCapability -Online -Name $Name -ErrorAction Stop
    if ($result.RestartNeeded) {
        $script:restartNeeded = $true
        Write-Warning "$Name needs a Windows restart to finish installation."
        return
    }
    $installed = Get-WindowsCapability -Online -Name $Name -ErrorAction Stop
    if ($installed.State -ne 'Installed') { throw "Installation did not complete for $Name`: $($installed.State)" }
}

try {
    $restartNeeded = $false
    Ensure-Capability 'OpenSSH.Client~~~~0.0.1.0'
    if (-not $restartNeeded) { Ensure-Capability 'OpenSSH.Server~~~~0.0.1.0' }
    if ($restartNeeded) {
        Write-Warning 'Restart Windows and run this installer again to finish service and firewall checks.'
        exit 0
    }

    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
    $service = Get-Service -Name sshd -ErrorAction Stop
    if ($service.Status -ne 'Running') { Start-Service sshd -ErrorAction Stop }
    Write-Host 'OpenSSH Server is running and starts automatically.'

    $defaultRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    $kmosRule = Get-NetFirewallRule -Name 'KMOS-SSH-In-Private-LAN' -ErrorAction SilentlyContinue
    if ($defaultRule) {
        Write-Host 'Windows already has an OpenSSH firewall rule; no duplicate was created.'
        $defaultRule | Select-Object Name, Enabled, Profile, Action | Format-Table -AutoSize
        Write-Host 'Review its network scope before using SSH on a real network.'
        if (-not ($defaultRule | Where-Object Enabled -eq True)) {
            Write-Warning 'The existing firewall rule is disabled; remote SSH will not work until it is enabled.'
        }
    } elseif ($kmosRule) {
        Write-Host 'The KMOS private-LAN SSH rule already exists; no duplicate was created.'
        $kmosRule | Select-Object Name, Enabled, Profile, Action | Format-Table -AutoSize
        if (-not ($kmosRule | Where-Object Enabled -eq True)) {
            Write-Warning 'The existing firewall rule is disabled; remote SSH will not work until it is enabled.'
        }
    } else {
        New-NetFirewallRule -Name 'KMOS-SSH-In-Private-LAN' -DisplayName 'KMOS OpenSSH (private LAN)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Private -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null
        Write-Host 'Added an inbound SSH rule for the private local subnet only.'
    }

    $port = Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue
    if (-not $port.TcpTestSucceeded) { throw 'sshd is running, but localhost port 22 is not reachable.' }
    Write-Host 'OpenSSH Client and Server are installed; localhost port 22 is listening.'
    Write-Host 'QEMU user-mode networking needs separate host-side port forwarding for connections into the VM.'
} catch {
    Write-Error $_
    exit 1
}
