# KMOS

KMOS installs Arch Linux x86_64 as a headless system or a KDE desktop. The
current KDE and headless → KDE workflows live on **`x86/next`**; `main` remains
the previous tested release until this work is merged.

## Fresh Arch install

1. Back up your data and boot an Arch x86_64 ISO on the target machine. Connect
   Ethernet, or use the [live-ISO Wi-Fi helper](#helpers) from a local copy of
   this repository.
2. On the live ISO, get the experimental checkout and start the installer:

   ```bash
   git clone --branch x86/next https://github.com/kamilomelo/kmos.git
   cd kmos
   ./kmos-install.sh
   ```

3. Choose **headless** or **KDE**. The guided KDE install includes Plasma,
   Spectacle, Kdenlive, and Firefox Developer Edition; Kamilo productivity
   defaults to Yes. You can add repository packages. AUR is optional (Yes by
   default): `paru` is the default helper, `tododo-bin` is included if you
   approve AUR, and other AUR packages require explicit selection.
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
git clone --branch x86/next https://github.com/kamilomelo/kmos.git ~/kmos-next
cd ~/kmos-next
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

## Helpers

- **Prepare an installer USB:** `./platforms/archlinux/tools/kmos-usb-flasher.sh`
  detects eligible media and confirms the destructive target.
- **Wi-Fi on the live ISO:** from a local checkout, run
  `./platforms/archlinux/tools/kmos-wifi-connect.sh` before installing.
- **Wi-Fi on a headless install:** run
  `cd /opt/kmos/bin && ./kmos-headless-wifi.sh` to set up iwd with Impala or
  `iwctl`.
- **Inspect an existing KDE handoff:**
  `./platforms/archlinux/tools/kmos-network-migration.sh --plan` is read-only.
  Follow the [recovery guide](./docs/arch-headless-to-kde.md) before changing
  network services.

## Other platforms and work in progress

- [Quartz64 Model B](./platforms/archlinuxarm/boards/quartz64b/README.md):
  board-specific Arch Linux ARM workflow; do not use the x86 installer.
- [Rocky Linux 10 Minimal](./platforms/rockylinux/kmos-rockylinux-install.sh):
  separate post-install workflow, not an Arch install.
- [Windows](./platforms/windows/WINDOWS_SETUP.md): manual guide; no automated
  installer.
- Adopting **existing Arch installations or VPS servers** is not supported yet.
  Wi-Fi-only handoff recovery still needs a hardware failure test. No
  `v1.0.0` release has been published yet.

Run `./scripts/check-shell.sh` for local shell checks (requires an already
installed ShellCheck 0.11.0). KMOS is licensed under the [MIT License](./LICENSE).

## Project structure

```text
kmos-install.sh              Arch/Rocky entry point
platforms/archlinux/         x86 installer, KDE, package manifests, assets, helpers
platforms/archlinuxarm/      Board-specific ARM workflows
platforms/rockylinux/       Rocky Linux post-install workflow
platforms/windows/          Windows manual guide
docs/                        Upgrade guide and milestone notes
scripts/                     Shell checks
tests/                       Non-destructive fixtures
```
