# Experimental headless → KDE (x86/next)

Use the live upgrade only on an **installed KMOS headless Arch x86_64** system,
not an Arch ISO or an arbitrary existing Arch/VPS installation. This work is
on `x86/next`, not `main` or `v0.9.0`.

**Verification snapshot (2026-10-10):** Fresh direct KDE and a headless → KDE
upgrade with visual defaults for multiple existing users were reported working
on hardware. NetworkManager's wired reboot handoff, connected Wi-Fi, and
Wi-Fi-only internet after unplugging Ethernet were previously verified; the
new Wi-Fi-SSH handoff was subsequently reported working, without captured
service diagnostics. The AUR-declined install path and Wi-Fi-only boot-guard
failure path still lack field tests. This remains on `x86/next`, not `main`.

From a checkout of `x86/next`, you can inspect the system with the optional
read-only check (the guided install also runs this check):

```bash
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
```

The legacy explicit `--install --profile full|noapps` options remain available
without AUR; the `noapps` manifest is also still used by Quartz64. It is **not**
part of guided x86 package selection. Guided ISO and live upgrades use the same
mandatory desktop package sets; the live upgrade requires local manifests
rather than fetching the published `main` manifests. The revised fresh-ISO
path was reported working on hardware; the AUR-declined path has only fixtures.

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
recommended flow. The guided KDE install has a reported successful hardware
test, but has not yet been merged into `main` or released as `v1.0.0`.

### Guided KDE package choices

- **Always:** shared Arch and terminal packages, KDE base, KDE apps (`ark`,
  `falkon`, `filelight`, `kate`, `kcalc`, `markdownpart`, `okular`,
  `partitionmanager`, `yakuake`, `ffmpegthumbs`, `gwenview`, `haruna`, `kamoso`,
  `kdenlive`, `kdegraphics-thumbnailers`, `kolourpaint`, `spectacle`,
  `qt6-multimedia-ffmpeg`, `tesseract-data-eng`), and
  desktop productivity (`firefox-developer-edition`). KDE base also resolves
  Plasma, audio (including `pipewire-jack`), device integration and filesystem
  tools. These explicit packages choose the FFmpeg, PipeWire JACK and English
  OCR providers without an installer prompt.
- **Kamilo productivity [Y/n]:** `bleachbit`, `filezilla`, `hunspell-en_us`,
  `inkscape`, `networkmanager-openvpn`, `openvpn`, `pass`, `rclone`, `rsync`,
  `rust` (which provides Cargo), `signal-desktop`, `simple-scan`, `torbrowser-launcher`,
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
confirmation and pacman transaction. The revised live-upgrade selector and
all-user visuals were reported working on hardware. An already upgraded KDE
machine is not a valid target
for re-running the installer. `--preflight` remains read-only; explicit
`--install` modes remain available for tests.

It performs a normal Arch
`pacman -Syu` transaction; inspect any proposed replacements or removals
before approving pacman's prompts. Back up important data first. For the first
real test, keep local console or Ethernet access available in case a package
upgrade interrupts SSH/Wi-Fi. Run the script as `./script.sh`, **not** by
prefixing `sudo`; it requests privileges itself and asks you to type
`INSTALL KDE` before any writes.

KMOS does **not** stop `iwd`, `dhcpcd`, or `sshd` during the upgrade. Unless you
separately approve next-boot staging, it does not change their enabled state or
enable NetworkManager. Plasma's network tray may not manage Wi-Fi while direct
iwd remains in charge; use the existing iwd/Impala connection until the
handoff. A system or package hook could still affect networking during a full
system upgrade.
The guided script stages KMOS's panel, wallpaper and color defaults only where
it does not overwrite personal configurations, enables SDDM for the next boot,
and calls the reviewable visual finishing pass **during the same invocation**
for every existing local regular account with a real home under `/home`, as
well as staging defaults for future users. Existing settings still need
individual approval and are backed up before replacement; personal panels
and wallpaper choices are never replaced. It does **not** run the ISO's destructive
font/package cleanup or install AUR packages. After finishing, it offers the
guarded **next-boot** NetworkManager handoff. Verified wired Ethernet uses the
wired handoff; when the wired safeguard cannot be used but Wi-Fi is working,
the guided flow instead offers a
Wi-Fi-only handoff with an explicit `STAGE WIFI` confirmation. Both paths change
only next-boot services, leave the active SSH connection alone, and do not
reboot automatically. The Wi-Fi-only path deliberately loses remote SSH after
reboot until you connect Wi-Fi again in KDE using a local screen and keyboard;
it does not read or migrate the old iwd password. If neither path is eligible,
networking stays under iwd/dhcpcd.
For a new panel, the Application Dashboard icon uses the SVG data from
`platforms/archlinux/assets/icons/kmos.ico`, installed as the uniquely named `kmos-dashboard` icon
in hicolor. It does not overwrite Breeze icons or change existing personal
panel configurations. An already-configured dashboard must be changed from
its KDE widget settings if its owner wants the new icon.

If package installation is interrupted, rerun with the **same profile** after
checking connectivity and pacman state. An in-progress marker allows retry; a
completed KMOS KDE profile makes subsequent runs a no-op. If finishing or
network staging is interrupted *after* KDE is marked complete, use the
individual `--apply` or `--stage-reboot` commands below instead. Existing non-KMOS KDE or a
different panel template is refused rather than replaced.

## Visual finishing and retries

The guided upgrade offers the reviewable finishing pass to **all local regular
users** automatically. For an older upgrade or a retry after interruption, you
can preview the KDE login/lock-screen look, Kappa/Konsole profile, Yakuake,
Kate, Dolphin and other desktop defaults for all local regular accounts:

