#!/usr/bin/env bash
# Provision the userspace of a Quartz64 Arch Linux ARM install with KMOS headless settings.
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
REPOSITORY_DIR=""
PRIMARY_USER=""
HOSTNAME_VALUE=""
WIFI_ADAPTER=""
AVAILABLE_PACKAGES=()
SKIPPED_PACKAGES=()
KDE_PACKAGES=()
KDE_METAPACKAGES=()

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

info() {
  printf '==> %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: ./provision-kmos-headless.sh

Run this script from a complete local KMOS Git checkout on an already booted
Quartz64. Uses the checkout's package manifests, assets and helper scripts.
It does not clone another repository or modify the board's bootloader.
EOF
}

ask_yes_no() {
  local prompt=$1 default=${2:-no} answer
  while true; do
    if [[ "$default" == yes ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer=${answer:-Y}
    else
      read -r -p "$prompt [y/N]: " answer
      answer=${answer:-N}
    fi
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) warn 'Please answer yes or no.' ;;
    esac
  done
}

prompt_secret() {
  local prompt=$1 first second
  while true; do
    read -r -s -p "$prompt: " first
    printf '\n' >&2
    [[ -n "$first" ]] || { warn 'Password cannot be empty.'; continue; }
    read -r -s -p "Confirm $prompt: " second
    printf '\n' >&2
    [[ "$first" == "$second" ]] || { warn 'Passwords do not match.'; continue; }
    printf '%s\n' "$first"
    unset first second
    return
  done
}

require_root_and_arm() {
  [[ $(uname -m) == aarch64 ]] || die "This script requires AArch64; current architecture: $(uname -m)"
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is not installed.'
  info 'Root access is required; sudo will prompt for your password.'
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
}

parse_arguments() {
  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

find_local_repository() {
  local repository_dir=""
  repository_dir=$(cd -- "$SCRIPT_DIR/../../../.." && pwd -P) || die 'Could not locate the local KMOS checkout.'
  validate_repository "$repository_dir"
  printf '%s\n' "$repository_dir"
}

validate_repository() {
  local repository_dir=$1
  [[ -d "$repository_dir/.git" ]] || die 'A complete KMOS Git checkout is required.'
  [[ $(git -C "$repository_dir" rev-parse --show-toplevel) == "$repository_dir" ]] || die 'The KMOS path does not match the Git checkout root.'
  [[ -r "$repository_dir/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD" ]] || die 'Headless package manifest missing. Clone the complete KMOS repository onto the Quartz64.'
  [[ -r "$repository_dir/platforms/archlinux/assets/starship-presets/tty-term.toml" ]] || die 'KMOS terminal presets missing. Clone the complete repository.'
  [[ -r "$repository_dir/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" ]] || die 'Quartz64 provisioner missing from the checkout.'
  [[ -x "$repository_dir/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" ]] || die 'Quartz64 Wi-Fi helper missing from the checkout.'
  [[ -r "$repository_dir/platforms/archlinux/packages/metapackages/kde/noapps/PKGBUILD" ]] || die 'KMOS KDE manifest missing from the checkout.'
}

configure_pacman() {
  local pacman_conf=/etc/pacman.conf
  sed -i 's/^#Color$/Color/' "$pacman_conf"
  if grep -q '^#ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  elif ! grep -q '^ParallelDownloads = ' "$pacman_conf"; then
    printf '\nParallelDownloads = 6\n' >> "$pacman_conf"
  fi
  grep -q '^ILoveCandy$' "$pacman_conf" || sed -i '/^ParallelDownloads = /a ILoveCandy' "$pacman_conf"
}

initialize_pacman() {
  info 'Initializing the package keyring and updating Arch Linux ARM.'
  pacman-key --init
  pacman-key --populate archlinuxarm
  pacman -Syu --needed --noconfirm
  pacman -S --needed --noconfirm git iwd nano openssh sudo
  configure_pacman
}

load_kmos_packages() {
  local pkgbuild=$1
  [[ -r "$pkgbuild" ]] || die "KMOS package manifest not found: $pkgbuild"
  awk -F"'" '
    /^depends=\(/ { in_depends=1; next }
    in_depends && /^\)/ { exit }
    in_depends && NF >= 3 { print $2 }
  ' "$pkgbuild"
}

handle_unavailable_package() {
  local package=$1 choice
  printf '\n%s is unavailable in the AArch64 repositories.\n' "$package"
  case "$package" in
    opencode) printf 'Upstream source for inspection or building: https://github.com/anomalyco/opencode\n' ;;
    *) printf 'No upstream build source is configured automatically for this package.\n' ;;
  esac
  while true; do
    read -r -p 'Skip [s], cancel [c], or show upstream [u]? [s]: ' choice
    choice=${choice:-s}
    case "$choice" in
      [Ss]) warn "Skipping $package."; return ;;
      [Uu])
        case "$package" in
          opencode) printf 'Upstream source: https://github.com/anomalyco/opencode\n' ;;
          *) printf 'No upstream source configured for %s.\n' "$package" ;;
        esac
        ;;
      [Cc]) die "Cancelled before skipping $package." ;;
      *) warn 'Choose s, c, or u.' ;;
    esac
  done
}

