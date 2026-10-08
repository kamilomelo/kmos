# kmos

KMOS is a shell-based operating-system provisioning toolkit. Its x86_64 Arch
Linux ISO installer offers **headless** or **KDE** installation. The current x86
milestone is documented in [release notes](./docs/releases/x86-2026-10-08.md);
new installation experiments will live on `x86/next` rather than changing this
baseline. Arch Linux ARM (Quartz64 Model B) and Rocky Linux have separate,
less mature workflows; this x86 milestone does not release those platforms.

**On `x86/next` only:** KMOS's fresh KDE panel uses shell-generated KConfig;
the wallpaper uses a shell first-login action. This removes KMOS-authored
Plasma JavaScript. A fresh KDE login confirmed the panel and Dashboard, but
revealed that the transparent wallpaper needs a black background and a
proportional, uncropped image. The revised wallpaper action sets both through
Plasma's D-Bus API; **it still needs a fresh graphical test**. The older
milestone tag contains JavaScript and has not been replaced.

## Start here: Arch Linux x86_64

**Warning:** this is an ISO installer, not a converter for an existing Arch
system. It formats the chosen root partition and the verified Arch EFI
partition. Back up your data. It refuses an unverified or shared Windows EFI
partition, but you must still check the displayed disk and partition plan
before typing `FORMAT`. If you use cfdisk, its edits can be saved *before*
the final `FORMAT` confirmation. Do not run this installer on a VPS or an
already installed system.

1. Boot an Arch Linux x86_64 ISO. For an offline USB setup, use
   `./platforms/archlinux/tools/kmos-usb-flasher.sh` on a working machine.
2. Connect Ethernet, or use `./platforms/archlinux/tools/kmos-wifi-connect.sh`
   from a local copy of this repository on the ISO. The Wi-Fi helper saves a
   handoff for the installed system.
3. Clone the repository on the ISO and run:

   ```bash
   git clone https://github.com/kamilomelo/kmos.git
   cd kmos
   ./kmos-install.sh
   ```

4. Explicitly select **headless (1)** or **KDE (2)**. AUR is a separate,
   optional prompt. Review the disk, boot, and network plan before proceeding.

