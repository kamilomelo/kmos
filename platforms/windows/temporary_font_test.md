# Temporary Kappa fonts and Terminal test

The VM check confirmed **Kappa Mono** was installed for all users, but did not
verify the other families. Run the first inline block in **elevated Windows
PowerShell 5.1 over SSH** to install **all six Kappa families** at once, including
Kappa Page (alpha). It fetches the current TTF files from the Kappa repository,
verifies their font names, and refuses to overwrite a different existing file.
It creates no script file in this repository. Report any error before running
the second block.

```powershell
& {
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }
Add-Type -AssemblyName System.Drawing
if (-not ([System.Management.Automation.PSTypeName]'KmosAllFontApi').Type) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KmosAllFontApi {
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
    public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);
}
'@
}
$api = 'https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts'
$families = @('kappa-text','kappa-page','kappa-mark','kappa-form','kappa-mono','kappa-spin')
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$dir = Join-Path $env:WINDIR 'Fonts'
$work = Join-Path $env:TEMP 'kmos-fonts'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count = 0
foreach ($family in $families) {
    $items = Invoke-RestMethod -Uri "$api/$family/ttf?ref=main" -ErrorAction Stop
    $files = @($items | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ttf$' -and $_.download_url })
    if (-not $files.Count) { throw "No TTF files for $family" }
    foreach ($item in $files) {
        if ($item.name -isnot [string]) { throw "Unexpected GitHub API response for $family (filename is not a string)" }
        if ($item.name -notmatch '^[A-Za-z0-9._-]+\.ttf$') { throw "Unexpected font filename: $($item.name)" }
        $source = Join-Path $work $item.name
        $target = Join-Path $dir $item.name
        Invoke-WebRequest -UseBasicParsing -Uri $item.download_url -OutFile $source -ErrorAction Stop
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 1024 -or -not (($bytes[0] -eq 0 -and $bytes[1] -eq 1 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -eq 'OTTO')) { throw "Not a valid TTF/OTF: $($item.name)" }
        $private = New-Object System.Drawing.Text.PrivateFontCollection
        try {
            $private.AddFontFile($source)
            $names = @($private.Families | ForEach-Object Name)
            if ($names.Count -ne 1 -or $names[0] -notmatch '^Kappa ') { throw "Unexpected font family: $($item.name) : $names" }
        } finally { $private.Dispose() }
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) { throw "Installed file differs; not overwriting $target" }
        } else { Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop }
        $registered = @((Get-ItemProperty -LiteralPath $key).PSObject.Properties | Where-Object { $_.Value -eq $item.name })
        if (-not $registered.Count) {
            $name = "$($names[0]) $([IO.Path]::GetFileNameWithoutExtension($item.name)) (TrueType)"
            $current = (Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue).$name
            if ($current -and $current -ne $item.name) { throw "Conflicting font registry entry: $name" }
            New-ItemProperty -Path $key -Name $name -Value $item.name -PropertyType String -ErrorAction Stop | Out-Null
        }
        if ([KmosAllFontApi]::AddFontResourceEx($target,0,[IntPtr]::Zero) -lt 1) { throw "Windows could not load $target" }
        $count++
    }
    Write-Host "$family : $($files.Count) fonts registered"
}
$result = [IntPtr]::Zero
[void][KmosAllFontApi]::SendMessageTimeout([IntPtr]0xffff,0x1d,[IntPtr]::Zero,[IntPtr]::Zero,2,5000,[ref]$result)
Write-Host "All six Kappa families: $count font files installed/verified for every user."
}
```

The failed earlier test also did **not** register the automatic Terminal sign-in
step. The next block tests the Terminal settings merge for **the SSH account
only**. It does not yet configure other accounts. Close Windows Terminal for
this account before running it. If it fails, paste the error here.

The second block makes a one-time backup beside the original `settings.json` before editing.
It preserves other JSON settings, but JSON comments and formatting are not
preserved. The font remains editable afterward. This is a VM test, not a
fleet-validated procedure.

