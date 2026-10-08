# Experimental headless → KDE (x86/next)

Use only on an **installed KMOS headless Arch x86_64** system, not an Arch ISO
and not an arbitrary existing Arch/VPS installation. This path is not part of
`main` or `v0.9.0`. A real headless → KDE upgrade and the KDE finishing pass
were reported working; NetworkManager migration remains untested.

From a checkout of `x86/next`, run the read-only check first:

```bash
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
```

The explicit `--install` operation offers the same full/noapps KDE package
sets as the ISO, with **no AUR installation**. It performs a normal Arch
`pacman -Syu` transaction; inspect any proposed replacements or removals
before approving pacman's prompts. Back up important data first. For the first
real test, keep local console or Ethernet access available in case a package
upgrade interrupts SSH/Wi-Fi. Run the script as `./script.sh`, **not** by
prefixing `sudo`; it requests privileges itself and asks you to type
`INSTALL KDE` before any writes.

KMOS does **not** disable `iwd`, `dhcpcd`, or `sshd` or start/enable
NetworkManager on this path. Plasma's NetworkManager tray may not manage Wi-Fi
while iwd remains in charge; use the existing iwd/Impala connection. A system
or package hook could still affect networking during a full system upgrade.
The script stages KMOS's panel, wallpaper and color defaults only for users
without those personal configurations, enables SDDM for the next boot, and
does not reboot automatically. It does **not** run the ISO KDE post-install
cleanup, optional AUR installation, font removals or existing-user KDE
configuration rewrites. Therefore visual details not included in these safe
defaults may differ from a fresh ISO KDE install until separately validated.

If an upgrade is interrupted, rerun with the **same profile** after checking
connectivity and pacman state. An in-progress marker allows retry; a completed
KMOS KDE profile makes subsequent runs a no-op. Existing non-KMOS KDE or a
different panel template is refused rather than replaced.

## Optional ISO-look finishing pass (after the upgrade)

The live upgrade deliberately skips the ISO's destructive post-install stage.
To add its KDE login/lock-screen look, Kappa/Konsole profile, Yakuake, Kate,
Dolphin and desktop defaults for **your own account**, first preview:

```bash
./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --plan
```

The plan lists existing files that differ from the KMOS defaults and their
sizes. If you want those changes, run `./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --apply`.
It asks for initial confirmation and then **each existing file** defaults to
**No**. Only approved replacements are saved under
`~/.local/share/kmos/backups/kde-<date>/` for user files or
`/var/backups/kmos/kde-<date>/` for system files. Missing files are added
without prompting; no panels, wallpaper choices, networking, packages or
other accounts' home files are changed. System-wide defaults can affect KDE
users without a personal override. It may download Kappa fonts with the existing
`curl` tool, but does not delete other fonts. Review the resulting KDE session
before removing any backup. Rerunning skips defaults that already match.

## Optional NetworkManager handoff (x86/next experiment)

The KDE upgrade deliberately retains the headless `iwd`/`dhcpcd` connection.
The goal is to let **NetworkManager control networking in KDE** instead of
managing connections directly with `iwctl` and `dhcpcd`. This is not just a
test of switching between SSIDs. Check active routes and a wired fallback
without changing services:

```bash
./platforms/archlinux/tools/kmos-network-migration.sh --plan
```

For a **staged SSH handoff with working Ethernet**, run this from the existing
SSH session. It checks real internet through Ethernet, asks for confirmation,
and enables NetworkManager and a one-time boot guard for the **next** boot.
It disables only the *next-boot* iwd/dhcpcd units; neither the current DHCP
lease nor your SSH session is stopped. Reboot deliberately when ready. The
boot guard verifies NM-controlled Ethernet internet and automatically restores
iwd/dhcpcd if that fails (allow roughly two minutes). If both paths fail,
use the physical console. Your Ethernet IP address might change after reboot.

```bash
./platforms/archlinux/tools/kmos-network-migration.sh --stage-reboot
```

Until reboot, `--cancel-stage` restores the original next-boot setup over SSH.
After reboot, reconnect over Ethernet; Wi-Fi will **not** automatically import
an NM profile. Select a Wi-Fi network in KDE and enter its password there.
NetworkManager controls the connections and IP addresses; iwd is retained only
as its Wi-Fi radio backend. Old iwd profiles remain on disk, and KMOS neither
reads nor exports their passwords. Test Wi-Fi with the cable unplugged only
after KDE shows an active NetworkManager Wi-Fi connection.

Alternatively, a **local-console-only live handoff** remains available. The
separate `--apply` command stops dhcpcd and the existing direct iwd Wi-Fi
connection, starts NetworkManager, checks wired internet, then waits while you
connect Wi-Fi from KDE and type `VERIFY WIFI` in the waiting terminal. Only
after both interfaces pass does it change the next-boot services. Never run
`--apply` over SSH. No packages are installed by either handoff.

```bash
./platforms/archlinux/tools/kmos-network-migration.sh --apply
```

An unsuccessful live handoff attempts to restore the prior services. If a
staged reboot fails, the boot guard attempts the fallback. If the live script
is killed unexpectedly, or if the result later needs to be reverted, use
`./platforms/archlinux/tools/kmos-network-migration.sh --rollback` **from the
local console**. It retains NetworkManager-created profiles but restores the
previous services and removes only KMOS's unchanged backend configuration.
Test unplugging Ethernet *after* Wi-Fi is verified, at the local console.
This switch is not field-verified yet; keep a way back to the local console.
