# Quartz64 Model B: Arch Linux ARM SD preparation

`prepare-quartz64b-sd.sh` creates a bootable Arch Linux ARM SD card for a Pine64 Quartz64 Model B from an Arch Linux host.

## Requirements

- An 8 GiB or larger SD card connected to the host.
- Ethernet with DHCP connected to the Quartz64 for its first boot.
- Host commands: `parted`, `dosfstools`, `e2fsprogs`, `curl`, `gnupg`, `bsdtar` (libarchive), `openssl`, and standard `util-linux` tools. The script checks for required tools before it changes any device.

On a kmos host, use the tools already installed. If the script reports a
missing command, check why it is needed before installing anything new.

## Create the card

```bash
./prepare-quartz64b-sd.sh
```

The script asks for root access through the system `sudo` password prompt. It then lists removable/SD disks, with size, model and transport. If only one is found, confirm that it is your card; otherwise choose its number. A separate erase confirmation defaults to `N`. It asks for a new `root` password, then offers to include offline Wi-Fi packages (default: yes). It prepares the normal bootable card and copies a manual Wi-Fi helper into `/root/`. When staging is selected, it downloads official AArch64 `ell` and `iwd` packages plus signatures, checks repository SHA-256 hashes, architecture and expected dependencies, and copies them onto the card. **The host does not install them or configure Wi-Fi.** Pacman verifies the package signatures against the Arch Linux ARM keyring when you choose to install them on the board. The script also installs U-Boot, configures the Model B device tree, and enables DHCP Ethernet, DNS, and SSH. The normal workflow needs no `--device` argument.

Downloads, the rootfs signature and U-Boot artifact are stored in `work/` next to the script. The temporary PGP keyring is removed after verification. At the end of a successful run, choose whether to keep the default work directory for another SD card or delete it. The directory is retained automatically after a failure. A custom `--work-dir` is always preserved and must be removed manually after inspection.

To remove the default root-owned cache later, run this from the **host** in
the Quartz64 directory. It does not touch a device: it checks for mounts,
asks for `DELETE`, and requests sudo itself. Custom work directories are never
touched:

```bash
./prepare-quartz64b-sd.sh --clean-work
```

The folder has three executable scripts: host SD preparation, on-board
headless setup/maintenance, and the separate on-board manual Wi-Fi helper.
The console Starship preset lives in `assets/`. SD preparation copies only
the self-contained Wi-Fi script into the board's `/root/`.

The rootfs is downloaded from an official Arch Linux ARM mirror with valid HTTPS and is verified using the official PGP signature before it is written to the SD.

The default U-Boot source is the exact GitLab CI artifact linked by Pine64's old Quartz64 Arch Linux ARM guide. It is old and not signed. For repeatable testing, archive it locally, record its digest, then use:

```bash
sha256sum quartz64-artifact.zip
./prepare-quartz64b-sd.sh \
  --device /dev/sdX \
  --bootloader-archive ./quartz64-artifact.zip \
  --bootloader-sha256 YOUR_RECORDED_SHA256
```

## First boot

Connect UART at `1500000` baud if you need the boot console, insert the card, and power the board. Log in as `root` using the password chosen during card preparation. If Ethernet is connected, DHCP should provide networking automatically. If not, use the local console to run the Wi-Fi helper below.

The KMOS headless provisioner runs on this initialized Arch Linux ARM system; it does not replace the Quartz64 bootloader or kernel.

## Network before provisioning

Ethernet is **not** required to run the helper if the board has a supported
wireless adapter and firmware and the signed offline packages were staged.
From the Quartz64's local root console:

```bash
cd /root
./connect-quartz64b-wifi.sh
```

