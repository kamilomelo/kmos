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

## Adopt an existing headless Arch system (VPS)

The **experimental adoption workflow on `main`** provisions an *installed,
headless Arch Linux x86_64* machine (VPS or local) without formatting it. It
does **not** convert existing KDE, add a graphical desktop to a VPS, or replace
the ISO installer. Never run
`./kmos-install.sh` on an installed system. Take a VPS snapshot, arrange
provider-console access, and keep your working SSH session open for the first
run.

```bash
git clone https://github.com/kamilomelo/kmos.git ~/kmos-adopt
cd ~/kmos-adopt
./platforms/archlinux/kmos-adopt-headless.sh --preflight
./platforms/archlinux/kmos-adopt-headless.sh
```

`--preflight` is read-only and needs no root. Review its package and account
inventory before the guided run; the script requests sudo when needed. If you
already have an older checkout, review local changes and update it to `main`
instead of cloning over it.

The guided run:

1. Runs `pacman -Syu --needed` for missing base tools (including `openssh`,
   `git`, `sudo`, and `nano`) and the headless CLI set: btop, fastfetch, opencode,
   ripgrep, Starship, Syncthing, tree, and zoxide. It includes iwd/Impala only
   when a wireless interface is present, and `nvtop` only when NVIDIA PCI
   hardware **and** `nvidia-utils` are detected. Arch upgrades and package
   hooks may affect running software; there is no automatic reboot.
2. Generates missing SSH *server host keys*, validates the existing sshd
   configuration, and enables sshd at boot. It starts sshd only if inactive;
   it does not restart an active SSH service or change network-manager or SSH
   settings.
3. Requires an AUR helper (`1) paru` by default, or `2) yay`) and `tododo-bin`.
   Paru is built from source using Rust; yay uses `yay-bin` when not already
   installed. The helper and `tododo-bin` are installed system-wide, but users
   need working sudo rights to install system packages. The current wheel
   administrator performs AUR builds as a non-root user. If that builder lacks
   sudo access, a rule for **all wheel users** is offered for separate approval.
4. Offers to create local users with Bash homes and passwords through the
   system `passwd` prompt. An SSH **public** key is optional for each new
   account; never paste a private key. It installs KMOS Starship presets and
   global interactive-Bash integration, skipping conflicting settings rather
   than replacing personal dotfiles. It never installs KDE here.

**Paru on small VPSs:** An earlier `paru-bin` could not load `libalpm.so.15`
against a newer pacman/libalpm. The current script builds `paru` from source
and asks before removing any conflicting `paru-bin` packages, *after* a
successful build. On one VPS the Rust compiler instead received **SIGKILL**
near the end of the build; an out-of-memory kill is plausible but **not yet
confirmed**. Building paru can need substantial RAM, disk space, and time;
select **yay** if your VPS cannot build it. Do not work around a libalpm
mismatch with a library symlink.
If the build fails, existing AUR helpers are preserved; earlier pacman, SSH,
or user changes are **not** automatically rolled back. See the
[adoption guide](./docs/arch-adopt-headless.md) for checks and recovery.

After a successful run, check `pacman -Q openssh tododo-bin`,
`systemctl is-enabled sshd.service`, `systemctl is-active sshd.service`, and
`paru --version` or `yay --version` (whichever helper you selected).

**Removing an old user:** First verify a *new* SSH login and sudo from a
different wheel administrator, then close the old user's sessions. From the
replacement administrator's own checkout, run:

```bash
./platforms/archlinux/kmos-adopt-headless.sh --users-only
```

This avoids repeating the package/AUR setup. The current login, last regular
administrator, logged-in users, and users with running processes cannot be
removed. Account removal and **permanent home deletion** require separate
explicit confirmations; an account created during a run cannot be removed in
that same run. There is no automatic configuration backup or rollback. VPS
adoption remains experimental; account cleanup has not yet been field-tested.
See the [v1.1.0 release notes](./docs/releases/v1.1.0.md) for field results
and remaining limits.

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
├── docs/                    Upgrade/adoption guides and release notes
├── scripts/                 Shell checks
└── tests/                   Non-destructive fixtures
```
