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
The helper enables iwd, networkd and resolved for later boots and does not
write a speculative profile before association. A failed attempt offers retry
or `CANCEL`; an existing profile is backed up before trying new credentials.
It preserves an existing compatible `/etc/iwd/main.conf`, including driver
quirks, instead of erasing them. On a fresh iwd config with the detected
`brcmfmac` driver, it writes the board-tested `SaeDisable=brcmfmac` WPA2
workaround **before starting/restarting iwd**; a new config also survives
reboot. It does not add that quirk to an existing config automatically.
This quirk disables SAE on brcmfmac, so WPA3-only networks cannot connect
with it. If your network is WPA3-only, use `--allow-sae` with the checkout's
standalone Wi-Fi helper on a **new** iwd config (and decline the provisioner's
Wi-Fi prompt); it will not overwrite an existing quirk. SAE has not been
validated on this board. None of this cures the repeated authentication
timeouts seen on Kasa after reboot, even with the manual quirk in place.
Like the x86 helper, `iwctl --passphrase` briefly exposes the passphrase in
process arguments; do not use it on an untrusted multi-user system. Changing
an active Wi-Fi connection over SSH is blocked: **use the local console** in
that case. A successful connection does **not** prove reboot persistence:
keep Ethernet connected for recovery, reboot, then verify the Wi-Fi address,
route and internet before relying on Wi-Fi-only SSH. If the adapter or
firmware is missing, the helper stops before installing packages; temporary
networking or a compatible adapter will be necessary.

The headless provisioner offers optional Wi-Fi setup **before package updates**
and calls the same helper from the checkout. Decline to continue over Ethernet
without changing Wi-Fi, or run the standalone helper later from the checkout:
`./platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh`.
Updating the Git checkout does not update an older SD-card copy at
`/root/connect-quartz64b-wifi.sh`; use the checkout copy to preserve existing
iwd settings and get the fresh-config brcmfmac workaround.
If the board remains online after a Wi-Fi association error, verify whether
Ethernet or Wi-Fi carries the connection before rebooting. A Wi-Fi error does
not require rerunning headless provisioning.

## Provision KMOS headless

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
Arch Linux ARM `starship` package is required; provisioning stops rather than
claiming a working prompt if it cannot be installed or rendered.

Headless provisioning first offers Wi-Fi, then installs available ARM CLI packages, asks before
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
Syncthing and removal of the default `alarm` account are optional. Confirming
removal deletes `/home/alarm` and all its contents, including any checkout
there. If the installer is running from `alarm`, it locks the account and
schedules removal before SSH logins on the next boot; it does not claim removal
until it succeeds. After reboot, `getent passwd alarm` must print nothing.
For a board already installed with `alarm` still present, run this from the
new administrator session instead of repeating provisioning:

```bash
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh remove-alarm
```

The headless run offers Wi-Fi but not KDE. Keep Ethernet connected for recovery
until Wi-Fi survives reboot and SSH over Wi-Fi is verified. Provisioning does
not rewrite partitions, U-Boot, or extlinux boot files, but its initial system
update may update the board's kernel packages.

**KDE is not offered on Quartz64.** The earlier experimental stage failed on
physical hardware and has been disabled pending a separate diagnosis. Over
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

After headless verification, the provisioner offers an **optional** AUR helper.
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