For KDE without the extra application groups, start with
`./kmos-install.sh --profile noapps` and then select KDE. For the full flow and
limitations, read [Arch Linux flow](#arch-linux-flow),
[Wi-Fi notes](#if-ethernet-is-not-available), and the
[x86 milestone notes](./docs/releases/x86-2026-10-08.md).

## Other platforms

- [Quartz64 Model B (Arch Linux ARM)](./platforms/archlinuxarm/boards/quartz64b/README.md): board-specific SD and provisioning workflow; **not** the x86 installer.
- [Rocky Linux](#rocky-linux): post-install configuration from Rocky minimal.
- [Windows](./platforms/windows/WINDOWS_SETUP.md): manual guide only.

## Arch Linux flow

The Arch installer requires a GPT EFI System Partition and a root partition on
the selected disk. The **selected Arch EFI partition is formatted** to remove
stale boot files. For an existing FAT EFI partition, the installer first
checks its contents read-only for the `krub` bootloader (or an empty ESP) and
requires a separate Windows EFI partition. If it cannot establish that
separation, it stops before `FORMAT`. A new,
unformatted EFI partition must be at least 512 MiB. The root partition is
also formatted. Both partitions must be unmounted; the final plan names the
exact devices and EFI action. Back up important data before installing.

The x86 Bash installer now collects the desktop (**explicitly choose 1 for
headless or 2 for KDE; Enter alone cannot select KDE**), AUR, account and
other configuration choices **before** the install plan review.
The krub menu always includes Arch Linux, Advanced options for Arch Linux and
UEFI Firmware Settings. If the installed GRUB provides `efibootnext` and a
unique firmware Boot Menu exists, one Boot Menu (EFI BootNext) entry is added;
otherwise this optional entry is skipped without stopping installation. The
only menu question is whether to also add Windows Boot Manager; No is the
default. Windows uses a verified EFI loader and a normal GRUB chainloader,
so the live ISO does not need `efibootnext`. The installer
disables the all-firmware-entry generator through its `GRUB_DISABLE_BOOTNEXT`
setting and makes the installed generator non-executable, without deleting
it or changing firmware entries. It writes at most one Boot Menu entry and,
if selected, one Windows entry. The installer never uses `os-prober` to
fill this menu. It checks the generated menu before replacing the previous
`grub.cfg`; an unexpected entry or evidence of unapproved GRUB generators
stops installation rather than silently using a different menu. This controls
GRUB's menu, **not the firmware's own BootNext/BootOrder entries**. On an
installed system,
`./kmos-install.sh inspect-krub` reports generated GRUB entries and firmware
entries read-only; it never removes firmware entries.
With existing partitions, the typed `FORMAT` confirmation is the format point;
the installer displays the exact disk, partitions and EFI action, then rechecks
the selected disk identity before formatting. If the plan is wrong, press
Ctrl+C and restart before typing `FORMAT`: there is no in-place plan editor.
If you choose to edit partitions, cfdisk opens immediately after that early
yes/no choice: cfdisk can write the partition table on exit. The installer
then selects and validates the resulting partitions and requires `FORMAT` before
touching their filesystems. Restarting after cfdisk cannot undo edits it has
already saved. Wi-Fi connection needed to fetch the checkout may also happen
separately before running this installer.
The selected, verified Arch EFI and root partitions are formatted. The
installer refuses to format a detected Windows EFI partition, and never
deletes firmware/NVRAM entries.
Before `pacstrap`, the x86 installer probes at most eight HTTPS mirrors from
the Arch ISO's mirror list (four seconds per probe) and places responsive
mirrors first. The original list remains as fallback, is backed up, and is
restored on the live ISO when the stage ends; the ranked list is saved in the
installed system. If probing fails, the existing list is left alone. Pacman's
normal download timeout is retained instead of disabling it. This ranks a
small sample by response time, not guaranteed package download throughput.
At completion, the x86 installer keeps its `############################ 100%`
progress display visible and counts down 10 seconds before rebooting. Press
any key to stay on the live ISO and reboot manually; without an interactive
terminal it skips automatic reboot.

**Field report (2026-10-02):** The fresh-clone x86 headless install and the KDE
install path both completed successfully in user testing. This does not verify
every firmware menu entry or Wi-Fi reconnection after reboot. Impala 0.9.0
works over SSH on the tested headless machine but fails on its local
`/dev/tty1` (`TERM=linux`) with a cursor-position timeout, including with
`--ascii`; native-console Impala remains an open issue.

Impala and iwd are listed in the shared `kmos-nodesktop` dependency manifest,
which the x86 installer loads for both headless and KDE choices and the
Quartz64 provisioner also reads. Installing Impala alone does not switch an
existing Wi-Fi backend. On x86 headless installs, a working iwd Wi-Fi handoff
is used at first boot;
wpa_supplicant is installed and enabled only as a last-resort fallback when
first-boot Wi-Fi was requested but no iwd profile was handed off. With no
Wi-Fi handoff, iwd is enabled for later Impala use and wired DHCP is enabled;
no Wi-Fi credentials are invented. KDE keeps its NetworkManager Wi-Fi
migration path.

When the x86 headless AUR option is accepted, KMOS installs the selected AUR
helper (`paru` or `yay`) and then `tododo-bin` as the normal user. Declining
the headless AUR option installs neither. The KDE AUR package list is separate.

For an x86 headless install started on Ethernet (without a Wi-Fi handoff), wired
DHCP and iwd are enabled on the installed system. After first boot, run
`cd /opt/kmos/bin && ./kmos-headless-wifi.sh` in an interactive terminal to connect
and save a persistent iwd Wi-Fi profile. Choose Impala or text-based `iwctl`
up front (the default); if Impala fails, the helper falls back to `iwctl`. It
shows sequential `iwctl` commands and asks you to confirm the connected network
appears in iwd's saved-network list. Ethernet can remain connected. The helper
does not replace existing profiles; KDE continues to use NetworkManager.

The KDE post-install stage no longer installs scripts that add, remove, unpin
or reorder Plasma panel widgets, or modify the default panel template. An
existing install can disable only the old KMOS-generated panel update scripts
with `./kmos-install.sh repair-panel`; it saves
each as a `.kmos-disabled` file and leaves other files alone. **This prevents
future changes but cannot infer or reconstruct an already-modified personal
panel layout.** Your panel configuration is in
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`; back it up before
rearranging widgets in Plasma or restoring a known-good copy.

The installer now stages a separate **first-run-only** KMOS panel template
based on the May 2026 layout: Dashboard at the left, KDE's task manager and
system tray, KMOS CPU/GPU, memory, disk and network monitors, three world
clocks, and Show Desktop. It does not run panel-update hooks against existing
users or change KDE's packaged default panel. The panel and its widgets were
verified on a fresh KDE login (2026-10-07). The KMOS colors did not apply in
that test: Plasma's color tool treats an already-selected `kmos` scheme as a
successful no-op. The revised one-time first-login action applies the palette
using the existing gray accent and checks the scheme hash before marking it
complete. It skips users who chose a different scheme and does not reapply
after later changes. **This revised color fix still needs a real KDE login
test.**

Fresh KMOS Konsole and Dolphin-terminal profiles explicitly select Kappa Mono;
the KDE post-install step verifies that fontconfig resolves the downloaded font.
The `kmos-fonts` package list includes `wqy-microhei` for CJK coverage. Arch's
`plasma-integration` package requires `ttf-hack`, so Hack may still be installed
as a KDE dependency, but KMOS does not select it as a terminal font. The
installer downloads only the Kappa families into its managed font directory.

### If Ethernet Is Not Available

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