The helper first detects a wireless interface. If `iwd` is missing, it asks
before installing the staged ARM `ell` and `iwd` packages locally with
`pacman -U` and **required signature verification**. As in the x86 Arch live
helper, it then scans, asks for your network and passphrase, connects with
`iwctl`, and checks association, the iwd-generated root-only profile, DHCP,
a Wi-Fi default route and internet **over the Wi-Fi adapter**, not Ethernet.
It does not rescan between the selection and connection (a second scan can
race with iwd); a scan already in progress still permits reading the current
network list. The connection command has a 45-second limit so it cannot block
the helper indefinitely. On a physical board, the saved WPA2 profile for
`KM-R-WiFi-GST` reconnected promptly after reboot and SSH worked over Wi-Fi.
This is the same-machine equivalent of copying the working iwd profile from
the live system into the target: it already lives in persistent `/var/lib/iwd`.
The helper enables iwd and resolved for later boots and does not
write a speculative profile before association. A failed attempt offers retry
or `CANCEL`; an existing profile is backed up before trying new credentials.
Like the x86 live-to-installed handoff, iwd owns Wi-Fi association, DHCP and
DNS (through systemd-resolved). On Quartz64 no profile copy is needed: iwd
creates it directly in the installed system's persistent `/var/lib/iwd`.
Networkd remains enabled for Ethernet only. The helper backs up and removes
KMOS's older Wi-Fi networkd file when switching an existing installation; it
refuses to overwrite a custom networkd Wi-Fi file. An existing iwd config is
backed up before updating its DHCP/DNS keys; driver quirks are preserved.
Fresh configs leave SAE/WPA3 enabled; a previously configured
`SaeDisable=brcmfmac` quirk is preserved, not added automatically. The Kasa
network still showed authentication timeouts after reboot even with this quirk.
At the **end of provisioning**, whether the update used Ethernet or Wi-Fi, the
installer offers **Impala/iwd (default), wpa_supplicant fallback, or Skip**.
If wpa_supplicant is already active or enabled, that tested backend becomes
the default instead: selecting Impala will not replace its working profile.
Impala is the interactive Wi-Fi picker, not a background service: **iwd**
retains the profile in `/var/lib/iwd` and reconnects at boot. The script
installs `impala` and `iwd` from the ARM repositories, configures iwd DHCP/DNS,
opens Impala on an interactive terminal (ASCII mode), then checks a saved,
autoconnecting profile, address, route, and Wi-Fi-bound internet. Run `impala`
later to change SSIDs. When Impala is unavailable in a configured repository,
the installer offers iwd/iwctl instead; it does not silently substitute a
downloaded executable or source build. A board without Ethernet can still
use iwd to bootstrap the initial update before Impala is installed.

Selecting the **wpa_supplicant fallback** preserves and verifies an existing
profile; otherwise it installs the ARM package and switches backends. For that
switch it reuses a usable WPA2 PSK or
passphrase from the active, root-only iwd profile, without asking a second
time. If the saved credentials cannot be safely read, it asks again. iwd
profiles are kept for rollback, but iwd is stopped and disabled before
wpa_supplicant starts.
If Wi-Fi is skipped after iwd was used for bootstrap, iwd is disabled for
future boots but the current connection is left up; without Ethernet the
installer skips automatic reboot and warns that a recovery connection is needed.
For the fallback, networkd supplies Wi-Fi DHCP and resolved supplies DNS;
for Impala/iwd, iwd supplies Wi-Fi DHCP and resolved supplies DNS. No two Wi-Fi
managers should run together. A failed fallback switch attempts to restore iwd, and provisioning
stops rather than claiming a persistent Wi-Fi setup. The generated profile
has mode `600`, a PSK rather than a plaintext passphrase, and the control socket
needed for `wpa_cli`. An older trial profile lacking `ctrl_interface` needs
manual review; the installer does not overwrite it.

The standalone trial remains available for an already-installed board with
Ethernet recovery: run `./platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh`
from the local console. To verify a reboot, run its read-only `--check` mode;
it waits up to 30 seconds for association, address, route and Wi-Fi internet.
The `KM-R-WiFi-RBT` network passed a real reboot check on one physical board;
this is not yet fleet reliability validation.
On an already-provisioned board with Ethernet recovery, run
`./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh wifi-fallback`
to install the ARM package if necessary and switch without repeating the full
installation. Confirm the update before proceeding if the package is missing.
Like the x86 helper, `iwctl --passphrase` briefly exposes the passphrase in
process arguments; do not use it on an untrusted multi-user system. Changing
an active Wi-Fi connection over SSH is blocked: **use the local console** in
that case. A successful connection does **not** prove reboot persistence:
keep Ethernet connected for recovery, reboot, then verify the Wi-Fi address,
route and internet before relying on Wi-Fi-only SSH. If the adapter or
firmware is missing, the helper stops before installing packages; temporary
networking or a compatible adapter will be necessary.