```powershell
& {
$ErrorActionPreference = 'Stop'
$path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Terminal settings not found: $path" }
$original = [IO.File]::ReadAllText($path)
$out = New-Object System.Text.StringBuilder
$quoted = $false; $escaped = $false; $line = $false; $block = $false
for ($i = 0; $i -lt $original.Length; $i++) {
    $c = $original[$i]
    $next = if ($i + 1 -lt $original.Length) { $original[$i + 1] } else { [char]0 }
    if ($line) {
        if ($c -eq "`r" -or $c -eq "`n") { $line = $false; [void]$out.Append($c) }
        continue
    }
    if ($block) {
        if ($c -eq '*' -and $next -eq '/') { $block = $false; $i++ }
        continue
    }
    if ($quoted) {
        [void]$out.Append($c)
        if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
        continue
    }
    if ($c -eq '"') { $quoted = $true; [void]$out.Append($c); continue }
    if ($c -eq '/' -and $next -eq '/') { $line = $true; $i++; continue }
    if ($c -eq '/' -and $next -eq '*') { $block = $true; $i++; continue }
    [void]$out.Append($c)
}
if ($quoted -or $block) { throw 'Unterminated JSON string or comment; settings unchanged.' }
$text = $out.ToString()
$out = New-Object System.Text.StringBuilder
$quoted = $false; $escaped = $false
for ($i = 0; $i -lt $text.Length; $i++) {
    $c = $text[$i]
    if ($quoted) {
        [void]$out.Append($c)
        if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $quoted = $false }
        continue
    }
    if ($c -eq '"') { $quoted = $true; [void]$out.Append($c); continue }
    if ($c -eq ',') {
        $j = $i + 1
        while ($j -lt $text.Length -and [char]::IsWhiteSpace($text[$j])) { $j++ }
        if ($j -lt $text.Length -and $text[$j] -in @('}', ']')) { continue }
    }
    [void]$out.Append($c)
}
try { $settings = ConvertFrom-Json -InputObject $out.ToString() -ErrorAction Stop }
catch { throw "Could not parse Terminal settings; original unchanged: $_" }
if ($settings -isnot [pscustomobject]) { throw 'Unexpected Terminal settings format; original unchanged.' }
if (-not $settings.PSObject.Properties['profiles']) { $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles -isnot [pscustomobject]) { throw 'Unexpected profiles format; original unchanged.' }
if (-not $settings.profiles.PSObject.Properties['defaults']) { $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles.defaults -isnot [pscustomobject]) { throw 'Unexpected defaults format; original unchanged.' }
if (-not $settings.profiles.defaults.PSObject.Properties['font']) { $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }
if ($settings.profiles.defaults.font -isnot [pscustomobject]) { throw 'Unexpected font format; original unchanged.' }
$font = $settings.profiles.defaults.font
if ($font.PSObject.Properties['face']) { $font.face = 'Kappa Mono' } else { $font | Add-Member -NotePropertyName face -NotePropertyValue 'Kappa Mono' }
if ($font.PSObject.Properties['size']) { $font.size = 12 } else { $font | Add-Member -NotePropertyName size -NotePropertyValue 12 }
foreach ($old in @('fontFace','fontSize')) {
    if ($settings.profiles.defaults.PSObject.Properties[$old]) { $settings.profiles.defaults.PSObject.Properties.Remove($old) }
}
$updated = ConvertTo-Json -InputObject $settings -Depth 100 -ErrorAction Stop
$check = ConvertFrom-Json -InputObject $updated -ErrorAction Stop
if ($check.profiles.defaults.font.face -ne 'Kappa Mono' -or $check.profiles.defaults.font.size -ne 12) { throw 'Merged font could not be verified; original unchanged.' }
$backup = "$path.kmos-backup"
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop }
$temp = "$path.kmos-$PID.tmp"
$replaceBackup = "$path.kmos-replace-$PID.bak"
if (Test-Path -LiteralPath $replaceBackup) { throw "Temporary replacement backup already exists; not overwriting: $replaceBackup" }
try {
    [IO.File]::WriteAllText($temp, $updated, ([Text.UTF8Encoding]::new($false)))
    [IO.File]::Replace($temp, $path, $replaceBackup)
    Remove-Item -LiteralPath $replaceBackup -ErrorAction SilentlyContinue
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
Write-Host "Applied Kappa Mono, size 12 to $path; original backed up at $backup"
}
```

Then reopen Windows Terminal for **this account** and check Settings → Profiles
→ Defaults → Appearance. The existing new-user account will not change from
this test; it needs the separate sign-in automation below.

## One-time default for every other account (VM test)

Run this **third block** from the elevated `itadmin` SSH session **after** the
current-account test succeeded. It reuses the tested second Markdown snippet
from a pinned Git commit, with a SHA-256 check; it does not download a `.ps1`
file from the repository. It creates a protected script **on the Windows VM at
runtime** so a Windows sign-in can apply that preference in the user's own
context. The machine-wide sign-in entry keeps retrying until each account has
succeeded, then the user's marker prevents any later reset of their choice.
Other Terminal settings are backed up and preserved, though comments may be
removed. Before testing, close Terminal in the new account and sign out.

