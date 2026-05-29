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
mount /dev/<usb-partition> /mnt/usb
cd /mnt/usb/<kmos-folder>
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

Rocky Linux support starts from the `Rocky 10 minimal` post-install state.

Use a minimal disk layout:
- `/boot/efi`
- `/`

After the first boot, run the local `kmos` Rocky script. It will create the swapfile, handle Wi-Fi if needed, and stop after the first successful update until you reboot.

Current Rocky entry points:

```bash
./platforms/rockylinux/kmos-rockylinux-install.sh
./platforms/rockylinux/tools/kmos-rockylinux-wifi-connect.sh
```

The Rocky path covers the headless minimal workflow.

Current Rocky sequence:
1. network + Wi-Fi prep
2. swapfile
3. full update -> reboot -> rerun `kmos`
4. enable EPEL, then use CRB only if the CLI packages need it
5. install CLI tooling
6. stage Starship presets and shell hooks
7. detect NVIDIA hardware; if present, add the official NVIDIA repo and install `nvidia-open`
8. reboot -> rerun `kmos` -> verify with `nvidia-smi`
9. create additional users
10. continue with later stages as they are implemented

For later Rocky updates, keep the NVIDIA path safe by following the same rule:
- run the update
- reboot into the newest installed kernel
- only then continue using `kmos` or validating the NVIDIA stack

The Rocky script now blocks if a newer kernel is installed but not yet running, because that state is exactly where DKMS-backed NVIDIA rebuilds can drift or fail.

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
