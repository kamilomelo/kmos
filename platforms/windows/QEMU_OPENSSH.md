# QEMU-only OpenSSH test

**Use this page only in the KMOS QEMU Windows test VM. Do not use it on a real
computer or for production deployment.** The current Windows installation in
this VM cannot download its built-in OpenSSH feature (`0x80240438`). This
block instead uses the pinned Microsoft **Preview/non-production-ready** MSI
that previously worked in this VM. It requires manual security updates.

From a **local Windows PowerShell (Admin)** window, copy and run this **one
block**, not the OpenSSH block on `WINDOWS_SETUP.md`:

```powershell
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell (powershell.exe).' }
$computer = Get-CimInstance Win32_ComputerSystem
if ($computer.Manufacturer -notmatch 'QEMU' -and $computer.Model -notmatch 'QEMU|Q35') {
    throw 'Not the QEMU test VM; do not install this Preview MSI.'
}
$msiClient = Join-Path $env:ProgramFiles 'OpenSSH\ssh.exe'
if (-not (Test-Path $msiClient) -or -not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    $msi = Join-Path $env:TEMP 'OpenSSH-Win64-v10.4.0.0.msi'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/OpenSSH-Win64-v10.4.0.0.msi' -OutFile $msi
    if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne '788D8643464A01EB63640A2FD746F9ED23D106B5A901A35F88DC8CD40E446AC9') { throw 'OpenSSH download checksum mismatch; do not install.' }
    $install = Start-Process msiexec.exe -ArgumentList "/i `"$msi`"" -Wait -PassThru
    if ($install.ExitCode -notin @(0, 3010)) { throw "OpenSSH MSI failed: $($install.ExitCode)" }
    if ($install.ExitCode -eq 3010) { throw 'Restart Windows, then rerun this block.' }
}
Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
if ((Get-Service sshd -ErrorAction Stop).Status -ne 'Running') { Start-Service sshd -ErrorAction Stop }
if (-not (Get-NetFirewallRule -Name KMOS-SSH-QEMU-Host -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name KMOS-SSH-QEMU-Host -DisplayName 'KMOS SSH from QEMU host only' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Public -RemoteAddress 10.0.2.2 -ErrorAction Stop | Out-Null
}
$client = Get-Command ssh.exe -ErrorAction Stop
if (-not (Test-NetConnection -ComputerName localhost -Port 22 -InformationLevel Quiet)) { throw 'SSH server is not listening on port 22.' }
Write-Host "SSH READY locally: client $($client.Source); server listening on port 22."
}
```

From the Linux host, an authenticated test is
`ssh -p 2222 <Windows-user>@127.0.0.1`. The QEMU firewall rule permits only
the host gateway (`10.0.2.2`); do not broaden it for this test. Verify any
unexpected host-key change before accepting it. `SSH READY locally` alone
does not verify authentication.
