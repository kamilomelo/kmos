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
your Wi-Fi network number (or the exact SSID) and passphrase, stores a root-only
WPA-Personal profile, and
enables persistent `iwd` plus DHCP through `systemd-networkd`. The passphrase
is never passed as a process argument. Failed association or missing Wi-Fi DHCP
route returns to the SSID prompt, removes the failed profile, and restores any
existing profile it temporarily replaced. If a saved profile already exists,
the helper offers to test it before asking for a new password. If Wi-Fi
associates but DHCP fails, it keeps the profile and offers DHCP retries rather
than asking for the password again. Type `CANCEL` at the SSID prompt to stop
explicitly. An already connected Wi-Fi link is accepted only when its
matching root-only auto-connect profile, DHCP address, Wi-Fi default route, and
persistent services can be verified. It restarts `iwd` to reload the saved
profile, scans again after that restart, and reconnects Wi-Fi, so **run it from
the local console**, not
over SSH. Even a successful reconnect **cannot prove it will work after reboot**.
Check `networkctl status` and verify the
connection survives a reboot before provisioning KMOS. If the adapter or
firmware is missing, the helper stops before installing packages; temporary
networking or a compatible adapter will be necessary.

If provisioning already reached the Wi-Fi prompt and failed there, do **not**
reflash or rerun the entire provisioner just to fix the credentials. With
Ethernet connected if necessary, update your existing KMOS checkout and run
`./platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh` from it.
If the board remains online after a Wi-Fi association error, verify whether
Ethernet or Wi-Fi carries the connection before rebooting. If you cancel the
Wi-Fi helper during provisioning, you may explicitly choose to finish using a
working Ethernet address and route. This is **Ethernet-only**, not a claim that
Wi-Fi works. Without that choice, provisioning stops rather than reporting a
completed installation.

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
kernel, so back up the working card before confirming provisioning.

Headless provisioning installs available ARM CLI packages, asks before
skipping unavailable packages, installs the four Kappa Mono Nerd Font TTF
styles from the Kappa Type GitHub repository using `git`, and configures
terminal presets, hostname, timezone
(default `Europe/Zurich`), locale, administrator and optional users, swap
(default `4G`, `0` to omit), SSH (root login disabled), and DHCP Ethernet/DNS.
Wi-Fi is optional; an existing iwd profile is kept if you decline to reconfigure
it. Syncthing and removal of the default `alarm` account are optional. Wi-Fi
is the last configuration prompt; keep Ethernet connected for package downloads.
If you choose Wi-Fi at the end, it must pass the saved-profile reconnect test.
Cancelling Wi-Fi can finish the installation **Ethernet-only** with explicit
confirmation; this does not claim that Wi-Fi works. Provisioning does not
rewrite partitions, U-Boot, or extlinux boot files, but its initial system
update may update the board's kernel packages.

**KDE is not offered on Quartz64.** The earlier experimental stage failed on
physical hardware and has been disabled pending a separate diagnosis. Headless
Starship uses `starship-headless.toml`: a conservative ASCII-only default
including over SSH. **Kappa Mono is still installed as part of headless KMOS**;
the ASCII preset is a fallback choice, not a reason to omit the Nerd Font.
No extra host package or board `fontconfig` package is required: if fontconfig
is already present, its cache and font-family lookup are checked. The Linux
text console cannot render desktop fonts, and an SSH session is rendered by
the terminal on your *other computer*: select Kappa Mono there to display
Nerd glyphs in an icon-based prompt.

On a board provisioned by an older version, repair **only** the prompt without
reinstalling or repeating system updates. From the existing KMOS checkout:

```bash
git pull --ff-only
./platforms/archlinuxarm/boards/quartz64b/repair-headless-prompt.sh
```

Start a new SSH session to check the prompt. This command does not install KDE,
change networking, or rerun the headless provisioner.

To add Kappa Mono to an **existing** headless board without repeating the
system update or provisioning, run from the KMOS checkout:

```bash
./platforms/archlinuxarm/boards/quartz64b/install-kappa-mono-fonts.sh
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
  is not part of this provisioner. Source builds and NetworkManager migration
  are **not automated**.
