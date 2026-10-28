# KMOS

KMOS installs Arch Linux x86_64 headless or with KDE. Guided headless → KDE
upgrades and experimental adoption of installed headless Arch are also available
on `main`.

## Fresh Arch install

1. Back up your data. Boot an Arch x86_64 live ISO and connect to the internet;
   use the [Wi-Fi helper](#helpers) if needed.
2. On the live ISO, run:

   ```bash
   git clone https://github.com/kamilomelo/kmos.git
   cd kmos
   ./kmos-install.sh
   ```

3. Choose **headless** or **KDE**, optional packages, and an AUR helper. Review
   these choices in the final plan.
4. Check the target disk and EFI action before typing **`FORMAT`**. The root is
   formatted. Reusing an eligible EFI filesystem does not format it; forcing
   EFI formatting requires the separate exact **`EREASE`** approval and erases
   its boot files, including Windows. `cfdisk` can write partition changes
   **before** `FORMAT`. Reboot when installation finishes.

If KDE fails after the base system and bootloader are installed, **do not rerun
the fresh installer**. From the live ISO, keep the target mounted at `/mnt` and
its EFI at `/mnt/boot`, then run `./kmos-install.sh resume-kde` from an updated
checkout. See [KDE recovery](./docs/arch-headless-to-kde.md#resume-a-failed-iso-kde-stage).
**Never run the ISO installer on an installed system or VPS.**

## Upgrade a KMOS headless install to KDE

On an **installed KMOS headless Arch x86_64** system, run as a regular user:

```bash
git clone https://github.com/kamilomelo/kmos.git ~/kmos
cd ~/kmos
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh
```

The upgrade preserves personal settings unless you approve replacements. It
does not format disks or install AUR packages. A next-boot NetworkManager
handoff is offered separately; have local access if upgrading over Wi-Fi. See
the [upgrade and recovery guide](./docs/arch-headless-to-kde.md).

## Adopt an existing headless Arch system (VPS)

This **experimental** path is for installed headless Arch x86_64, not an ISO or
an existing KDE system. Keep a snapshot or provider console available.

```bash
git clone https://github.com/kamilomelo/kmos.git ~/kmos-adopt
cd ~/kmos-adopt
./platforms/archlinux/kmos-adopt-headless.sh --preflight
./platforms/archlinux/kmos-adopt-headless.sh
```

The preflight changes nothing. Guided adoption upgrades Arch, configures
headless tools and SSH, and offers guarded hostname and account changes. It
does not format disks or intentionally reconfigure networking; package upgrades
can still affect services. **Wheel membership alone does not grant sudo.** See
the [adoption guide](./docs/arch-adopt-headless.md).

To manage accounts later without reinstalling packages, use an authorized
admin account or provider root console:

```bash
./platforms/archlinux/kmos-adopt-headless.sh --users-only
```

Verify a replacement admin's new SSH login and sudo access before removing an
old account. Home deletion requires separate approval.

## Helpers

- **Installer USB:** `./platforms/archlinux/tools/kmos-usb-flasher.sh` asks you
  to confirm the destructive target.
- **Live-ISO Wi-Fi:** `./platforms/archlinux/tools/kmos-wifi-connect.sh`.
- **Installed headless Wi-Fi:** `cd /opt/kmos/bin && ./kmos-headless-wifi.sh`.

## Other platforms and work in progress

- [Quartz64 Model B](./platforms/archlinuxarm/boards/quartz64b/README.md):
  board-specific Arch Linux ARM workflow, not the x86 installer.
- [Rocky Linux 10 Minimal](./platforms/rockylinux/kmos-rockylinux-install.sh):
  separate post-install workflow.
- [Windows](./platforms/windows/WINDOWS_SETUP.md): manual guide.

The fresh x86_64 installer and KDE login were tested in isolated VMs. See the
[v1.1.1 release notes](./docs/releases/v1.1.1.md) for scope and limits.
For local shell checks, run `./scripts/check-shell.sh` with an already installed
ShellCheck 0.11.0. KMOS is licensed under the [MIT License](./LICENSE).

## Project structure

```text
kmos/
├── kmos-install.sh           Platform entry point
├── platforms/
│   ├── archlinux/            x86 installer, KDE, packages, assets, tools
│   ├── archlinuxarm/         Board-specific ARM workflows
│   ├── rockylinux/          Rocky Linux post-install workflow
│   └── windows/             Windows manual guide
├── docs/                    Upgrade/adoption guides and release notes
├── scripts/                 Shell checks
└── tests/                   Non-destructive fixtures
```