install_kmos_packages() {
  local repository_dir=$1 package package_lines package_summary=""
  local -a packages=()
  package_lines=$(load_kmos_packages "$repository_dir/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD") || die 'Could not read the headless package manifest.'
  [[ -n "$package_lines" ]] || die 'KMOS does not define headless packages.'
  mapfile -t packages <<< "$package_lines"
  ((${#packages[@]} > 0)) || die 'KMOS does not define headless packages.'
  printf -v package_summary '%s ' "${packages[@]}"
  info "KMOS headless package set: ${package_summary% }"
  for package in "${packages[@]}"; do
    [[ "$package" =~ ^[a-zA-Z0-9@._+:-]+$ ]] || die "Invalid KMOS package name: $package"
    if pacman -Si "$package" >/dev/null 2>&1; then
      AVAILABLE_PACKAGES+=("$package")
    else
      handle_unavailable_package "$package"
      SKIPPED_PACKAGES+=("$package")
    fi
  done
  ((${#AVAILABLE_PACKAGES[@]} == 0)) || pacman -S --needed --noconfirm "${AVAILABLE_PACKAGES[@]}"
  if ((${#SKIPPED_PACKAGES[@]} > 0)); then
    printf -v package_summary '%s ' "${SKIPPED_PACKAGES[@]}"
    warn "Packages skipped by your choice: ${package_summary% }"
  fi
}

kde_metapackage_path() {
  case "$1" in
    kmos-audio) printf 'desktop-shared/audio/PKGBUILD\n' ;;
    kmos-browsers) printf 'desktop-shared/browsers/PKGBUILD\n' ;;
    kmos-devices) printf 'desktop-shared/devices/PKGBUILD\n' ;;
    kmos-docs) printf 'desktop-shared/docs/PKGBUILD\n' ;;
    kmos-filesystems) printf 'desktop-shared/filesystems/PKGBUILD\n' ;;
    kmos-fonts) printf 'desktop-shared/fonts/PKGBUILD\n' ;;
    kmos-graphics) printf 'desktop-shared/graphics/PKGBUILD\n' ;;
    kmos-kde-base) printf 'kde/base/PKGBUILD\n' ;;
    kmos-kde-multimedia) printf 'kde/multimedia/PKGBUILD\n' ;;
    kmos-kde-utils) printf 'kde/utils/PKGBUILD\n' ;;
    kmos-kde-noapps) printf 'kde/noapps/PKGBUILD\n' ;;
    kmos-kde-plasma) printf 'kde/base/plasma/PKGBUILD\n' ;;
    kmos-maintenance) printf 'desktop-shared/maintenance/PKGBUILD\n' ;;
    kmos-network) printf 'desktop-shared/network/PKGBUILD\n' ;;
    kmos-privacy) printf 'desktop-shared/privacy/PKGBUILD\n' ;;
    *) return 1 ;;
  esac
}

