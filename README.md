# KMOS

KMOS installs Arch Linux x86_64 as a headless system or a KDE desktop. Fresh
KDE installs and headless → KDE upgrades are available on `main`.

## Fresh Arch install

1. Back up your data and boot an Arch x86_64 ISO on the target machine. Connect
   Ethernet, or use the [live-ISO Wi-Fi helper](#helpers) from a local copy of
   this repository.
2. On the live ISO, get the checkout and start the installer:

   ```bash
   git clone https://github.com/kamilomelo/kmos.git
   cd kmos
   ./kmos-install.sh
   ```

3. Choose **headless** or **KDE**, then review the optional package and AUR
   choices. The installer shows your selections before disk approval.
4. Review the disk and EFI plan before typing **`FORMAT`**. The installer
   **formats the selected root and Arch EFI partitions**. Partition edits made
   in `cfdisk` may take effect even before `FORMAT`. Reboot when installation
   finishes.

**Never run the ISO installer on an installed system or VPS.** It is not an
existing-Arch conversion tool. See the
[package choices and safety details](./docs/arch-headless-to-kde.md).

## Upgrade a KMOS headless install to KDE

Only use this path on an **installed KMOS headless Arch x86_64** machine, not
an arbitrary Arch installation. With internet access, run as a regular user:

```bash
git clone https://github.com/kamilomelo/kmos.git ~/kmos
cd ~/kmos
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh
```

The single guided run installs KDE and applies visual defaults to existing
local regular users with homes under `/home`; new users inherit defaults too.
Existing personal panels stay intact; differing files require approval and
are backed up. The live upgrade does **not** install AUR packages or format disks.

It separately offers a **next-boot** NetworkManager handoff. Current SSH and
networking stay active until you reboot. If staging over Wi-Fi, have a local
screen and keyboard ready: after reboot, reconnect Wi-Fi in KDE before SSH
returns. Existing iwd Wi-Fi passwords are not imported. If staging is declined
or fails its checks, iwd/dhcpcd remain in charge. See the
[upgrade and recovery guide](./docs/arch-headless-to-kde.md). Do not rerun the
upgrade on an already-upgraded KDE system.

## Adopt an existing headless Arch system

For an installed Arch x86_64 headless machine (including a VPS), the
**experimental, non-formatting** adoption script is separate from
`./kmos-install.sh`:

```bash
./platforms/archlinux/kmos-adopt-headless.sh --preflight
./platforms/archlinux/kmos-adopt-headless.sh
```

It reviews the KMOS CLI packages, enables OpenSSH, requires an AUR helper and
`tododo-bin`, and offers user creation/removal and terminal defaults. Existing
SSH settings and network configuration are preserved. Prepare provider-console
access and review the [adoption safety guide](./docs/arch-adopt-headless.md)
before use.
Existing KDE systems are not supported by this path. The initial VPS trial
confirmed package installation with yay; account cleanup still needs a field
test.

After verifying a replacement admin's SSH login, use
`./platforms/archlinux/kmos-adopt-headless.sh --users-only` to manage accounts
without rerunning the package installation. The current login cannot remove
itself.

## Helpers

- **Prepare an installer USB:** `./platforms/archlinux/tools/kmos-usb-flasher.sh`
  detects eligible media and confirms the destructive target.
- **Wi-Fi on the live ISO:** from a local checkout, run
  `./platforms/archlinux/tools/kmos-wifi-connect.sh` before installing.
- **Wi-Fi on a headless install:** run
  `cd /opt/kmos/bin && ./kmos-headless-wifi.sh` to set up iwd with Impala or
  `iwctl`.

## Other platforms and work in progress

- [Quartz64 Model B](./platforms/archlinuxarm/boards/quartz64b/README.md):
  board-specific Arch Linux ARM workflow; do not use the x86 installer.
- [Rocky Linux 10 Minimal](./platforms/rockylinux/kmos-rockylinux-install.sh):
  separate post-install workflow, not an Arch install.
- [Windows](./platforms/windows/WINDOWS_SETUP.md): manual guide; no automated
  installer.
- Wi-Fi-only KDE handoff recovery still needs a hardware failure test. See the
  [v1.0.0 release notes](./docs/releases/v1.0.0.md).

Run `./scripts/check-shell.sh` for local shell checks (requires an already
installed ShellCheck 0.11.0). KMOS is licensed under the [MIT License](./LICENSE).

## Project structure

```text
kmos/
├── kmos-install.sh           Platform entry point
├── platforms/
│   ├── archlinux/            x86 installer, KDE, packages, assets, tools
│   ├── archlinuxarm/         Board-specific ARM workflows
│   ├── rockylinux/          Rocky Linux post-install workflow
│   └── windows/             Windows manual guide
├── docs/                    Upgrade guide and release notes
├── scripts/                 Shell checks
└── tests/                   Non-destructive fixtures
```