```bash
./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --plan --all-users
```

The plan lists existing files that differ from the KMOS defaults and their
sizes. If you want those changes, run `./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --apply --all-users`.
The guided upgrade already asks for `INSTALL KDE`, so it skips the redundant
initial visual confirmation; standalone `--apply --all-users` still asks once.
**Each existing file** defaults to
**No**. Only approved replacements are saved under
`~/.local/share/kmos/backups/kde-<date>/` within each affected account for user files or
`/var/backups/kmos/kde-<date>/` for system files. Missing files are added
without prompting; no panels, wallpaper choices, networking, packages or
non-selected home files are changed. System-wide defaults can affect KDE
users without a personal override. It may download Kappa fonts with the existing
`curl` tool, but does not delete other fonts. Review the resulting KDE session
before removing any backup. Rerunning skips defaults that already match.

## NetworkManager handoff (x86/next experiment)

The KDE upgrade deliberately retains the headless `iwd`/`dhcpcd` connection
until a reboot following an approved handoff. The guided path offers wired or
Wi-Fi-only staging after the visual finish when its checks pass. On an already
upgraded machine, use the commands below without rerunning the KDE installer.
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
boot guard allows up to two minutes for NM-controlled Ethernet internet and
automatically restores iwd/dhcpcd if that fails. If both paths fail,
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

For **Wi-Fi-only SSH upgrades with local console access after reboot**, the
guided upgrade uses the same next-boot staging mechanism but does **not** need
a wired interface. Its explicit `STAGE WIFI` confirmation warns that SSH will
be lost on reboot. The boot guard accepts an available, disconnected NM Wi-Fi
device so you can enter the password in KDE; it restores iwd/dhcpcd only if
NM cannot manage that device. A missing Wi-Fi password is **not** considered
a boot failure. The old iwd profiles remain untouched, but NM does not import
them. If staging was interrupted after the KDE installer completed, use the
separate `--stage-reboot-wifi` command below; **do not rerun the installer**.
This Wi-Fi-only path has a reported successful install; the fallback on device
failure still has fixture tests only.

```bash
./platforms/archlinux/tools/kmos-network-migration.sh --stage-reboot-wifi
```

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

### Field results and remaining test

Two staged handoffs were verified on hardware. On one machine, NM controlled
Ethernet and Wi-Fi after reboot, and internet continued on Wi-Fi alone. On the
headless-to-KDE machine, the first boot check correctly rolled back to
`iwd`/`dhcpcd`: it waited about 24 seconds, shorter than NM's 45-second
Ethernet DHCP timeout. After extending the guarded wait to two minutes, the
next reboot completed with NM active/enabled, iwd active/disabled as its Wi-Fi
backend, dhcpcd inactive/disabled, and SSH routed over Ethernet. Wi-Fi
connected in KDE; an HTTPS request bound to `wlan0` succeeded. With Ethernet
unplugged, `wlan0` was the sole default route and unbound HTTPS also succeeded.
The local-only `--apply` path, automatic rollback on a **genuinely failed** NM
connection with the longer wait, and switching SSIDs in KDE remain unverified
on hardware. The earlier short-timeout rollback did work. The guided Wi-Fi-only
handoff was subsequently reported successful over Wi-Fi SSH, but detailed
service logs and a failed-NM Wi-Fi boot-guard test were not provided.

## Final field-test checklist (before any release merge)

Use a **dedicated test machine** and a fresh Arch x86_64 ISO. Keep Ethernet
and local-console access available; back up data. From an `x86/next` checkout
on the live ISO, run `./kmos-install.sh` without profile flags. The ISO installer
formats selected partitions; verify the disk/EFI target before typing `FORMAT`.

1. **Fresh KDE:** inspect the concise package questions before `FORMAT`. Check
   Kamilo productivity defaults to Yes, free-text repository extras persist,
   and AUR consent defaults to Yes. With AUR approved, confirm `tododo-bin` and
   any explicitly selected extras; do not assume optional drivers are selected
   automatically. To verify the decline path, use a *separate fresh install*
   (never rerun the ISO installer on an installed system) and check that neither
   an AUR helper nor AUR packages are installed.
   On first boot, check Spectacle, Kdenlive, Firefox Developer Edition, chosen
   productivity packages, the new-panel Dashboard icon, and networking. Confirm
   pacman does not ask for rust/rustup, JACK, Qt multimedia or tessdata providers.
2. **Fresh headless → KDE:** on a fresh *headless* KMOS install, obtain an
   `x86/next` checkout and run `./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh`
   as a regular user, without `sudo` or profile flags. Confirm **the same run**
   guides package selection, offers reviewable visual finishing for all local
   regular users with backups, and asks separately to stage NM for next boot.
   Verified wired internet uses the wired guard; a working Wi-Fi connection
   without a suitable wired/SSH fallback offers the Wi-Fi-only guard, which
   requires reconnecting in KDE after reboot and local-console access.
   It must not stop active SSH/network services or reboot automatically. After
   the deliberate reboot, check KDE visuals without overwriting personal panels,
   NM Ethernet, Wi-Fi connected through KDE, and Wi-Fi-only internet at the
   local console with Ethernet unplugged. A disconnected Wi-Fi interface before
   staging is supported, but Wi-Fi credentials must be entered in KDE afterward.

Do not rerun the ISO installer on the installed system or rerun the live KDE
installer after KDE is marked complete. Capture results and unresolved failures
before deciding whether to merge `x86/next` into `main`.