resolve_kde_metapackage() {
  local name=$1 relative dependency manifest package_lines seen=0
  local -a dependencies=()
  local previous
  for previous in "${KDE_METAPACKAGES[@]}"; do
    [[ "$previous" != "$name" ]] || return 0
  done
  relative=$(kde_metapackage_path "$name") || die "Unknown KDE metapackage: $name"
  manifest="$REPOSITORY_DIR/platforms/archlinux/packages/metapackages/$relative"
  package_lines=$(load_kmos_packages "$manifest") || die "Could not read $manifest"
  if [[ -n "$package_lines" ]]; then mapfile -t dependencies <<< "$package_lines"; fi
  KDE_METAPACKAGES+=("$name")
  for dependency in "${dependencies[@]}"; do
    [[ "$dependency" =~ ^[a-zA-Z0-9@._+:-]+$ ]] || die "Invalid KDE dependency: $dependency"
    if [[ "$dependency" == kmos-* ]]; then
      resolve_kde_metapackage "$dependency"
    else
      seen=0
      for previous in "${KDE_PACKAGES[@]}"; do
        if [[ "$previous" == "$dependency" ]]; then seen=1; break; fi
      done
      if ((seen == 0)); then KDE_PACKAGES+=("$dependency"); fi
    fi
  done
}

