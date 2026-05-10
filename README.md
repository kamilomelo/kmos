# kmos

kmos is a practical Arch Linux installation toolkit.
It provides:
- a USB flasher,
- a network bootstrap script for Arch ISO,
- a lean base installer (`nodesktop`),
- an optional KDE desktop layer with post-install customization.

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

The installer handles partitioning, base setup, bootloader, and then asks for desktop mode:
- `nodesktop` (headless/minimal), or
- KDE desktop path (calls `desktop/kmos-kde-install.sh` + `desktop/kmos-kde-post.sh`).

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
├── desktop/                       # KDE installer stages
│   ├── kmos-kde-install.sh        # KDE package install stage
│   └── kmos-kde-post.sh           # KDE post-install defaults and tweaks
├── tools/                         # Helper scripts
│   ├── kmos-wifi-connect.sh       # Wi-Fi bootstrap for Arch ISO/live session
│   └── kmos-usb-flasher.sh        # Bootable USB flasher
├── metapackages/                  # PKGBUILD bundle definitions (nodesktop, kde, shared sets)
├── assets/                        # Wallpaper, themes, Konsole/Kate presets, prune list
└── LICENSE
```

## License

This repository is released under the MIT License.
See [`LICENSE`](./LICENSE) for full terms.
