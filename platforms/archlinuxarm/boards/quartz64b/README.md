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
`pacman -U` and **required signature verification**. Then it scans, asks for
your Wi-Fi SSID and passphrase, stores a root-only WPA-Personal profile, and
enables persistent `iwd` plus DHCP through `systemd-networkd`. The passphrase
is never passed as a process argument. Check `networkctl status` and verify the
connection survives a reboot before provisioning KMOS. If the adapter or
firmware is missing, the helper stops before installing packages; temporary
networking or a compatible adapter will be necessary.

## Provision KMOS headless, then optionally KDE

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
kernel, so back up the working card before confirming provisioning.

Headless provisioning installs available ARM CLI packages, asks before
skipping unavailable packages, configures terminal presets, hostname, timezone
(default `Europe/Zurich`), locale, administrator and optional users, swap
(default `4G`, `0` to omit), SSH (root login disabled), and DHCP Ethernet/DNS.
Wi-Fi is optional; an existing iwd profile is kept if you decline to reconfigure
it. Syncthing and removal of the default `alarm` account are optional. After
verifying headless setup it asks whether to install KDE (`noapps` or `full`).
KDE is blocked if DRM hardware or essential ARM packages are missing, and
missing optional packages require explicit consent to skip. It does not
automatically build sources or run x86 KDE post-install tweaks. KDE uses the
existing working `iwd`/`systemd-networkd` connection for now: NetworkManager
is installed but **not activated** until a safe on-board network migration is
validated. Reboot and verify the desktop and network locally. Neither stage
changes the board's kernel, partitions, U-Boot, or extlinux boot files.

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
- The availability of headless and KDE packages in the AArch64 repositories,
  the GPU/DRM stack, and the KDE session must be checked on the actual board.
  Source builds and NetworkManager migration are **not automated** yet.