The provisioner chooses persistent Wi-Fi **after base setup**, before the KDE
choice, optional AUR helper, final network check and reboot. Run the
standalone bootstrap helper when networking is needed before cloning the checkout:
`./platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh`.
Updating the Git checkout does not update an older SD-card copy at
`/root/connect-quartz64b-wifi.sh`; use the checkout copy to preserve existing
iwd settings and get the fresh-config brcmfmac workaround.
If the board remains online after a Wi-Fi association error, verify whether
Ethernet or Wi-Fi carries the connection before rebooting. A Wi-Fi error does
not require rerunning headless provisioning.

## Provision KMOS (headless or KDE)

After confirming internet access on the booted Quartz64, use `git` to clone
the repository and run its executable provisioner. From the local root console:

```bash
command -v git
git clone https://github.com/kamilomelo/kmos.git
cd kmos
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
```

If `command -v git` prints nothing, Git must first be installed **on the
board** using its working network. Do not attempt the clone until it is
available. The provisioner validates the local checkout and reports its commit
before asking permission to make changes. It never fetches another copy or
replaces files in your clone. Its initial `pacman -Syu` can update the board
kernel, so back up the working card before confirming provisioning. The
initial provisioning confirmation defaults to **Yes**; the Wi-Fi backend
question defaults to Impala/iwd unless a wpa_supplicant service is already
active or enabled, in which case it defaults to preserving wpa_supplicant.
Select **3** to skip Wi-Fi. The
Arch Linux ARM `starship` package is required; provisioning stops rather than
claiming a working prompt if it cannot be installed or rendered.

Headless provisioning brings up temporary Wi-Fi only if Ethernet is absent,
then installs available ARM CLI packages, asks before
skipping unavailable packages, installs the four Kappa Mono Nerd Font TTF
styles from the Kappa Type GitHub repository using `git`, and configures
terminal presets, hostname, timezone
(default `Europe/Zurich`), locale, administrator and optional users, swap
(default `4G`, `0` to omit), SSH (root login disabled), and DHCP Ethernet/DNS.
After verification, the optional AUR choice, and a live internet check against
GitHub, a success banner offers a 10-second countdown: press any key to stay in
the current session, or let it
reboot automatically. Without an interactive terminal, it skips automatic
reboot. Board maintenance commands (`repair-prompt`, `fonts`, `aur`, and
`remove-alarm`) never trigger this countdown.
If SSH, networking, or live internet access is unavailable at the end, the
provisioner stops without claiming completion or rebooting; keep the recovery
connection attached and diagnose the failure instead of repeating provisioning.
Syncthing is optional. Once the replacement wheel administrator exists, the
installer removes the default `alarm` login automatically without a prompt.
It **does not delete `/home/alarm`** or any checkout/files there; review them
manually later. If the installer is running from `alarm`, it locks the account and
schedules removal before SSH logins on the next boot; it does not claim removal
until it succeeds. After reboot, `getent passwd alarm` must print nothing.
For a board already installed with `alarm` still present, run this from the
new administrator session instead of repeating provisioning:

```bash
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh remove-alarm
```

After the base headless setup and persistent Wi-Fi choice, the installer asks
**“Do you want to install a desktop?”** (default **Yes**), like the x86
installer. Answer **No** to keep it headless; answer **Yes** for KDE and select
`full` (default) or `noapps`. KDE uses the same x86 package manifests, but only
available AArch64 repository packages are selected. Missing optional packages
are listed and can be skipped with one confirmation. If a core Plasma/SDDM
component is absent, KDE is not installed and the headless boot target stays
in place. The Linux text console and SSH remain available in either case.

