# Experimental headless → KDE (x86/next)

Use only on an **installed KMOS headless Arch x86_64** system, not an Arch ISO
and not an arbitrary existing Arch/VPS installation. This path is not part of
`main` or `v0.9.0`. A real headless → KDE upgrade and the KDE finishing pass
were reported working. The staged SSH-to-NetworkManager reboot handoff was
verified on Ethernet and with **Wi-Fi only** after the cable was unplugged.

From a checkout of `x86/next`, you can inspect the system with the optional
read-only check (the guided install also runs this check):

```bash
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
```

The legacy explicit `--install --profile full|noapps` options remain available
without AUR; the `noapps` manifest is also still used by Quartz64. It is **not**
part of guided x86 package selection. Guided ISO and live upgrades use the same
mandatory desktop package sets; the live upgrade requires local manifests
rather than fetching the published `main` manifests. This reorganized selection has only
been checked with offline fixtures, not a new ISO installation.

On the **experimental x86/next Arch ISO installer**, `./kmos-install.sh` always
installs the shared Arch CLI tools. Choosing KDE adds mandatory KDE base,
KDE apps (including Spectacle and Kdenlive), and desktop productivity
(`firefox-developer-edition`). Kamilo productivity is asked with **Yes** as the
default; the full package list is below. The free-text official-repository
package prompt remains. AUR is asked separately (yes by default): choose `paru` or
`yay`, then select optional AUR packages by name or with `fzf` when already
available; `tododo-bin` is included only when AUR is approved. All choices and
local manifests are validated **before** final disk approval/format. There is
no Firefox pruning policy; guided installs also skip the old font/package
cleanup. Explicit `--profile full|noapps` remains for compatibility, not the
recommended flow. **This reorganization is fixture-tested only; do not treat
it as a field-tested replacement for `main`/`v0.9.0`.**

### Guided KDE package choices

- **Always:** shared Arch and terminal packages, KDE base, KDE apps (`ark`,
  `falkon`, `filelight`, `kate`, `kcalc`, `markdownpart`, `okular`,
  `partitionmanager`, `yakuake`, `ffmpegthumbs`, `gwenview`, `haruna`, `kamoso`,
  `kdenlive`, `kdegraphics-thumbnailers`, `kolourpaint`, `spectacle`), and
  desktop productivity (`firefox-developer-edition`). KDE base also resolves
  Plasma, audio, device integration and filesystem tools.
- **Kamilo productivity [Y/n]:** `bleachbit`, `filezilla`, `hunspell-en_us`,
  `inkscape`, `networkmanager-openvpn`, `openvpn`, `pass`, `rclone`, `rsync`,
  `rust`, `cargo`, `signal-desktop`, `simple-scan`, `torbrowser-launcher`,
  `torsocks`, `typst`, `wqy-microhei`.
- **AUR [Y/n]:** if approved, installs `tododo-bin`; helper defaults to `paru`
  (or choose `yay`). Optional AUR names are `brother-ql1100nwb`,
  `kchat-appimage`, `kdrive-bin`, `onlyoffice-bin`, `paisa-bin`,
  `rtl8821au-dkms-git`. These extras are **not** selected automatically;
  hardware-specific drivers must be chosen explicitly. If `fzf` is already
  present, it can select extras; otherwise type their names. Enter chooses
  no extras.
- **Extra repo packages:** enter additional official-repository package names,
  or press Enter for none. This is separate from the predefined groups.

No package defaults change the explicit disk/partition choices or the `FORMAT`
confirmation.

On a **new headless → KDE upgrade**, run the script without arguments to
choose the optional Kamilo set and extra official-repository packages:

```bash
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh
```

This always includes KDE base, KDE apps and mandatory desktop productivity.
The optional Kamilo choice defaults to Yes (see the package list above);
extra repository names are entered separately. This live upgrade does **not** install
`fzf` or AUR packages. The selection is shown before the `INSTALL KDE`
confirmation and pacman transaction. The revised live-upgrade selector is
**fixture-tested only**. An already upgraded KDE machine is not a valid target
for re-running the installer. `--preflight` remains read-only; explicit
`--install` modes remain available for tests.

It performs a normal Arch
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
For a new panel, the Application Dashboard icon uses the SVG data from
`platforms/archlinux/assets/icons/kmos.ico`, installed as the uniquely named `kmos-dashboard` icon
in hicolor. It does not overwrite Breeze icons or change existing personal
panel configurations. An already-configured dashboard must be changed from
its KDE widget settings if its owner wants the new icon.

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
After reboot, reconnect over Ethernet. KMOS does **not** copy existing iwd
credentials into a NetworkManager profile; if Wi-Fi is not connected under
NetworkManager, select a network in KDE and enter its password there.
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

**Field result (2026-10-09):** The staged reboot completed with NetworkManager
controlling Ethernet and Wi-Fi, iwd active only as the Wi-Fi backend, dhcpcd
inactive, and SSH routed over Ethernet. The Wi-Fi device showed connected in
`nmcli`; a request bound to `wlan0` succeeded. After Ethernet was unplugged,
the default route used `wlan0` alone and internet access still worked. The
local-only `--apply` path, automatic failure fallback, and switching between
different Wi-Fi SSIDs in KDE remain **unverified on real hardware**.
