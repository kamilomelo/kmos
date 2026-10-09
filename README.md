# KMOS

KMOS is a shell-based toolkit for installing **Arch Linux x86_64** as a
headless system or a KDE desktop. The x86 installer is the tested path; other
platforms are separate, less mature workflows.

## Install Arch x86_64

**Back up your data.** Boot an Arch x86_64 ISO on the target machine. This
installer **formats the selected root partition and verified Arch EFI
partition**; it is not for converting an installed system or VPS. Inspect the
disk plan before typing `FORMAT`. If you use cfdisk, it can save partition
table edits *before* that confirmation.

With Ethernet, run on the live ISO:

```bash
git clone https://github.com/kamilomelo/kmos.git
cd kmos
./kmos-install.sh
```

Choose **headless (1)** or **KDE (2)** when prompted. AUR is optional. For KDE
without the extra application groups, run `./kmos-install.sh --profile noapps`
instead. The installer checks the Arch EFI target and refuses to format a
detected Windows EFI partition; you must still review every selected device.

The experimental `x86/next` branch instead offers a single optional Kamilo
productivity set, free-text repository extras and an explicit AUR choice in
the normal no-argument KDE install flow. That reorganized ISO path is not
field-tested yet;
use `main` for the tested release.

## Helpers

- **USB installer:** `./platforms/archlinux/tools/kmos-usb-flasher.sh` writes an
  Arch ISO to a removable drive. Review its selected device before confirming.
- **No Ethernet on the live ISO:** start from a local copy of this repository
  (for example, on USB) and run
  `./platforms/archlinux/tools/kmos-wifi-connect.sh` before the installer. It
  hands off the working Wi-Fi connection for first boot.
- **Headless Wi-Fi after an Ethernet install:** on the installed system, run
  `cd /opt/kmos/bin && ./kmos-headless-wifi.sh`. Choose Impala or text-based
  `iwctl`; iwd saves the connected network for later boots.

## Project structure

```text
kmos/
├── kmos-install.sh                 Platform entry point
├── platforms/
│   ├── archlinux/
│   │   ├── kmos-archlinux-install.sh
│   │   ├── desktop/kde/            KDE installation and defaults
│   │   ├── packages/               Package definitions and AUR list
│   │   ├── assets/                 Themes, wallpapers and profiles
│   │   └── tools/                  USB flasher and live-ISO Wi-Fi helper
│   ├── archlinuxarm/boards/        Board-specific workflows
│   ├── rockylinux/                Minimal post-install workflow
│   └── windows/                   Manual guide
├── docs/releases/                 Milestone notes
├── scripts/                       Shell validation
└── tests/                         Non-destructive tests
```

The tested shell-only x86 milestone and its limits are in the
[release notes](./docs/releases/x86-2026-10-08-shell-only.md). The old milestone
tag remains in history. For local validation, run `./scripts/check-shell.sh`
(requires ShellCheck 0.11.0). Licensed under the [MIT License](./LICENSE).

## Other platforms

- **Quartz64 Model B:** use its [board-specific guide](./platforms/archlinuxarm/boards/quartz64b/README.md), not the x86 installer.
- **Rocky Linux 10 Minimal:** after its own installation, use `./platforms/rockylinux/kmos-rockylinux-install.sh`; Wi-Fi helper: `./platforms/rockylinux/tools/kmos-rockylinux-wifi-connect.sh`.
- **Windows:** [manual guide](./platforms/windows/WINDOWS_SETUP.md); no automatic installer.
