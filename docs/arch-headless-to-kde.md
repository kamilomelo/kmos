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

For the first handoff, use a **local KDE terminal with a working Ethernet cable
attached**, not SSH. The separate `--apply` command first checks real wired
internet through the Ethernet interface, asks you to type `MIGRATE NETWORK`,
and stops dhcpcd and the existing direct iwd Wi-Fi connection. It then starts
NetworkManager with **iwd as its Wi-Fi radio backend**. NetworkManager controls
the connections and IP addresses; `iwctl` no longer manages them. Saved iwd
profiles are not removed or exported. After wired networking is verified under
NetworkManager, reconnect to Wi-Fi using KDE's network menu (enter credentials
there), then type `VERIFY WIFI` in the waiting terminal. Only after *both*
interfaces pass verification does the script enable NetworkManager on boot
and disable the old dhcpcd/iwd boot units. No packages or Wi-Fi credentials
are added by KMOS.

```bash
./platforms/archlinux/tools/kmos-network-migration.sh --apply
```

An unsuccessful handoff attempts to restore the prior services. If the script
is killed unexpectedly, or if the result later needs to be reverted, use
`./platforms/archlinux/tools/kmos-network-migration.sh --rollback` **from the
local console**. It retains NetworkManager-created profiles but restores the
previous services and removes only KMOS's unchanged backend configuration.
Test unplugging Ethernet *after* Wi-Fi is verified, at the local console.
This switch is not field-verified yet; keep a way back to the local console.
