# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete.

## Phase 1: Core Tools

Run these first on a fresh Windows 11 machine with internet access.

### Install Core Tools

```powershell
winget install --id Git.Git --exact --source winget
winget install --id Microsoft.PowerShell.Preview --exact --source winget
winget install --id GNU.Nano --exact --source winget --scope machine
winget install --id KDE.Kate --exact --source winget --scope machine
winget install --id Mozilla.Firefox.DeveloperEdition --exact --source winget --scope machine
winget install --id 9NR5B8GVVM13 --exact --source msstore --accept-package-agreements --accept-source-agreements
```

If `winget` scope causes trouble for PowerShell Preview, use the MSI alternative:

```powershell
Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v7.7.1-preview.4/PowerShell-7.7.1-preview.4-win-x64.msi" -OutFile "$env:TEMP\ps77preview.msi"
msiexec /i "$env:TEMP\ps77preview.msi" /quiet ALLUSERS=1
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

### Verify SSH

```powershell
Get-Service sshd
ssh localhost
```

If `ssh localhost` works, the SSH server is up on the local machine. External access still depends on network, hostname, and firewall conditions outside this guide.
