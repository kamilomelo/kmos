# Run elevated after installing fonts. Uses HKLM Run for one-time per-user setup.
& {
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell (powershell.exe).' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }

$dir = Join-Path $env:ProgramData 'kmos\scripts'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$script = Join-Path $dir 'set_kmos_terminal_font.ps1'
$url = 'https://raw.githubusercontent.com/kamilomelo/kmos/20ecf61/platforms/windows/assets/set_kmos_terminal_font.ps1'
$hash = '186A2F5BF14DCCCB2DB53E0E60B9404404A9A19A67802C7838561EBC5A0F276E'
$download = Join-Path $env:TEMP 'set_kmos_terminal_font.ps1'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download -ErrorAction Stop
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $hash) { throw 'Terminal setup download failed checksum verification.' }
if ((Test-Path -LiteralPath $script) -and (Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash -ne $hash) {
    throw "Existing Terminal setup script differs: $script (not overwriting)."
}
Copy-Item -LiteralPath $download -Destination $script -Force -ErrorAction Stop

$runner = Join-Path $dir 'start_kmos_terminal_font.ps1'
$runnerContent = @'
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font.log'
try {
    & 'C:\ProgramData\kmos\scripts\set_kmos_terminal_font.ps1' *>> $log
} catch {
    Add-Content -LiteralPath $log -Value "KMOS Terminal font setup failed at $(Get-Date -Format o): $_"
}
'@
if ((Test-Path -LiteralPath $runner) -and
    (Get-Content -LiteralPath $runner -Raw).TrimEnd("`r", "`n") -ne $runnerContent.TrimEnd("`r", "`n")) {
    throw "Existing Terminal setup runner differs: $runner (not overwriting)."
}
Set-Content -LiteralPath $runner -Value $runnerContent -Encoding ASCII
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$runCommand = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\ProgramData\kmos\scripts\start_kmos_terminal_font.ps1"'
$existing = (Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -ErrorAction SilentlyContinue).'kmos.terminalFont'
if ($existing -and $existing -ne $runCommand) { throw 'A different kmos.terminalFont startup entry exists; not replacing it.' }
if (-not $existing) { New-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -Value $runCommand -PropertyType String -ErrorAction Stop | Out-Null }
if ((Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -ErrorAction Stop).'kmos.terminalFont' -ne $runCommand) { throw 'Could not verify startup entry.' }
Write-Host 'Windows Terminal font will be applied once at sign-in for existing and future accounts; each user can change it afterward.'
Write-Host "To apply to the current account now, run: & '$script'"
}
