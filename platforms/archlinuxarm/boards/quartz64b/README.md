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

The script asks for root access through the system `sudo` password prompt. It then lists removable/SD disks, with size, model and transport. If only one is found, confirm that it is your card; otherwise choose its number. A separate erase confirmation defaults to `N`. It then asks for a new `root` password. It erases the selected card, verifies the Arch Linux ARM rootfs PGP signature, installs U-Boot, configures the Model B device tree, and enables DHCP Ethernet, DNS, and SSH. The normal workflow needs no `--device` argument.

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

Connect UART at `1500000` baud if you need the boot console, connect Ethernet, insert the card, and power the board. Log in as `root` using the password chosen during card preparation. DHCP should provide networking automatically.

The KMOS headless provisioner runs on this initialized Arch Linux ARM system; it does not replace the Quartz64 bootloader or kernel.

## Provision KMOS headless

Transfer a **matching copy of the local kmos files** to the booted Quartz64
using a USB drive or your local network. Keep these paths together:
`platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh`,
`platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD`, and
`platforms/archlinux/assets/starship-presets/`. Copying the script alone, or
cloning remote `main` while these changes are not published, will not work.
The provisioner does not fetch a different repository revision. It checks the
local files **before** updating packages or changing system configuration.

For example, on the host create a small archive on an already-mounted USB
drive (replace the paths with your actual kmos and USB mount points):

```bash
tar -C /path/to/local/kmos -czf /path/to/mounted-usb/kmos-quartz.tar.gz \
  platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh \
  platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD \
  platforms/archlinux/assets/starship-presets
```

Safely unmount the drive, connect it to the Quartz64, and mount it there.
From the board's root console, extract it to a writable location (replace the
USB path with its mount point on the board):

```bash
mkdir -p /root/kmos
tar -xzf /path/to/mounted-usb/kmos-quartz.tar.gz -C /root/kmos
cd /root/kmos
```

From inside that copied tree on the Quartz64, run the script while Ethernet is
connected. It asks for root access through `sudo` if you are not already root:

```bash
./platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
```

It first asks permission to update Arch Linux ARM, initializes its package
keyring, and installs `iwd`, `nano`, `openssh`, and `sudo` as needed. It reads
the local `nodesktop` package set, checks AArch64 availability, and asks you
whether to skip an unavailable package or cancel. Only selected packages are
installed and checked afterward. Then it installs terminal presets, prompts
for hostname, timezone (default `Europe/Zurich`), locale, administrator and
optional users, and swap size (default `4G`, or `0` to skip). It configures
SSH (root login disabled, password login for normal users allowed), DHCP
Ethernet and DNS; Wi-Fi is **optional and defaults to no**. You may enable
Syncthing and remove the default `alarm` account after the administrator is
created. Ethernet has a lower route metric than Wi-Fi. It does **not** change
the board's kernel, partitions, U-Boot or extlinux boot files, and it does not
install KDE yet. Reboot when it reports completion.

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
- First boot requires Ethernet: provisioning initializes pacman and installs
  `iwd` **before** its interactive Wi-Fi setup. Offline first-boot Wi-Fi is
  not implemented.
- Bring the current local kmos files to the board before running the
  provisioner. The availability of every package in the AArch64 repositories
  must be checked at run time; no KDE stage is implemented for this board yet.
- The post-boot Wi-Fi setup still passes its password to `iwctl` as a process
  argument. Avoid production Wi-Fi credentials until this path can be tested
  and hardened on the board. The provisioner no longer clones or removes
  work directories.
