# Experimental headless → KDE (x86/next)

Use only on an **installed KMOS headless Arch x86_64** system, not an Arch ISO
and not an arbitrary existing Arch/VPS installation. This path is not part of
`main` or `v0.9.0` and has **only mocked tests**, not a real upgrade test yet.

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
