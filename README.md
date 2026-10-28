# KMOS

KMOS installs Arch Linux x86_64 headless or with KDE. It also supports a
guided KMOS headless → KDE upgrade and experimental adoption of an installed,
headless Arch system. Other platforms have separate workflows below.

## Fresh Arch install

Boot an Arch x86_64 live ISO, connect to the internet, and run:

```bash
git clone https://github.com/kamilomelo/kmos.git
cd kmos
./kmos-install.sh
```

Review the disk and EFI plan before typing **`FORMAT`**: the selected root is
formatted. Formatting an existing EFI partition requires the separate exact
**`EREASE`** approval and erases its boot files, including Windows. `cfdisk`
can write partition changes **before** `FORMAT`. Choose headless or KDE and
review all package and AUR selections in the final plan.

**Never run this ISO installer on an installed system or VPS.** If KDE fails
after the base install, do not rerun it: with the original target still
mounted at `/mnt` and `/mnt/boot`, use `./kmos-install.sh resume-kde` from the
live ISO. See [KDE recovery](./docs/arch-headless-to-kde.md#resume-a-failed-iso-kde-stage).

## Existing Arch systems

- **KMOS headless → KDE:** on a KMOS-installed headless system, run
  `./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight`, then
  the same script without `--preflight`. It preserves personal settings unless
  you approve replacements. A network handoff is offered separately; plan for
  local access when upgrading over Wi-Fi. See the [upgrade guide](./docs/arch-headless-to-kde.md).
- **Installed headless Arch → KMOS headless (experimental):** run
  `./platforms/archlinux/kmos-adopt-headless.sh --preflight`, then the same
  script without `--preflight`. Have a snapshot or provider console available;
  Arch upgrades and account changes can affect a running VPS. It does not
  convert an existing KDE installation. See the [adoption guide](./docs/arch-adopt-headless.md).

Clone this repository on the installed system before running either workflow.
Neither workflow formats a disk.

## Helpers and other platforms

- [Arch live-ISO Wi-Fi](./platforms/archlinux/tools/kmos-wifi-connect.sh)
- [Installer USB flasher](./platforms/archlinux/tools/kmos-usb-flasher.sh)
  (asks you to confirm the destructive device)
- [Quartz64 Model B](./platforms/archlinuxarm/boards/quartz64b/README.md)
- [Rocky Linux 10 Minimal](./platforms/rockylinux/kmos-rockylinux-install.sh)
- [Windows manual guide](./platforms/windows/WINDOWS_SETUP.md)

The fresh x86_64 installer and KDE login were tested in isolated VMs. See the
[v1.1.1 release notes](./docs/releases/v1.1.1.md) for test scope and limits.
KMOS is licensed under the [MIT License](./LICENSE).
