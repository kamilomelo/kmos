# Temporary VM test: automatic Kappa fonts and Terminal default

**Test only.** This page is temporary; it is not a replacement for
[windows_setup.md](windows_setup.md). Use the Windows VM with a rollback
checkpoint available. Open this page **in the VM browser** so you can copy the
block below into **Windows PowerShell (Admin)** without pasting across the
Linux-to-VM clipboard. It uses the Windows-supplied `powershell.exe`, not
PowerShell Preview.

```powershell
& {
$ErrorActionPreference = 'Stop'
$base = 'https://raw.githubusercontent.com/kamilomelo/kmos/17bc9f7/platforms/windows/assets'
$files = @(
    @('install_kmos_fonts.ps1', '651F9F0F9F7A5370DF192810969164033ED91CC8FFCFD2CF9A2A34D0CD550F2F'),
    @('register_kmos_terminal_font.ps1', '016BD6496EDD2307FF60A043F862C48984AC4D21BB5D23A4D35CEB4527CC79B9')
)
foreach ($file in $files) {
    $path = Join-Path $env:TEMP $file[0]
    Invoke-WebRequest -UseBasicParsing -Uri "$base/$($file[0])" -OutFile $path -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file[1]) {
        throw "Checksum mismatch: $($file[0])"
    }
    & $path
}
}
```

The first script installs the five frozen Kappa families for all users;
**Kappa Page alpha is excluded**. The second registers a one-time per-user
Windows Terminal default of **Kappa Mono, size 12**, for existing and future
accounts. It does not repeatedly reset a user's later font choice. Existing
Terminal settings are backed up before the first edit; comments in those
settings may be removed by the JSON merge. Both scripts are **awaiting a
Windows test**, so report any error instead of continuing blindly.

After the block succeeds, **sign out and back in**. Open Windows Terminal →
Settings → Profiles → Defaults → Appearance and confirm Kappa Mono, size 12.
Check both an existing account and a new test account. Do not create the new
account before completing the first six steps of the primary guide. A profile
with its own font override may still display a different font.

## SSH from Linux (no clipboard into the VM required)

The QEMU launcher forwards Linux `127.0.0.1:2222` to the VM's SSH port 22.
After restoring a VM checkpoint, its SSH host key may differ from the entry
already saved on Linux. **Do not delete the old entry or suppress host-key
checking.** In the Windows VM, run `ssh-keygen -lf
C:\ProgramData\ssh\ssh_host_ed25519_key.pub`; compare its `SHA256:` fingerprint
with the new host-key prompt before accepting it. From Linux, connect with:

```bash
ssh -p 2222 -o UserKnownHostsFile=/tmp/opencode/kmos-win11-known_hosts -o StrictHostKeyChecking=ask WINDOWS_USERNAME@127.0.0.1
```

Replace `WINDOWS_USERNAME` with the Windows login. The separate known-hosts
file leaves the original entry untouched. If the fingerprints do not match,
stop. SSH must already be installed and an authenticated login must work;
this page does not install OpenSSH.
