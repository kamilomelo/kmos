#!/usr/bin/env bash
# Adopt an installed Arch x86_64 headless host without replaying the ISO installer.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/packages/metapackages/nodesktop/PKGBUILD"
PRESETS="$SCRIPT_DIR/assets/starship-presets"
MARKER=/usr/share/kmos/adopted-headless
BASHRC=/etc/bash.bashrc
STARSHIP_PROFILE=/etc/profile.d/10-kmos-starship.sh
SHARE_KMOS=/usr/share/kmos
SUDO_RULE_DIR=/etc/sudoers.d
declare -a PACKAGES=() USERS_CREATED=()

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/kmos-adopt-headless.sh [--preflight|--users-only|--help]

Guided adoption of an INSTALLED Arch x86_64 headless machine (including a VPS).
Reviews packages, accounts, and terminal appearance before changes. Builds
paru (default) from source with Rust, or installs yay, and requires tododo-bin.
Enables OpenSSH without rewriting its configuration or restarting an active
sshd. Optionally changes the hostname with confirmation, without changing
network services. Never formats disks or converts an existing KDE desktop.
Account deletion is final.
--preflight reports eligibility without root or changes; --help needs no root.
--users-only manages accounts without rerunning pacman, AUR, or appearance setup.
An authorized admin can also grant sudo to existing wheel users in --users-only.
Have a VPS snapshot or provider console available before a package upgrade.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }
note() { printf '%s\n' "$*" >&2; }
ask() {
  local reply
  while true; do
    read -r -p "$1 [y/N]: " reply </dev/tty || return 1
    case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; [nN]|[nN][oO]|'') return 1 ;; *) note 'Please answer yes or no.' ;; esac
  done
}
input() {
  local answer
  read -r -p "$1" answer </dev/tty || return 1
  printf '%s\n' "$answer"
}
installed() { pacman -Qq "$1" >/dev/null 2>&1; }
is_admin() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -Fxq wheel; }
regular_user() {
  local name=$1 entry uid home shell
  awk -F: -v n="$name" '$1 == n {found=1} END {exit !found}' /etc/passwd || return 1
  entry=$(getent passwd "$name") || return 1
  IFS=: read -r _ _ uid _ _ home shell <<< "$entry"
  [[ "$uid" =~ ^[0-9]+$ ]] && ((uid >= 1000 && uid < 65534)) &&
    [[ "$home" == /home/* && "$home" != /home/*/* ]] &&
    [[ "$shell" != */nologin && "$shell" != */false ]]
}
regular_users() {
  local name entry
  while IFS=: read -r name _; do
    regular_user "$name" || continue
    entry=$(getent passwd "$name") || continue
    printf '%s\n' "$entry"
  done </etc/passwd
}
has_nvidia() {
  local vendor
  installed nvidia-utils || return 1
  for vendor in /sys/bus/pci/devices/*/vendor; do
    [[ -r "$vendor" ]] || continue
    [[ $(<"$vendor") == 0x10de ]] && return 0
  done
  return 1
}
eligible() {
  local id
  [[ -r /etc/os-release ]] || { fail 'Cannot identify the OS.'; return 1; }
  # shellcheck disable=SC1091
  id=$(. /etc/os-release; printf '%s' "${ID:-}")
  [[ "$id" == arch && $(uname -m) == x86_64 ]] || { fail 'Only Arch Linux x86_64 is supported.'; return 1; }
  [[ -d /var/lib/pacman/local && -e /etc/machine-id ]] || { fail 'An installed Arch system is required.'; return 1; }
  [[ ! -e /run/archiso && ! -e /etc/arch-release.iso ]] || { fail 'Do not run on the Arch live ISO.'; return 1; }
  for id in plasma-desktop sddm; do
    installed "$id" && { fail 'Existing KDE/SDDM systems are out of scope.'; return 1; }
  done
  [[ ! -e /usr/share/kmos/kde-profile ]] || { fail 'Existing KMOS KDE is out of scope.'; return 1; }
  [[ ! -L "$MARKER" && ( ! -e "$MARKER" || -f "$MARKER" ) ]] || {
    fail 'Adoption marker is not a regular file.'; return 1;
  }
  [[ -r "$MANIFEST" && -d "$PRESETS" ]] || { fail 'Use a complete local KMOS checkout.'; return 1; }
}
packages_for_host() {
  local pkg list
  PACKAGES=(base-devel git sudo openssh nano)
  # Local, tracked manifest only; never source remote or host-provided manifests.
  # shellcheck disable=SC1090,SC2154 # Local checked-out PKGBUILD declares depends.
  list=$(source "$MANIFEST" && printf '%s\n' "${depends[@]}") || { fail 'Could not load headless package manifest.'; return 1; }
  [[ -n "$list" ]] || { fail 'Headless package manifest is empty.'; return 1; }
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$pkg" =~ ^[a-z0-9@._+-]+$ ]] || { fail "Invalid manifest package: $pkg"; return 1; }
    if [[ "$pkg" == iwd || "$pkg" == impala ]]; then
      # Wi-Fi tools are unnecessary on most VPSs and are never enabled here.
      compgen -G '/sys/class/net/*/wireless' >/dev/null || continue
    fi
    PACKAGES+=("$pkg")
  done <<< "$list"
  has_nvidia && PACKAGES+=(nvtop)
  return 0
}
preflight() {
  local pkg entry name _ home styled=no renderer="$SCRIPT_DIR/tools/kartouche.sh"
  eligible || return 1
  packages_for_host || return 1
  # The optional renderer affects only presentation, not adoption eligibility.
  if [[ -f "$renderer" && -r "$renderer" && ! -L "$renderer" ]]; then
    # shellcheck disable=SC1090,SC1091
    if source "$renderer"; then
      KT_NAME='kmos Adopt Headless'
      KT_DESCRIPTION='Arch Linux adoption preview; no changes made.'
      KT_ACCENT='38;5;244'
      [[ ${TERM:-} == linux ]] && KT_ACCENT=37
      kt_banner 'Read-only preflight'
      styled=yes
    fi
  fi
  printf 'Arch headless x86_64: eligible\nPackages (pacman upgrade + --needed):\n'
  printf 'Current hostname: %s (optional change in guided mode)\n' "$(hostname)"
  for pkg in "${PACKAGES[@]}"; do
    if installed "$pkg"; then printf '  %-18s installed\n' "$pkg"; else printf '  %-18s to install\n' "$pkg"; fi
  done
  printf 'Accounts (regular users under /home):\n'
  while IFS= read -r entry; do
    IFS=: read -r name _ _ _ _ home _ <<< "$entry"
    if is_admin "$name"; then printf '  %s (wheel, %s)\n' "$name" "$home"
    else printf '  %s (%s)\n' "$name" "$home"; fi
  done < <(regular_users)
  printf 'Current SSH/network services: '
  systemctl --no-pager --plain is-active sshd.service NetworkManager.service systemd-networkd.service iwd.service dhcpcd.service 2>/dev/null | paste -sd ' ' - || :
  printf 'sshd at boot: '
  systemctl is-enabled sshd.service 2>/dev/null || printf 'not enabled / unavailable\n'
  printf 'AUR: paru from source (requires Rust) or yay; tododo-bin required.\n'
  for pkg in paru yay; do
    if helper_works "$pkg"; then printf '  %-18s working\n' "$pkg"
    elif command -v "$pkg" >/dev/null 2>&1; then printf '  %-18s installed but cannot start\n' "$pkg"
    else printf '  %-18s absent\n' "$pkg"; fi
  done
  printf 'Appearance: KMOS Starship presets and managed Bash integration; conflicting configuration is skipped.\n'
  printf 'No changes made. Guided mode offers an optional hostname change and enables/starts sshd without changing its config; network services, bootloader and disk settings stay intact.\n'
  if [[ "$styled" == yes ]]; then
    kt_summary rail 'Installed Arch eligible' ok 'Packages and accounts inventoried' ok 'Host settings unchanged' ok
  fi
}
require_root() {
  ((EUID == 0)) && return 0
  command -v sudo >/dev/null 2>&1 || { fail 'sudo is required for adoption.'; return 1; }
  sudo -v || { fail 'This login has no working sudo access. Use another sudo administrator or the provider root console to run --users-only and repair this wheel user; wheel membership alone is not enough.'; return 1; }
  exec sudo -- "$SCRIPT_DIR/kmos-adopt-headless.sh" "$@"
}
valid_name() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [[ "$1" != root ]]; }
valid_hostname() {
  local name=$1 label
  local -a labels
  # Linux limits the active hostname to 64 bytes (ASCII names here).
  ((${#name} > 0 && ${#name} <= 64)) && [[ "$name" != .* && "$name" != *. && "$name" != *..* ]] || return 1
  IFS=. read -r -a labels <<< "$name"
  for label in "${labels[@]}"; do
    ((${#label} <= 63)) && [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}
offer_hostname() {
  local current name
  current=$(hostname) || { fail 'Cannot read current hostname.'; return 1; }
  ask "Change hostname (currently $current)?" || return 0
  while true; do
    name=$(input 'New hostname (lowercase DNS name; blank to cancel): ') || return 1
    [[ -n "$name" ]] || { note 'Hostname unchanged.'; return 0; }
    valid_hostname "$name" && break
    note 'Invalid hostname: use up to 64 lowercase letters, digits, dots and internal hyphens.'
  done
  [[ "$name" != "$current" ]] || { note 'Hostname unchanged.'; return 0; }
  note "This changes the system hostname from $current to $name. It does not edit /etc/hosts or network services."
  ask "Confirm hostname $name?" || { note 'Hostname unchanged.'; return 0; }
  hostnamectl set-hostname "$name" || { fail 'Could not set the hostname; check hostnamectl and host permissions.'; return 1; }
  note "Hostname set to $name. Check /etc/hosts or provider DNS separately if they refer to the old name."
}

add_key() (
  local name=$1 home key file tmp
  home=$(getent passwd "$name" | cut -d: -f6)
  [[ "$home" == "/home/$name" && ! -L "$home" ]] || { fail 'Unexpected home; refusing to write SSH keys.'; return 1; }
  key=$(input "Paste ONE SSH public key for $name (blank to skip): ") || return 1
  [[ -n "$key" ]] || return 0
  [[ "$key" != *$'\n'* && "$key" != *$'\r'* ]] || { fail 'Invalid SSH public key.'; return 1; }
  tmp=$(mktemp) || return 1
  trap 'rm -f -- "$tmp"' EXIT
  printf '%s\n' "$key" > "$tmp"
  if ! ssh-keygen -lf "$tmp" >/dev/null 2>&1; then fail 'Invalid SSH public key.'; return 1; fi
  file="$home/.ssh/authorized_keys"
  [[ ! -L "$home/.ssh" && ! -L "$file" && ( ! -e "$file" || -f "$file" ) ]] || {
    fail 'SSH key path is not a regular file.'; return 1;
  }
  install -d -m 0700 -o "$name" -g "$name" "$home/.ssh"
  if [[ ! -e "$file" ]]; then install -m 0600 -o "$name" -g "$name" "$tmp" "$file"
  elif ! grep -Fxq -- "$key" "$file"; then printf '%s\n' "$key" >> "$file"; fi
  chown "$name:$name" "$file"
  chmod 0600 "$file"
  rm -f -- "$tmp"
)
create_accounts() {
  local name
  local -a group=()
  while ask 'Create a local user?'; do
    name=$(input 'New username: ') || return 1
    valid_name "$name" && ! getent passwd "$name" >/dev/null || { note 'Invalid or existing username.'; continue; }
    group=()
    if ask "Grant $name wheel (admin) access?"; then group=(-G wheel); fi
    useradd -m -s /bin/bash "${group[@]}" "$name" || return 1
    USERS_CREATED+=("$name")
    note "Set a password for $name (handled by passwd, never by KMOS):"
    passwd "$name" || { passwd -l "$name"; fail "Password setup failed; $name is locked until resolved."; return 1; }
    add_key "$name" || return 1
    if ((${#group[@]})); then
      ensure_admin_sudo "$name" || { fail "$name was created but does not have verified sudo access; repair it from an authorized admin before relying on it."; return 1; }
    fi
    note "Created $name. Verify a NEW SSH login before removing an old administrator."
  done
}
sudo_allowed() { sudo -l -U "$1" -u root -- /usr/bin/true >/dev/null 2>&1; }
ensure_admin_sudo() (
  local name=$1 rule tmp
  valid_name "$name" && regular_user "$name" && is_admin "$name" || { fail 'Sudo grants require an existing regular wheel user.'; return 1; }
  sudo_allowed "$name" && return 0
  rule="$SUDO_RULE_DIR/20-kmos-adopt-$name"
  [[ ! -e "$rule" && ! -L "$rule" && ! -L "$SUDO_RULE_DIR" ]] || {
    fail "Existing sudo rule or symlink $rule needs manual review."; return 1;
  }
  note "$name is in wheel but is not authorized for sudo as root."
  note "Proposed rule for $name ONLY: $name ALL=(ALL:ALL) ALL"
  ask "Grant sudo to $name via $rule?" || { fail "Sudo grant for $name declined; no rule installed."; return 1; }
  command -v visudo >/dev/null || { fail 'visudo is required to validate sudo policy.'; return 1; }
  tmp=$(mktemp) || return 1
  trap 'rm -f -- "$tmp"' EXIT
  printf '%s ALL=(ALL:ALL) ALL\n' "$name" > "$tmp"
  chmod 0440 "$tmp"
  visudo -c -f "$tmp" >/dev/null || { fail 'Invalid sudo policy.'; return 1; }
  [[ -d "$SUDO_RULE_DIR" ]] || install -d -m 0750 "$SUDO_RULE_DIR"
  install -m 0440 -o root -g root "$tmp" "$rule"
  sudo_allowed "$name" || { fail "Sudo policy still denies $name; review $rule and the host sudoers policy before relying on this account."; return 1; }
)
repair_admin_sudo() {
  local entry name
  while IFS= read -r entry; do
    name=${entry%%:*}
    is_admin "$name" || continue
    sudo_allowed "$name" && continue
    note "$name is in wheel but lacks sudo authorization."
    if ask "Repair sudo for existing wheel user $name?"; then
      ensure_admin_sudo "$name" || return 1
    fi
  done < <(regular_users)
}
choose_builder() {
  local name=$1
  regular_user "$name" && is_admin "$name" || { fail 'AUR builder must be a regular wheel user.'; return 1; }
  command -v runuser >/dev/null && command -v sudo >/dev/null || { fail 'runuser and sudo are required.'; return 1; }
  ensure_admin_sudo "$name" || return 1
  note "Checking sudo access for $name; sudo may ask for that user's password."
  runuser -u "$name" -- sudo -v || { fail "Cannot use $name for AUR; fix sudo access first."; return 1; }
}
aur_builder() {
  local name entry count=0 chosen=""
  name=${SUDO_USER:-}
  if [[ -n "$name" && "$name" != root ]] && regular_user "$name" && is_admin "$name"; then
    printf '%s\n' "$name"
    return 0
  fi
  for name in "${USERS_CREATED[@]}"; do
    if regular_user "$name" && is_admin "$name"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  while IFS= read -r entry; do
    name=${entry%%:*}
    if is_admin "$name"; then
      chosen=$name
      ((count += 1))
    fi
  done < <(regular_users)
  if ((count == 1)); then printf '%s\n' "$chosen"; return 0; fi
  fail 'Run adoption from a regular wheel account with sudo; root cannot safely choose among multiple admins.'
}
helper_works() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }
select_aur_helper() {
  local choice
  note 'AUR is required for VPS adoption; tododo-bin will be installed.'
  note 'AUR helper options'
  printf '  1) paru\n  2) yay\n' >&2
  while true; do
    choice=$(input 'Select [1-2] (default: 1): ') || return 1
    case "$choice" in
      ''|1) choice=paru; break ;;
      2) choice=yay; break ;;
      *) note 'Invalid selection.' ;;
    esac
  done
  if command -v "$choice" >/dev/null 2>&1 && ! helper_works "$choice"; then
    if [[ "$choice" == paru ]]; then
      note 'Installed paru cannot start; the source build will replace it after explicit approval.'
    else
      fail 'Installed yay cannot start (possibly a libalpm ABI mismatch); repair it before choosing yay.'
      return 1
    fi
  fi
  printf '%s\n' "$choice"
}
install_source_paru() (
  local builder=$1 builddir list archive="" candidate
  local -a old_packages=()
  note 'Building paru from AUR source requires Rust and may use substantial VPS RAM/disk space.'
  pacman -Syu --needed -- rust || { fail 'Could not install Rust for the paru source build.'; return 1; }
  builddir=$(mktemp -d /tmp/kmos-aur.XXXXXXXX) || return 1
  trap 'rm -rf -- "$builddir"' EXIT
  chmod 0700 "$builddir"
  chown "$builder:$builder" "$builddir"
  runuser -u "$builder" -- git clone https://aur.archlinux.org/paru.git "$builddir/paru" || {
    fail 'Could not clone paru from AUR.'; return 1;
  }
  [[ -f "$builddir/paru/PKGBUILD" ]] || { fail 'Paru PKGBUILD missing.'; return 1; }
  cat -- "$builddir/paru/PKGBUILD"
  ask 'Approve building paru from the AUR source shown above?' || {
    fail 'Paru source build declined.'; return 1;
  }
  runuser -u "$builder" -- bash -c 'cd -- "$1" && makepkg -s' _ "$builddir/paru" || {
    fail 'Could not build paru from source; installed AUR helpers were preserved.'; return 1;
  }
  list=$(runuser -u "$builder" -- bash -c 'cd -- "$1" && makepkg --packagelist' _ "$builddir/paru") || {
    fail 'Cannot locate the built paru package.'; return 1;
  }
  while IFS= read -r candidate; do
    if [[ "$candidate" == "$builddir/paru/"* && "${candidate##*/}" == paru-[0-9]*.pkg.tar.* && -f "$candidate" ]]; then
      archive=$candidate
      break
    fi
  done <<< "$list"
  [[ -n "$archive" ]] || { fail 'Built paru package missing; existing helpers were preserved.'; return 1; }
  installed paru-bin-debug && old_packages+=(paru-bin-debug)
  installed paru-bin && old_packages+=(paru-bin)
  if ((${#old_packages[@]} > 0)); then
    note "The source package conflicts with installed ${old_packages[*]}."
    ask "Approve removing ${old_packages[*]} before installing the built paru package?" || {
      fail 'Existing paru-bin packages preserved; source package was not installed.'; return 1;
    }
    # Do not remove any dependencies. Pacman refuses removal if another package needs them.
    pacman -R -- "${old_packages[@]}" || { fail 'Could not remove conflicting binary packages.'; return 1; }
  fi
  pacman -U -- "$archive" || {
    fail 'Could not install built paru; an approved paru-bin removal may have completed. Rerun to rebuild.'; return 1;
  }
)
install_aur() {
  local builder=$1 helper=$2 builddir repo
  if [[ "$helper" == paru ]]; then
    if ! installed paru || installed paru-bin || ! helper_works paru; then
      install_source_paru "$builder" || return 1
    fi
  elif ! command -v "$helper" >/dev/null 2>&1; then
    builddir=$(mktemp -d /tmp/kmos-aur.XXXXXXXX) || return 1
    chmod 0700 "$builddir"
    chown "$builder:$builder" "$builddir"
    repo=yay-bin
    if ! runuser -u "$builder" -- git clone "https://aur.archlinux.org/$repo.git" "$builddir/$repo"; then
      rm -rf -- "$builddir"
      fail "Could not clone $repo; retry later."; return 1
    fi
    [[ -f "$builddir/$repo/PKGBUILD" ]] || { rm -rf -- "$builddir"; fail 'AUR PKGBUILD missing.'; return 1; }
    cat -- "$builddir/$repo/PKGBUILD"
    if ! ask "Approve building $repo from the AUR source shown above?"; then
      rm -rf -- "$builddir"
      fail 'AUR helper build declined.'; return 1
    fi
    if ! runuser -u "$builder" -- bash -c 'cd -- "$1" && makepkg -si --needed' _ "$builddir/$repo"; then
      rm -rf -- "$builddir"
      fail "Could not build $repo; inspect the AUR source and retry."; return 1
    fi
    rm -rf -- "$builddir"
  fi
  helper_works "$helper" || { fail "$helper cannot start after installation; check its libalpm compatibility."; return 1; }
  runuser -u "$builder" -- "$helper" --version >/dev/null 2>&1 || {
    fail "$helper does not work for the AUR build user $builder."; return 1;
  }
  if ! installed tododo-bin; then runuser -u "$builder" -- "$helper" -S --needed tododo-bin || return 1; fi
  installed tododo-bin || { fail 'tododo-bin is mandatory and was not installed.'; return 1; }
}
enable_ssh() {
  installed openssh || { fail 'OpenSSH was not installed.'; return 1; }
  command -v sshd >/dev/null 2>&1 && command -v ssh-keygen >/dev/null 2>&1 || {
    fail 'OpenSSH server or key-generation binary is missing.'; return 1;
  }
  ssh-keygen -A || { fail 'Could not generate missing SSH host keys.'; return 1; }
  sshd -t || { fail 'Existing sshd configuration is invalid; refusing to enable or start it.'; return 1; }
  if ! systemctl is-enabled --quiet sshd.service; then
    systemctl enable sshd.service || { fail 'Could not enable sshd for boot.'; return 1; }
  fi
  if ! systemctl is-active --quiet sshd.service; then
    systemctl start sshd.service || { fail 'Could not start sshd; inspect its service status.'; return 1; }
  fi
  note 'OpenSSH is enabled for boot and running; an already active sshd was not restarted.'
}
install_appearance() {
  local preset bashrc=$BASHRC profile=$STARSHIP_PROFILE
  [[ ! -L "$SHARE_KMOS" && ! -L "$SHARE_KMOS/starship-presets" ]] || { fail 'KMOS preset path is a symlink.'; return 1; }
  install -d -m 0755 "$SHARE_KMOS/starship-presets"
  for preset in "$PRESETS"/*.toml; do
    [[ -f "$preset" ]] || continue
    if [[ -L "$SHARE_KMOS/starship-presets/${preset##*/}" ]]; then
      note "Symlinked preset preserved: ${preset##*/}"; continue
    fi
    if [[ -e "$SHARE_KMOS/starship-presets/${preset##*/}" ]] &&
        ! cmp -s "$preset" "$SHARE_KMOS/starship-presets/${preset##*/}"; then
      note "Differing preset preserved: ${preset##*/}"; continue
    fi
    install -m 0644 "$preset" "$SHARE_KMOS/starship-presets/${preset##*/}"
  done
  if [[ -e "$profile" || -L "$profile" ]]; then
    note "Existing $profile preserved; no prompt selection change."
  else
    install -Dm0644 /dev/stdin "$profile" <<'EOF'
if [ -z "${STARSHIP_CONFIG:-}" ]; then
  if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
    export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/holow-light.toml
  else
    export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/tty-term.toml
  fi
fi
EOF
  fi
  [[ ! -L "$bashrc" ]] || { fail 'Global Bash config is a symlink; skipping integration.'; return 1; }
  if [[ -f "$bashrc" ]] && grep -qE 'starship init bash|zoxide init bash' "$bashrc" &&
      ! grep -Fxq '# kmos headless adoption' "$bashrc"; then
    note "Existing Bash prompt integration preserved in $bashrc; KMOS integration skipped."
    return 0
  fi
  if ! grep -Fxq '# kmos headless adoption' "$bashrc" 2>/dev/null; then
    cat >> "$bashrc" <<'EOF'

# kmos headless adoption
if [[ $- == *i* ]]; then
  command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
  command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
fi
EOF
  fi
}
remove_account() {
  local name=$1 home login count=0 entry
  regular_user "$name" || { fail 'Only regular /home users can be removed.'; return 1; }
  login=${SUDO_USER:-$(id -un)}
  [[ "$name" != "$login" ]] || { fail 'Cannot remove the current login.'; return 1; }
  if is_admin "$name"; then
    regular_user "$login" && is_admin "$login" || { fail 'Remove an old admin only from a different verified wheel login.'; return 1; }
    while IFS= read -r entry; do
      is_admin "${entry%%:*}" && ((count += 1))
    done < <(regular_users)
    ((count > 1)) || { fail 'Cannot remove the last regular administrator.'; return 1; }
  fi
  if command -v loginctl >/dev/null && loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -Fxq "$name"; then
    fail 'Account has an active login session.'; return 1
  fi
  command -v pgrep >/dev/null || { fail 'Cannot check running processes; refusing removal.'; return 1; }
  if pgrep -u "$name" >/dev/null 2>&1 || pgrep -U "$name" >/dev/null 2>&1; then
    fail 'Account has running processes.'; return 1
  fi
  home=$(getent passwd "$name" | cut -d: -f6)
  note "Remove account $name (home: $home). This cannot be undone."
  local answer
  answer=$(input "Type REMOVE $name to continue: ") || return 1
  [[ "$answer" == "REMOVE $name" ]] || { note 'Removal cancelled.'; return 0; }
  if ask "Also DELETE $home and its contents permanently?"; then
    answer=$(input "Type DELETE $home to confirm home deletion: ") || return 1
    [[ "$answer" == "DELETE $home" ]] || { note 'Home deletion cancelled; account retained.'; return 0; }
    [[ ! -L "$home" ]] || { fail 'Home is a symlink; refusing deletion.'; return 1; }
    [[ "$home" == "/home/$name" ]] || { fail 'Nonstandard home; refusing automated deletion.'; return 1; }
    if findmnt -rn --mountpoint "$home" >/dev/null 2>&1; then
      fail 'Home is a mount point; refusing deletion.'; return 1
    fi
    if findmnt -rn -o TARGET | grep -Fq -- "$home/"; then
      fail 'A filesystem is mounted inside this home; refusing deletion.'; return 1
    fi
    userdel -r -- "$name"
  else
    userdel -- "$name"
    note "Home retained at $home; handle it manually when no longer needed."
  fi
}
remove_accounts() {
  local name
  if ((${#USERS_CREATED[@]} > 0)); then
    note 'No accounts will be removed in a run that created users; verify a fresh SSH login first.'
    return 0
  fi
  while ask 'Remove an old local user?'; do
    name=$(input 'Existing username to remove: ') || return 1
    remove_account "$name" || return 1
  done
}
guided() {
  local helper builder
  require_root || return 1
  preflight || return 1
  note 'Review the package transaction; Arch upgrades and pacman hooks may affect running services.'
  note 'Take a VPS snapshot or have provider console access. No automatic configuration backups are retained.'
  ask 'Continue with KMOS adoption?' || { note 'Cancelled without changes.'; return 0; }
  helper=$(select_aur_helper) || return 1
  note 'Running pacman -Syu --needed; review package replacement prompts.'
  pacman -Syu --needed -- "${PACKAGES[@]}" || return 1
  enable_ssh || return 1
  offer_hostname || return 1
  create_accounts || return 1
  builder=$(aur_builder) || return 1
  note "Using $builder for the AUR build; $helper is installed system-wide for all users."
  choose_builder "$builder" || return 1
  install_aur "$builder" "$helper" || return 1
  install_appearance || return 1
  [[ ! -e "$MARKER" && ! -L "$MARKER" ]] && install -Dm0644 /dev/stdin "$MARKER" <<< 'Arch headless adoption (not ISO-installed KMOS)'
  remove_accounts || return 1
  note 'KMOS headless adoption completed; sshd is enabled and active, and network services were not reconfigured.'
}
users_only() {
  require_root --users-only || return 1
  preflight || return 1
  note 'Accounts-only mode: no package transactions, AUR builds or SSH/network changes.'
  ask 'Continue to account management?' || { note 'Cancelled without changes.'; return 0; }
  repair_admin_sudo || return 1
  create_accounts || return 1
  remove_accounts
}

main() {
  case "${1:---guided}" in
    --help|-h) (($# <= 1)) || { usage >&2; return 2; }; usage ;;
    --preflight) (($# == 1)) || { usage >&2; return 2; }; preflight ;;
    --users-only) (($# == 1)) || { usage >&2; return 2; }; users_only ;;
    --guided) (($# == 0)) || { usage >&2; return 2; }; guided ;;
    *) usage >&2; return 2 ;;
  esac
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
