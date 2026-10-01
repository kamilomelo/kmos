# kmos

kmos is a practical operating-system provisioning toolkit.

The primary implemented platform is Arch Linux x86_64. Rocky Linux has a
post-install workflow; Arch Linux ARM has a Quartz64 Model B workflow. Other
ARM boards remain future work. Windows has a manual guide under
`platforms/windows/`. The main focus of this repository is the Linux path.

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

The Arch installer requires a GPT EFI System Partition and a root partition on
the selected disk. An existing FAT EFI partition can be **reused without
formatting** if it has at least 512 MiB free; this preserves existing boot
files but adds Arch and GRUB files to it. Alternatively, choose to format an
EFI partition of at least 512 MiB (which erases its existing contents).
The root partition is always formatted. Both partitions must be unmounted,
and the final confirmation names the exact devices and EFI action. Back up
important data before installing; reusing an EFI partition does not make the
root-formatting step reversible.

The x86 Bash installer now collects the desktop (**explicitly choose 1 for
headless or 2 for KDE; Enter alone cannot select KDE**), AUR, account and
other configuration choices **before** the install plan review.
The early krub choice also requires an explicit selection: **1** generates a
KMOS-only menu (no other-OS probing, recovery entries or firmware-settings
entry), while **2** permits other-OS detection. Enter alone does not choose
either option. The generated menu is checked before the installer reboots;
unknown entries in KMOS-only mode stop the installation for review instead of
being silently accepted. This controls GRUB's menu, **not the firmware's own
BootNext/BootOrder entries**. On an installed system,
`./kmos-install.sh inspect-krub` reports generated GRUB entries and firmware
entries read-only; it never removes firmware entries.
With existing partitions, the typed `FORMAT ...` confirmation is the GO point;
the installer rechecks the selected disk identity before formatting and runs
the selected installation without a later desktop-choice prompt. If you choose
to edit partitions, it first asks for `GO <disk>` **before opening cfdisk**:
cfdisk can write the partition table on exit. It then selects and validates
the resulting partitions and requires a separate `FORMAT ...` confirmation
before touching their filesystems. No partition edits can be rolled back by
the installer once cfdisk writes them. Wi-Fi connection needed to fetch the
checkout may also happen separately before running this installer.

The KDE post-install stage no longer installs scripts that add, remove, unpin
or reorder Plasma panel widgets, or modify the default panel template. An
existing install can disable only the old KMOS-generated panel update scripts
with `./kmos-install.sh repair-panel`; it saves
each as a `.kmos-disabled` file and leaves other files alone. **This prevents
future changes but cannot infer or reconstruct an already-modified personal
panel layout.** Your panel configuration is in
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`; back it up before
rearranging widgets in Plasma or restoring a known-good copy.

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

## Arch Linux ARM

ARM boards require board-specific SD preparation, followed by provisioning on
the booted board. The x86_64 Arch installer is **not** usable on ARM; the root
dispatcher refuses `archarm` rather than sending it to the x86_64 UEFI flow.
Arch Linux ARM has separate AArch64 and ARMv7 package repositories, so not all
x86_64 packages or KDE features can be assumed available. Currently the
[Quartz64 Model B workflow](./platforms/archlinuxarm/boards/quartz64b/README.md)
implements SD preparation (including a manual first-boot Wi-Fi helper), headless
post-boot provisioning from a pinned GitHub checkout, and an experimental KDE
offer gated by ARM package and graphics checks. Other boards remain future work.

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
1. hostname + network + Wi-Fi prep
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
├── .github/workflows/shell-validation.yml # Non-destructive CI
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
│   ├── archlinuxarm/
│   │   ├── README.md
│   │   └── boards/quartz64b/              # Quartz64 SD, manual Wi-Fi, headless setup
│   ├── rockylinux/
│   │   ├── kmos-rockylinux-install.sh     # Rocky minimal post-install entry point
│   │   └── tools/
│   │       └── kmos-rockylinux-wifi-connect.sh # Rocky Wi-Fi bootstrap helper
│   └── windows/
│       ├── WINDOWS_SETUP.md                # Manual Windows setup workflow
│       └── assets/                         # Windows-specific runtime assets
├── scripts/                                # Local shell validation and baseline
├── tests/                                  # Mocked, non-destructive safety tests
├── LICENSE
└── README.md
```

## Notes

- The Arch platform still uses the established internal `kmos` package and asset names.
- The Rocky platform currently starts from a manually installed Rocky Minimal base.
- Platform-specific assets are mirrored into `/opt/kmos/assets/` during installation.
- Windows reuses assets directly from `platforms/windows/assets/` through the Markdown guide.

## Non-destructive validation

Install ShellCheck 0.11.0, then run `bash scripts/check-shell.sh`. The check runs
`bash -n` and ShellCheck on Arch, Arch Linux ARM, and Rocky Bash entry points and the
validation scripts, then runs mocked partition-safety tests. It does not run
the installers, write to disks, or inspect other untracked work. CI runs the same
check on pushes and pull requests. Existing diagnostics are recorded in
`scripts/shellcheck-baseline.txt`; new diagnostics fail the check. When fixing
an existing diagnostic, remove its matching baseline entry as part of the fix.

## Windows

Windows is intentionally kept as a manual or semi-manual path.

If you need it, use:

- [platforms/windows/WINDOWS_SETUP.md](./platforms/windows/WINDOWS_SETUP.md)

## License

This repository is released under the MIT License.
See [`LICENSE`](./LICENSE) for full terms.
