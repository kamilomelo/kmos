# kmos

kmos is a practical operating-system provisioning toolkit.

Today the implemented platform is:
- `archlinux`
- `windows`

The project is now structured so additional platforms can be added later, such as:
- `rocky`

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

### Windows Flow

On a fresh Windows 11 install, open an elevated PowerShell session and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\platforms\windows\kmos-windows-install.ps1
```

This script is intended to be run after Windows is already installed and online. It handles:
- PowerShell preview bootstrap
- optional disk shrink for Linux coexistence
- Windows app installs
- OpenSSH client/server setup
- shared kmos assets, wallpaper, fonts, and Starship defaults
- optional local administrator creation
- final Chris Titus utility launch

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
│   └── windows/
│       ├── assets/                         # Windows-specific runtime assets
│       ├── kmos-windows-install.ps1        # Main Windows post-install provisioner
│       └── Apply-KmosWindowsUser.ps1       # Per-user Windows defaults hook
├── LICENSE
└── README.md
```

## Notes

- The Arch platform still uses the established internal `kmos` package and asset names.
- Platform-specific assets are mirrored into `/opt/kmos/assets/` during installation.
- Windows stages its reusable assets from `platforms/windows/assets/` into `C:\ProgramData\kmos\assets`.
- Future Rocky Linux support should live beside Arch and Windows under `platforms/`.

## License

This repository is released under the MIT License.
See [`LICENSE`](./LICENSE) for full terms.