```powershell
& {
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }
$url = 'https://raw.githubusercontent.com/kamilomelo/kmos/77ee34d/platforms/windows/temporary_font_test.md'
$expected = '5F1E6D145F62EB9B9F31005434A3F0892A16F7C16CF1223B9CC4403203713146'
$download = Join-Path $env:TEMP 'kmos-tested-terminal-snippet.md'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download -ErrorAction Stop
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected) { throw 'Tested Markdown snippet checksum mismatch; no sign-in entry registered.' }
$text = [IO.File]::ReadAllText($download)
$blocks = [regex]::Matches($text, '(?ms)^```powershell\r?\n(.*?)^```[ \t]*$')
if ($blocks.Count -ne 2) { throw "Expected exactly two snippets in pinned Markdown; got $($blocks.Count)" }
$code = $blocks[1].Groups[1].Value.TrimEnd("`r", "`n")
if (-not $code.StartsWith("& {`n") -or -not $code.EndsWith('}')) { throw 'Unexpected Terminal snippet; no sign-in entry registered.' }

$dir = Join-Path $env:ProgramData 'kmos\terminal-font'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
& icacls.exe $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-11:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect Terminal font runtime directory; no sign-in entry registered.' }
$apply = Join-Path $dir 'Apply-KmosTerminalFont.ps1'
if ((Test-Path -LiteralPath $apply) -and (Get-Content -LiteralPath $apply -Raw).TrimEnd("`r", "`n") -ne $code) { throw "Different runtime script already exists: $apply" }
if (-not (Test-Path -LiteralPath $apply)) { Set-Content -LiteralPath $apply -Value $code -Encoding UTF8 -ErrorAction Stop }

$runner = Join-Path $dir 'Start-KmosTerminalFont.ps1'
$runnerCode = @'
$ErrorActionPreference = 'Stop'
$marker = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font-applied'
if (Test-Path -LiteralPath $marker -PathType Leaf) { return }
$log = Join-Path $env:LOCALAPPDATA 'kmos-terminal-font.log'
try {
    Start-Sleep -Seconds 30
    if (-not (Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue)) { throw 'Windows Terminal package not yet registered for this account; will retry at next sign-in.' }
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
        [IO.File]::WriteAllText($settings, '{}', ([Text.UTF8Encoding]::new($false)))
    }
    & 'C:\ProgramData\kmos\terminal-font\Apply-KmosTerminalFont.ps1' *>> $log
    if (-not $?) { throw 'Terminal font merge failed.' }
    [IO.File]::WriteAllText($marker, (Get-Date -Format o))
    Add-Content -LiteralPath $log -Value 'KMOS Terminal font applied once.'
} catch {
    Add-Content -LiteralPath $log -Value "KMOS Terminal font failed at $(Get-Date -Format o): $_"
    exit 1
}
'@
if ((Test-Path -LiteralPath $runner) -and (Get-Content -LiteralPath $runner -Raw).TrimEnd("`r", "`n") -ne $runnerCode.TrimEnd("`r", "`n")) { throw "Different runtime runner already exists: $runner" }
if (-not (Test-Path -LiteralPath $runner)) { Set-Content -LiteralPath $runner -Value $runnerCode -Encoding UTF8 -ErrorAction Stop }

$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$command = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\ProgramData\kmos\terminal-font\Start-KmosTerminalFont.ps1"'
$existing = (Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -ErrorAction SilentlyContinue).'kmos.terminalFont'
if ($existing -and $existing -ne $command) { throw 'A different kmos.terminalFont sign-in entry exists; not overwriting.' }
if (-not $existing) { New-ItemProperty -Path $runKey -Name 'kmos.terminalFont' -Value $command -PropertyType String -ErrorAction Stop | Out-Null }
if ((Get-ItemProperty -Path $runKey -Name 'kmos.terminalFont').'kmos.terminalFont' -ne $command) { throw 'Sign-in entry could not be verified.' }
Write-Host 'Automatic one-time Terminal font setup registered for existing and future users.'
}
```

Sign out the **new user** and sign back in. Wait at least 30 seconds, then
reopen Terminal and check its defaults and visible font. From **that new user**
in PowerShell, the log `%LOCALAPPDATA%\kmos-terminal-font.log` should end with
`KMOS Terminal font applied once.` and
`%LOCALAPPDATA%\kmos-terminal-font-applied` should exist. If the log reports
a failure, share its text; **do not repeatedly edit the new user's settings**.
After verification the temporary page can be folded into the two setup guides.