The x86 manifest includes NetworkManager, plasma-nm and another login manager.
Quartz64 excludes those entries and keeps the **selected standalone Wi-Fi
backend** (iwd or wpa_supplicant) and **SDDM** for the login screen. Installing
KDE does **not** automatically migrate Wi-Fi to NetworkManager or remove
Impala. If NetworkManager is migrated and **survives a reboot**, the optional
`./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh remove-impala`
command checks that NetworkManager is active and enabled, standalone iwd and
wpa_supplicant are inactive and disabled, no KMOS Wi-Fi networkd DHCP file is
present, and Wi-Fi has an address, default route and internet. It then asks
before removing **only the Impala TUI**; saved iwd profiles are preserved for
recovery. Merely installing NetworkManager is not sufficient to remove it.
A missing DRM graphics card
requires explicit permission to try KDE; an installed package set cannot prove
that a graphical session will work on the board. No x86 binaries or unreviewed
AUR replacements are installed. For an already-provisioned board, use
`./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh kde` to
offer KDE without rerunning accounts, swap or Wi-Fi setup; it asks before the
required full ARM package update.

Keep Ethernet connected for recovery
until Wi-Fi survives reboot and SSH over Wi-Fi is verified. Provisioning does
not rewrite partitions, U-Boot, or extlinux boot files, but its initial system
update may update the board's kernel packages.

The earlier experimental KDE stage failed on physical hardware; **this KDE
path is still unverified on a physical Quartz64**. Over
**SSH**, headless Starship uses KMOS's icon-based `holow-light.toml` preset,
as the x86_64 installer does. The physical Linux text console instead uses
the ASCII-only `starship-headless.toml` preset. **Kappa Mono is installed as
part of headless KMOS**; the ASCII console fallback does not omit the font.
No extra host package or board `fontconfig` package is required: if fontconfig
is already present, its cache and font-family lookup are checked. The Linux
text console cannot render desktop fonts, and an SSH session is rendered by
the terminal on your *other computer*: select Kappa Mono there to display
the prompt's Nerd glyphs. The provisioner checks that both Starship presets
render and that a fresh SSH-style Bash selects the icon preset.

After the headless/KDE choice, the provisioner offers an **optional** AUR helper
for headless or `full` KDE installs; the `noapps` profile skips it.
Answer once whether to install one, then select `1) paru` (default) or `2) yay`.
That choice installs its board-side build dependencies (`base-devel` and `go`
for yay, or `base-devel`, `rust`, and `cargo` for paru) and builds the AUR
source as the administrator without further y/N prompts. It never uses
`yay-bin`, `paru-bin`, or an x86 binary. Choosing a helper also authorizes
running its third-party PKGBUILD without a separate review prompt; inspect
the retained checkout afterward if needed. `makepkg` can still ask
for the administrator's normal sudo authentication for package transactions;
the installer does not enable passwordless sudo. Builds can be slow and need
disk space, and AUR packages may not support AArch64. Build checkouts are kept
for inspection. To choose a helper later without repeating provisioning:

```bash
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh aur
```

On a board provisioned by an older version, repair **only** the prompt without
reinstalling or repeating system updates. From the existing KMOS checkout:

```bash
git pull --ff-only
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh repair-prompt
```

Start a new SSH session to check the prompt. This command does not install KDE,
change networking, or rerun the headless provisioner. If `starship` was missing
on the old install, it asks before a full Arch Linux ARM update to install the
official AArch64 package; **that update may change the board kernel**. Declining
leaves packages untouched, and the repair will not claim success.

To add Kappa Mono to an **existing** headless board without repeating the
system update or provisioning, run from the KMOS checkout:

```bash
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh fonts
```

## Current limitations

- SD preparation now traces the host root filesystem and script checkout
  through LVM, encryption, and RAID block-device ancestry. It refuses unknown
  layouts and hosts using Btrfs for either location rather than guessing at
  possible multi-device filesystems. These checks have only been exercised
  with mocked devices, not a real SD writer. **Always verify the target and
  back up the card**; `--yes-really-erase` bypasses interactive confirmation.
- The default legacy U-Boot artifact has no trusted upstream signature. A
  SHA-256 provided with `--bootloader-sha256` only helps if the expected value
  was obtained from a trusted source.
- Manual first-boot Wi-Fi supports only WPA-Personal SSIDs with ASCII letters,
  digits, spaces, underscores and hyphens. The board must have a working
  wireless adapter and firmware; offline package installation and association
  have only been mocked, not tested on physical wireless hardware yet. If an
  official package changes dependencies, SD preparation stops for review.
- Headless package availability on AArch64 still depends on the repositories.
  The GPU/DRM stack and KDE session require separate on-board diagnosis; KDE
  is not part of this provisioner. KDE source builds and NetworkManager
  migration are **not automated**.
