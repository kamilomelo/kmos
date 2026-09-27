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

The script asks for root access through the system `sudo` password prompt. It then lists removable/SD disks, with size, model and transport. If only one is found, confirm that it is your card; otherwise choose its number. A separate erase confirmation defaults to `N`. It asks for a new `root` password and optionally for first-boot WPA-Personal Wi-Fi credentials. If Wi-Fi is selected, it verifies that the PGP-checked ARM rootfs already contains `iwd` **before writing to the card**; otherwise it stops, rather than promising offline networking it cannot provide. It erases the selected card, installs U-Boot, configures the Model B device tree, and enables DHCP Ethernet, DNS, and SSH. Wi-Fi credentials, when provided, are saved in an `0600` iwd profile, with DHCP handled by `systemd-networkd`. The normal workflow needs no `--device` argument.

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

## Network before provisioning

Ethernet is not required if the first-boot Wi-Fi option was selected and the
board has a working wireless adapter and firmware. To configure a different
network on a newly prepared card, log in locally as root and run the helper
already on the card: `cd /root && ./connect-quartz64b-wifi.sh`. It requires
`iwd` already installed, never puts the passphrase in a command argument, and
does not replace a saved profile. Cards prepared before this option was added
will not have this helper. If the adapter/firmware or `iwd` is missing, use
Ethernet or temporary USB tethering, or obtain the necessary verified ARM
packages offline. Check DHCP/DNS and reboot persistence before fetching KMOS.

## Provision KMOS headless, then optionally KDE

After confirming internet access on the booted Quartz64, download the
provisioner from the published GitHub `main` branch and run it from the local
console (shown for a root login). The cloned checkout is pinned to the commit
that GitHub returns when the run begins:

```bash
curl -fL -o provision-kmos-headless.sh \
  https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
chmod +x provision-kmos-headless.sh
./provision-kmos-headless.sh
```

It asks before any update, initializes Arch Linux ARM's keyring, updates the
system, installs the base tools and `git`, then clones KMOS over HTTPS into a
unique private directory under `/var/tmp`. It records the cloned commit and
uses that checkout for all manifests and assets. If the downloaded entry point
differs from the cloned commit, it restarts from the cloned version. The clone
is retained for inspection; it is never silently replaced or deleted.

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
- First-boot Wi-Fi supports only WPA-Personal SSIDs with ASCII letters,
  digits, spaces, underscores and hyphens. The rootfs must include `iwd` and
  the board must have a working wireless adapter and firmware; this has not
  been tested on physical wireless hardware yet.
- The availability of headless and KDE packages in the AArch64 repositories,
  the GPU/DRM stack, and the KDE session must be checked on the actual board.
  Source builds and NetworkManager migration are **not automated** yet.
