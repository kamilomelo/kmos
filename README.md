# kmos

kmos is a practical Arch Linux installation toolkit.
It provides:
- a lean base installer (`nodesktop`),
- an optional KDE desktop layer with post-install customization,
- an optional AUR package layer for KDE,
- helper scripts for Wi-Fi bootstrap and USB flashing.

## How To Use It

### 1) Prepare Installation USB
Use `tools/kmos-usb-flasher.sh` on a working machine to write the Arch ISO to USB.

### 2) Boot Target Machine With Arch ISO
Boot from the flashed USB and open a shell.

### 3) If Ethernet Is Available
Connect cable, clone kmos, and run:

```bash
git clone https://github.com/kamilomelo/kmos.git
cd kmos
./kmos-archlinux-install.sh
```

The installer handles partitioning, base setup, bootloader, and then asks whether to install a desktop.

The root of the repository is intentionally small:
- `kmos-archlinux-install.sh` is the main entrypoint,
- `desktop/` contains desktop-specific install stages,
- `tools/` contains reusable helper scripts,
- `packages/` contains package definitions and AUR package lists.

### KDE Profiles
The KDE installer supports two profiles:

- `full`: default complete KDE desktop profile.
- `noapps`: KDE desktop core without the extra shared application groups.

The main installer uses the default `full` profile. To run the KDE stage manually with fewer applications:

```bash
./desktop/kde/kmos-kde-install.sh --target /mnt --profile noapps
```

### AUR Packages
For the `full` KDE profile, the main installer asks whether to install `paru` and the KDE AUR package set.

The editable list lives in:

```text
packages/aur/kde-packages.txt
```

If you use the `noapps` profile, `paru` and that AUR package list are skipped entirely.

Packages from that list are installed system-wide into the target system, not only for one user.
The full repository `assets/` tree is also mirrored into `/opt/kmos/assets/` during install.

### 4) If Ethernet Is NOT Available (Wi-Fi Path)
Use the repository from external media, then run Wi-Fi setup first:

```bash
# Example: mount external USB containing the kmos repo
mount /dev/<usb-partition> /mnt
cd /mnt/<kmos-folder>
./tools/kmos-wifi-connect.sh
```

After Wi-Fi is connected, continue with:

```bash
./kmos-archlinux-install.sh
```

## Project Structure

```text
.
├── kmos-archlinux-install.sh      # Main Arch installer (base + optional desktop stage)
├── assets/                        # Runtime assets mirrored into /opt/kmos/assets/
│   ├── color-schemes/             # KDE color schemes
│   ├── icons/                     # Custom launcher and desktop icons
│   ├── kate/                      # Kate themes
│   ├── konsole/                   # Konsole profiles and colors
│   ├── menus/                     # Menu-hide lists
│   ├── printers/                  # Printer drivers and PPDs
│   ├── prune/                     # Package prune lists
│   ├── starship-presets/          # Shell prompt presets
│   ├── wallpapers/                # Wallpapers
│   └── yakuake/                   # Yakuake skins
├── packages/                      # Package definitions and package lists
│   ├── aur/                       # AUR package lists
│   └── metapackages/              # PKGBUILD bundle definitions
├── desktop/                       # Desktop-specific installer logic
│   └── kde/
│       ├── kmos-kde-install.sh    # KDE package install stage
│       └── kmos-kde-post.sh       # KDE post-install defaults and tweaks
├── tools/                         # Helper scripts
│   ├── kmos-wifi-connect.sh       # Wi-Fi bootstrap for Arch ISO/live session
│   └── kmos-usb-flasher.sh        # Bootable USB flasher
└── LICENSE
```

## License

This repository is released under the MIT License.
See [`LICENSE`](./LICENSE) for full terms.