offer_kde_desktop() {
  local profile package summary="" missing_summary="" graphics_device=""
  local -a available=() missing=()
  local -a full=(kmos-audio kmos-browsers kmos-devices kmos-docs kmos-filesystems kmos-fonts kmos-graphics kmos-kde-base kmos-kde-multimedia kmos-kde-utils kmos-maintenance kmos-network kmos-privacy)
  local metapackage
  ask_yes_no 'Install a KDE desktop now?' no || return 0
  for graphics_device in /dev/dri/card[0-9]*; do
    [[ -e "$graphics_device" ]] && break
  done
  [[ -e "$graphics_device" ]] || { warn 'No DRM device found in /dev/dri; KDE will not be installed until Quartz64 graphics are verified.'; return 0; }
  read -r -p 'KDE profile [noapps/full] (noapps): ' profile
  profile=${profile:-noapps}
  case "$profile" in
    noapps) resolve_kde_metapackage kmos-kde-noapps ;;
    full)
      for metapackage in "${full[@]}"; do resolve_kde_metapackage "$metapackage"; done
      ;;
    *) die 'Invalid KDE profile; the headless system remains available.' ;;
  esac
  for package in "${KDE_PACKAGES[@]}"; do
    if pacman -Si "$package" >/dev/null 2>&1; then
      available+=("$package")
    else
      missing+=("$package")
    fi
  done
  for package in plasma-desktop plasma-workspace kwin sddm networkmanager; do
    if ! pacman -Si "$package" >/dev/null 2>&1; then
      warn "Essential KDE component unavailable on ARM: $package. No KDE packages will be installed."
      return 0
    fi
  done
  if ((${#missing[@]} > 0)); then
    printf -v missing_summary '%s ' "${missing[@]}"
    warn "Optional KDE packages unavailable on ARM: ${missing_summary% }."
    info 'Source builds and x86 binaries will not be used automatically.'
    ask_yes_no 'Skip those packages and continue with KDE?' no || { info 'KDE deferred; the headless system remains available.'; return 0; }
  fi
  ((${#available[@]} > 0)) || die 'No KDE packages are available.'
  printf -v summary '%s ' "${available[@]}"
  info "KDE $profile will install: ${summary% }"
  ask_yes_no 'Install KDE on the Quartz64?' no || return 0
  pacman -S --needed --noconfirm "${available[@]}"
  for package in plasma-desktop plasma-workspace kwin sddm networkmanager; do
    pacman -Q "$package" >/dev/null || die "KDE component missing after installation: $package"
  done
  # Keep iwd + networkd in charge of Wi-Fi and Ethernet until NM migration is
  # verified on the physical board; never disable the working network here.
  systemctl enable sddm.service
  systemctl set-default graphical.target
  info 'KDE installed. Headless networking remains active; NetworkManager will not start until migration is validated on the board.'
}

configure_kmos_terminal() {
  local repository_dir=$1
  local preset="$repository_dir/platforms/archlinux/assets/starship-presets/tty-term.toml"
  [[ -r "$preset" ]] || die 'KMOS TTY preset not found.'
  install -Dm0644 "$preset" /usr/share/kmos/starship-presets/tty-term.toml
  install -Dm0644 /dev/stdin /etc/profile.d/10-kmos-starship.sh <<'EOF'
export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/tty-term.toml
EOF
  touch /etc/bash.bashrc
  if ! grep -q '^# kmos headless shell$' /etc/bash.bashrc; then
    cat >> /etc/bash.bashrc <<'EOF'

# kmos headless shell
if [[ $- == *i* ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
if [[ $- == *i* ]] && command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
export EDITOR=nano
export VISUAL=nano
EOF
  fi
  install -d -m 0755 /opt/kmos/assets/starship-presets
  cp -a "$repository_dir/platforms/archlinux/assets/starship-presets/." /opt/kmos/assets/starship-presets/
}

configure_identity() {
  local timezone locale keymap
  read -r -p 'New hostname: ' HOSTNAME_VALUE
  [[ "$HOSTNAME_VALUE" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die 'Invalid hostname.'
  read -r -p 'Timezone [Europe/Zurich]: ' timezone
  timezone=${timezone:-Europe/Zurich}
  [[ "$timezone" =~ ^[a-zA-Z0-9_+/-]+$ && "$timezone" != *..* ]] || die 'Invalid timezone.'
  [[ -e "/usr/share/zoneinfo/$timezone" ]] || die "Timezone does not exist: $timezone"
  read -r -p 'Locale [en_US.UTF-8]: ' locale
  locale=${locale:-en_US.UTF-8}
  [[ "$locale" =~ ^[a-zA-Z_]+\.UTF-8$ ]] || die 'Invalid locale.'
  read -r -p 'Console keymap [us]: ' keymap
  keymap=${keymap:-us}
  [[ "$keymap" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Invalid keymap.'
  ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
  if [[ -e /dev/rtc0 ]]; then
    hwclock --systohc || warn 'Could not update the hardware clock; system time remains unchanged.'
  fi
  grep -q "^$locale UTF-8" /etc/locale.gen || sed -i "s/^#$locale UTF-8/$locale UTF-8/" /etc/locale.gen
  grep -q "^$locale UTF-8" /etc/locale.gen || printf '%s UTF-8\n' "$locale" >> /etc/locale.gen
  locale-gen
  printf 'LANG=%s\n' "$locale" > /etc/locale.conf
  printf 'KEYMAP=%s\n' "$keymap" > /etc/vconsole.conf
  printf '%s\n' "$HOSTNAME_VALUE" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME_VALUE.localdomain $HOSTNAME_VALUE
EOF
}

create_administrator() {
  local username password additional add_password
  while true; do
    read -r -p 'Primary administrator username: ' username
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] && break
    warn 'Invalid username.'
  done
  password=$(prompt_secret "Password for $username")
  if id "$username" >/dev/null 2>&1; then
    usermod -aG wheel "$username"
  else
    useradd -m -G wheel -s /bin/bash "$username"
  fi
  printf '%s:%s\n' "$username" "$password" | chpasswd
  unset password
  PRIMARY_USER=$username

  while ask_yes_no 'Create another user?' no; do
    read -r -p 'Additional username: ' additional
    [[ "$additional" =~ ^[a-z_][a-z0-9_-]*$ ]] || { warn 'Invalid username.'; continue; }
    add_password=$(prompt_secret "Password for $additional")
    if id "$additional" >/dev/null 2>&1; then
      usermod -aG users "$additional"
    else
      useradd -m -s /bin/bash "$additional"
    fi
    if ask_yes_no "Grant sudo access to $additional?" no; then
      usermod -aG wheel "$additional"
    fi
    printf '%s:%s\n' "$additional" "$add_password" | chpasswd
    unset add_password
  done
  install -Dm0440 /dev/stdin /etc/sudoers.d/00-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
}

configure_ssh() {
  install -Dm0644 /dev/stdin /etc/ssh/sshd_config.d/10-kmos.conf <<'EOF'
PermitRootLogin no
PermitEmptyPasswords no
PasswordAuthentication yes
EOF
  systemctl enable sshd.service
}

configure_networkd() {
  install -d -m 0755 /etc/systemd/network
  cat > /etc/systemd/network/20-ethernet-dhcp.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=100
EOF
  cat > /etc/systemd/network/25-wifi-dhcp.network <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
  ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl enable systemd-networkd.service systemd-resolved.service
}

detect_wifi_adapter() {
  local interface
  for interface in /sys/class/net/*; do
    [[ -d "$interface/wireless" ]] || continue
    printf '%s\n' "${interface##*/}"
    return
  done
  return 1
}

configure_wifi() {
  ask_yes_no 'Configure persistent Wi-Fi now?' no || return
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || { warn 'No Wi-Fi adapter detected. Ethernet remains configured.'; return; }
  "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
  info 'Wi-Fi configured; iwd and systemd-networkd will retain the connection after reboot.'
}

configure_swap() {
  local size
  read -r -p 'Swapfile size [4G, 0 to skip]: ' size
  size=${size:-4G}
  [[ "$size" == 0 ]] && return
  [[ "$size" =~ ^[1-9][0-9]*[MG]$ ]] || die 'Invalid swap size. Use 0, 512M, or 4G.'
  if [[ -e /swapfile || -L /swapfile ]]; then
    if ! ask_yes_no '/swapfile already exists. Replace it? Its contents will be lost.' no; then
      info 'Existing swapfile kept.'
      return 0
    fi
  fi
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fallocate -l "$size" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  sed -i '\|^/swapfile |d' /etc/fstab
  printf '/swapfile none swap defaults 0 0\n' >> /etc/fstab
}

remove_alarm() {
  getent passwd alarm >/dev/null || return
  ask_yes_no 'Remove the initial alarm user and its home directory?' yes || return
  id "$PRIMARY_USER" >/dev/null || die 'Administrator account is missing; alarm will not be removed.'
  userdel -r alarm
}

configure_syncthing() {
  pacman -Q syncthing >/dev/null 2>&1 || { warn 'Syncthing is not installed; its service will be skipped.'; return; }
  ask_yes_no "Enable Syncthing for $PRIMARY_USER?" no || return
  systemctl enable --now "syncthing@$PRIMARY_USER.service"
}

verify_installation() {
  local package
  info 'Verifying configuration.'
  for package in iwd nano openssh sudo "${AVAILABLE_PACKAGES[@]}"; do
    pacman -Q "$package" >/dev/null || die "Expected package missing: $package"
  done
  id "$PRIMARY_USER" >/dev/null
  id -nG "$PRIMARY_USER" | grep -qw wheel || die "$PRIMARY_USER is not in the wheel group."
  sudo -l -U "$PRIMARY_USER" >/dev/null
  [[ $(cat /etc/hostname) == "$HOSTNAME_VALUE" ]] || die 'Hostname does not match.'
  systemctl is-enabled sshd.service systemd-networkd.service systemd-resolved.service >/dev/null
  [[ -f /usr/share/kmos/starship-presets/tty-term.toml ]] || die 'Starship preset is missing.'
  if [[ -n "$WIFI_ADAPTER" ]]; then
    systemctl is-enabled iwd.service >/dev/null
    iwctl station "$WIFI_ADAPTER" show || warn 'Could not query Wi-Fi status.'
  fi
}

main() {
  parse_arguments "$@"
  REPOSITORY_DIR=$(find_local_repository)
  require_root_and_arm "$@"
  info "KMOS checkout commit: $(git -C "$REPOSITORY_DIR" rev-parse HEAD)"
  if [[ -n $(git -C "$REPOSITORY_DIR" status --porcelain --untracked-files=no) ]]; then
    warn 'This checkout has local changes; the files used may differ from the displayed commit.'
  fi
  info 'Arch Linux ARM will be updated and configured from this KMOS checkout.'
  ask_yes_no 'Continue with provisioning?' no || die 'Cancelled without modifying the system.'
  initialize_pacman
  install_kmos_packages "$REPOSITORY_DIR"
  configure_kmos_terminal "$REPOSITORY_DIR"
  configure_identity
  create_administrator
  configure_ssh
  configure_networkd
  configure_wifi
  configure_swap
  configure_syncthing
  remove_alarm
  verify_installation
  info 'KMOS headless provisioning complete.'
  offer_kde_desktop
  info 'Reboot when convenient, then check networking and any graphical session locally.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
