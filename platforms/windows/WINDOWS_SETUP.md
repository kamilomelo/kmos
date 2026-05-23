# kmos Windows Setup

This guide is the manual Windows path for `kmos`. Use it from an elevated PowerShell session and run one phase at a time. The commands here are meant to be pasted directly, verified, and only repeated if a step did not complete.

## Phase 1: Core Tools

Run these first on a fresh Windows 11 machine with internet access.

### 1. Install Git

```powershell
winget install --id Git.Git --exact --source winget
```

### 2. Install PowerShell Preview

```powershell
winget install --id Microsoft.PowerShell.Preview --exact --source winget --scope machine
```

### 3. Install Lenovo Commercial Vantage

```powershell
winget install --id 9NR5B8GVVM13 --exact --source msstore --accept-package-agreements --accept-source-agreements
```

If that Store-backed install is unavailable on a given machine, skip it for now and revisit the Lenovo package path later.

### 4. Install Firefox Developer Edition

```powershell
winget install --id Mozilla.Firefox.DeveloperEdition --exact --source winget --scope machine
```

### 5. Install and Enable OpenSSH

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (SSH)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
```

### 6. Verify SSH

```powershell
Get-Service sshd
ssh localhost
```

If `ssh localhost` works, the SSH server is up on the local machine. External access still depends on network, hostname, and firewall conditions outside this guide.
