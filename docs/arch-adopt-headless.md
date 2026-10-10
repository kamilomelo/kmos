# Adopt an installed Arch headless system (including a VPS)

This is **not** the Arch ISO installer and does not format disks. Use it only on
an **installed, headless Arch Linux x86_64** machine, not an Arch ISO or an
existing KDE desktop. This path is **experimental**: an initial VPS trial
installed packages with yay, but account cleanup has not been field-tested.
Have a provider console or VPS snapshot available.

```bash
git clone https://github.com/kamilomelo/kmos.git ~/kmos
cd ~/kmos
./platforms/archlinux/kmos-adopt-headless.sh --preflight
./platforms/archlinux/kmos-adopt-headless.sh
```

`--preflight` needs no root and changes nothing. The guided script requests
sudo when needed. Review the proposed packages and confirm before changes.
It uses `pacman -Syu --needed`: an Arch upgrade can upgrade existing packages,
run hooks, and require a later reboot even though KMOS does not deliberately
restart SSH, networking, or the VPS. Do not use a partial upgrade.

The package list includes the headless KMOS CLI set (including fastfetch), plus
the base tools needed for adoption. `openssh` is installed if missing; the
script generates missing SSH host keys, validates the existing SSH configuration,
enables `sshd` at boot, and starts it if inactive. It never restarts an already
active `sshd`. Wi-Fi tools are skipped when there is no wireless interface;
`nvtop` is included when an
NVIDIA PCI device and `nvidia-utils` are present. The script does not install
graphics drivers, change network-manager services, or alter SSH settings. It
shows the same numbered helper menu as the fresh headless x86 installer:
`1) paru` (default) or `2) yay`. VPS AUR is required rather than optional.
Paru is built from AUR **source**, not
`paru-bin`, to match the system's pacman/libalpm. This installs the official
`rust` package if missing; Rust remains installed for future paru rebuilds.
Compiling can take considerable VPS RAM, disk space and time. After showing the
PKGBUILD and building the package, it asks separately before
removing conflicting `paru-bin` and `paru-bin-debug` packages. If removal is
declined or the build fails, the existing packages remain. If installing the
already-built source package fails *after* approved removal, the broken binary
packages may be gone; rerun to rebuild. The script
automatically uses the current wheel admin to perform the non-root AUR build,
and **requires** `tododo-bin`. The helper is installed
system-wide, not just for the build user. Installing system-wide packages
requires sudo access; wheel membership alone may not be sufficient. AUR
packages are third-party software; review their build files at the prompt.
AUR failure leaves adoption incomplete and can be retried.

**Field result:** `paru-bin` failed to launch against a newer libalpm. The
source-built `paru` reached its final Rust compile on one VPS but `rustc`
received SIGKILL. That suggests a resource limit, possibly RAM; it is **not**
proof of OOM. Do not symlink libalpm versions. On a small VPS, choose `2) yay`
if paru cannot be built. Check memory, disk space, and the boot's kernel journal
before attributing a failure to OOM. A failed source build happens before any
approved removal of existing `paru-bin`
packages; the Rust package remains installed for future builds.

For read-only checks after SIGKILL on the same boot:

```bash
free -h
df -h /tmp
sudo journalctl -k -b --no-pager | grep -Ei 'out of memory|oom|killed process|memory cgroup' | tail -n 30
```

You can create regular users, choose wheel admin access, set passwords through
the system's `passwd` prompt, and paste individual SSH public keys. No password
is read or saved by KMOS. If there is no existing sudo-capable regular user,
create one before choosing the AUR builder. Verify a fresh SSH login and sudo
access for a new administrator. If the selected AUR build user lacks sudo
access, the script offers a validated, KMOS-owned rule for **all wheel users**;
declining stops AUR installation. **The script will not remove accounts in the
same run in which it created one.** Rerun from the replacement wheel account
with sudo to remove an old administrator, using the accounts-only command:

```bash
./platforms/archlinux/kmos-adopt-headless.sh --users-only
```

This mode does not rerun pacman, AUR builds, or appearance/SSH setup. Log out
of the old account first, then start a **new SSH session** as the replacement
admin and verify sudo before running it. The current login, last regular
administrator, logged-in users, and users with running processes are protected.
Removing an account and deleting its home each require explicit typed approval.
Home deletion is irreversible; use a provider snapshot if you need recovery.

KMOS installs Starship presets and a small managed Bash prompt integration.
It leaves existing personal dotfiles alone, skips conflicting global prompt
configurations and differing presets, and does not duplicate settings on rerun.
There is **no persistent configuration backup or automatic rollback**. The
script cleans up its temporary AUR build directory when the build returns, but
normal pacman caches remain managed by pacman. An interrupted run may leave
packages or newly created accounts in place; inspect the system and rerun.

Adoption has its own marker, separate from the ISO-installed headless marker.
It does **not** authorize the existing headless → KDE upgrader; reinstall from
the ISO if you want to replace an existing KDE desktop with KMOS KDE.
