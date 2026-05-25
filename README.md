# kmos

kmos is a practical operating-system provisioning toolkit.

Today the primary implemented platform is:
- `archlinux`

The project is structured so additional platforms can be added later, especially:
- `rocky`

There is also a minimal Windows guide under `platforms/windows/`, but the main focus of this repository is the Linux path.

## How To Use It

### Main Entry Point

Use the root dispatcher:

```bash
./kmos-install.sh
```

For the current implementation, that dispatcher detects Arch Linux and runs:

```bash
./platforms/archlinux/kmos-archlinux-install.sh
```

The Arch installer also supports:

```bash
./kmos-install.sh --profile noapps
```

### Arch Linux Flow

#### 1) Prepare Installation USB

Use:

```bash
./platforms/archlinux/tools/kmos-usb-flasher.sh
```

on a working machine to write the Arch ISO to USB.

#### 2) Boot Target Machine With Arch ISO

Boot from the flashed USB and open a shell.

#### 3) If Ethernet Is Available

Clone the repo and run:

```bash
git clone https://github.com/kamilomelo/kmos.git
cd kmos
./kmos-install.sh
```

The dispatcher will route to the Arch installer.

#### 4) If Ethernet Is NOT Available

Use the repository from external media, then run Wi-Fi setup first:

```bash
mount /dev/<usb-partition> /mnt
cd /mnt/<kmos-folder>
./platforms/archlinux/tools/kmos-wifi-connect.sh
```

After Wi-Fi is connected, continue with:

```bash
./kmos-install.sh
```

## Arch Linux Profiles

The current Arch/KDE implementation supports:

- `full`: default complete KDE desktop profile
- `noapps`: KDE desktop core without the extra shared application groups

Use:

```bash
./kmos-install.sh --profile noapps
```

## Rocky Linux

Rocky Linux support now starts from the `Rocky 10 minimal` post-install state.

The current Rocky workflow is intentionally conservative:
- install Rocky Minimal with the official installer first
- use `/boot/efi`, `/boot`, and `/` only
- do not create a separate `/home` partition
- do not create a swap partition
- boot the installed system
- run the local `kmos` Rocky script
- let the Rocky script create a swapfile instead
- if ethernet is not available, the Rocky script starts by bringing up Wi-Fi
- the first successful Rocky update run stops on purpose and requires a reboot before NVIDIA or tooling work continues

Current Rocky entry points:

```bash
./platforms/rockylinux/kmos-rockylinux-install.sh
./platforms/rockylinux/tools/kmos-rockylinux-wifi-connect.sh
```

This is an initial scaffold. The next Rocky stage is KDE installation and post-install desktop configuration on top of the minimal base.

Current Rocky sequence:
1. network
2. prepare Wi-Fi support while ethernet is available
3. swapfile
4. full update
5. reboot
6. rerun `kmos`
7. enable CRB and EPEL
8. install CLI tooling
9. stage Starship presets and shell hooks
10. create additional users
11. continue with NVIDIA and KDE stages as they are implemented

## Current Project Structure

```text
.
├── kmos-install.sh                         # Root platform dispatcher
├── platforms/
│   ├── archlinux/
│   │   ├── kmos-archlinux-install.sh       # Main Arch installer
│   │   ├── assets/                         # Arch-specific runtime assets
│   │   ├── desktop/
│   │   │   └── kde/
│   │   │       ├── kmos-kde-install.sh     # KDE package install stage
│   │   │       └── kmos-kde-post.sh        # KDE post-install defaults and tweaks
│   │   ├── packages/                       # Arch package definitions and AUR lists
│   │   │   ├── aur/
│   │   │   └── metapackages/
│   │   └── tools/                          # Arch helper scripts
│   │       ├── kmos-wifi-connect.sh
│   │       └── kmos-usb-flasher.sh
│   ├── rockylinux/
│   │   ├── kmos-rockylinux-install.sh     # Rocky minimal post-install entry point
│   │   └── tools/
│   │       └── kmos-rockylinux-wifi-connect.sh # Rocky Wi-Fi bootstrap helper
│   └── windows/
│       ├── WINDOWS_SETUP.md                # Manual Windows setup workflow
│       └── assets/                         # Windows-specific runtime assets
├── LICENSE
└── README.md
```

## Notes

- The Arch platform still uses the established internal `kmos` package and asset names.
- The Rocky platform currently starts from a manually installed Rocky Minimal base.
- Platform-specific assets are mirrored into `/opt/kmos/assets/` during installation.
- Windows reuses assets directly from `platforms/windows/assets/` through the Markdown guide.
- Future Rocky Linux support should live beside Arch and Windows under `platforms/`.

## Windows

Windows is intentionally kept as a manual or semi-manual path.

If you need it, use:

- [platforms/windows/WINDOWS_SETUP.md](./platforms/windows/WINDOWS_SETUP.md)

## License

This repository is released under the MIT License.
See [`LICENSE`](./LICENSE) for full terms.
