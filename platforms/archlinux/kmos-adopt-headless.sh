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
SUDO_RULE=/etc/sudoers.d/20-kmos-adopt-wheel
declare -a PACKAGES=() USERS_CREATED=()

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/kmos-adopt-headless.sh [--preflight|--help]

Guided adoption of an INSTALLED Arch x86_64 headless machine (including a VPS).
Reviews packages, accounts, and terminal appearance before changes. Installs
paru (default) or yay and tododo-bin. Enables OpenSSH without rewriting its
configuration or restarting an active sshd. Never formats disks, changes
network services, or converts an existing KDE desktop. Account deletion is final.
--preflight reports eligibility without root or changes; --help needs no root.
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
  local pkg entry name _ home
  eligible || return 1
  packages_for_host || return 1
  printf 'Arch headless x86_64: eligible\nPackages (pacman upgrade + --needed):\n'
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
  printf 'AUR: choose paru (default) or yay; tododo-bin required.\n'
  printf 'Appearance: KMOS Starship presets and managed Bash integration; conflicting configuration is skipped.\n'
  printf 'No changes made. Guided mode enables/starts sshd without changing its config; network, bootloader and disk settings stay intact.\n'
}
require_root() {
  ((EUID == 0)) && return 0
  command -v sudo >/dev/null 2>&1 || { fail 'sudo is required for adoption.'; return 1; }
  exec sudo -- "$SCRIPT_DIR/kmos-adopt-headless.sh" "$@"
}
valid_name() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [[ "$1" != root ]]; }

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
    note "Created $name. Verify a NEW SSH login before removing an old administrator."
  done
}
enable_wheel_sudo() (
  local builder=$1 rule=$SUDO_RULE tmp
  sudo -l -U "$builder" >/dev/null 2>&1 && return 0
  [[ ! -e "$rule" && ! -L "$rule" && ! -L "${rule%/*}" ]] || {
    fail "Existing sudo rule or symlink $rule needs manual review."; return 1;
  }
  note 'The selected wheel user cannot currently use sudo.'
  note 'The proposed rule grants sudo to ALL wheel users: %wheel ALL=(ALL:ALL) ALL'
  ask 'Install this KMOS-owned wheel sudo rule?' || { fail 'AUR builds require working sudo.'; return 1; }
  command -v visudo >/dev/null || { fail 'visudo is required to validate sudo policy.'; return 1; }
  tmp=$(mktemp) || return 1
  trap 'rm -f -- "$tmp"' EXIT
  printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$tmp"
  chmod 0440 "$tmp"
  visudo -c -f "$tmp" >/dev/null || { fail 'Invalid wheel sudo policy.'; return 1; }
  [[ -d "${rule%/*}" ]] || install -d -m 0750 "${rule%/*}"
  install -m 0440 -o root -g root "$tmp" "$rule"
)
choose_builder() {
  local name=$1
  regular_user "$name" && is_admin "$name" || { fail 'AUR builder must be a regular wheel user.'; return 1; }
  command -v runuser >/dev/null && command -v sudo >/dev/null || { fail 'runuser and sudo are required.'; return 1; }
  enable_wheel_sudo "$name" || return 1
  note "Checking sudo access for $name; sudo may ask for that user's password."
  runuser -u "$name" -- sudo -v || { fail "Cannot use $name for AUR; fix sudo access first."; return 1; }
}
install_aur() {
  local builder=$1 helper=$2 builddir repo
  if ! command -v "$helper" >/dev/null 2>&1; then
    builddir=$(mktemp -d /tmp/kmos-aur.XXXXXXXX) || return 1
    chmod 0700 "$builddir"
    chown "$builder:$builder" "$builddir"
    repo="$helper-bin"
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
  command -v "$helper" >/dev/null 2>&1 || { fail "$helper is not runnable."; return 1; }
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
  helper=$(input 'AUR helper [paru/yay] (default paru): ') || return 1
  helper=${helper:-paru}
  [[ "$helper" == paru || "$helper" == yay ]] || { fail 'Choose paru or yay.'; return 1; }
  create_accounts || return 1
  builder=$(input 'Existing/new wheel username for AUR builds: ') || return 1
  regular_user "$builder" && is_admin "$builder" || { fail 'Choose a regular wheel user for AUR.'; return 1; }
  note 'Running pacman -Syu --needed; review package replacement prompts.'
  pacman -Syu --needed -- "${PACKAGES[@]}" || return 1
  enable_ssh || return 1
  choose_builder "$builder" || return 1
  install_aur "$builder" "$helper" || return 1
  install_appearance || return 1
  [[ ! -e "$MARKER" && ! -L "$MARKER" ]] && install -Dm0644 /dev/stdin "$MARKER" <<< 'Arch headless adoption (not ISO-installed KMOS)'
  remove_accounts || return 1
  note 'KMOS headless adoption completed; sshd is enabled and active, and network services were not reconfigured.'
}

main() {
  case "${1:---guided}" in
    --help|-h) (($# <= 1)) || { usage >&2; return 2; }; usage ;;
    --preflight) (($# == 1)) || { usage >&2; return 2; }; preflight ;;
    --guided) (($# == 0)) || { usage >&2; return 2; }; guided ;;
    *) usage >&2; return 2 ;;
  esac
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
