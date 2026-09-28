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
REMOVE_ALARM_REQUESTED=0
ALARM_REMOVAL_PENDING=0
ALARM_HOME=""
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
Usage: ./provision-kmos-headless.sh [provision|repair-prompt|fonts|aur|remove-alarm]

Run this script from a complete local KMOS Git checkout on an already booted
Quartz64. Uses the checkout's package manifests, assets and helper scripts.
No argument provisions KMOS headless. The other commands repair only the
prompt, install only Kappa Mono, choose an AUR helper, or remove alarm.
They do not rerun system provisioning or modify the board's bootloader.
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
  [[ -r "$repository_dir/platforms/archlinuxarm/boards/quartz64b/assets/starship-headless.toml" ]] || die 'Quartz64 headless Starship preset missing.'
  [[ -r "$repository_dir/platforms/archlinux/assets/starship-presets/holow-light.toml" ]] || die 'KMOS SSH Starship preset missing.'
  [[ -r "$repository_dir/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" ]] || die 'Quartz64 provisioner missing from the checkout.'
  [[ -x "$repository_dir/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" ]] || die 'Quartz64 Wi-Fi helper missing from the checkout.'
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
  pacman -S --needed --noconfirm git iwd nano openssh starship sudo
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
    if [[ "$package" == starship ]]; then
      pacman -Q starship >/dev/null || die 'Starship is required for the headless prompt; do not skip it.'
      continue
    fi
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

install_kappa_mono_fonts() (
  local target_dir=${1:-/usr/local/share/fonts/kmos} work_dir font source
  command -v git >/dev/null 2>&1 || die 'Git is required to retrieve the Kappa Mono font repository.'
  work_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/kmos-kappa-mono.XXXXXXXX") || die 'Could not create a private font staging directory.'
  trap 'rm -rf -- "$work_dir"' EXIT
  git clone --quiet --depth 1 --filter=blob:none --sparse \
    https://github.com/kamilomelo/kappa-type.git "$work_dir/kappa-type" || die 'Could not clone the Kappa Type font source.'
  git -C "$work_dir/kappa-type" sparse-checkout set fonts/kappa-mono/ttf || die 'Could not select Kappa Mono font files.'
  info "Kappa Type commit used: $(git -C "$work_dir/kappa-type" rev-parse HEAD)"
  for font in Regular Bold Italic BoldItalic; do
    source="$work_dir/kappa-type/fonts/kappa-mono/ttf/KappaMono-$font.ttf"
    [[ -s "$source" ]] || die "Kappa Mono font missing: $source"
  done
  for font in Regular Bold Italic BoldItalic; do
    install -Dm0644 "$work_dir/kappa-type/fonts/kappa-mono/ttf/KappaMono-$font.ttf" \
      "$target_dir/KappaMono-$font.ttf"
  done
  if command -v fc-cache >/dev/null 2>&1 && command -v fc-match >/dev/null 2>&1; then
    fc-cache -f "$target_dir" || die 'Could not refresh the Kappa Mono font cache.'
    fc-match -f '%{family}\n' 'Kappa Mono' | grep -Fqi 'Kappa Mono' || die 'fontconfig could not find Kappa Mono after installation.'
    info 'Kappa Mono installed and visible to fontconfig.'
  else
    info 'Kappa Mono installed. fontconfig is not installed on this headless system; no extra package was added.'
  fi
)

configure_kde_terminal() {
  local repository_dir=$1 root=${2:-}
  install -Dm0644 "$repository_dir/platforms/archlinux/assets/konsole/kmos.colorscheme" "$root/usr/share/konsole/kmos.colorscheme"
  install -Dm0644 /dev/stdin "$root/usr/share/konsole/kmos.profile" <<'EOF'
[Appearance]
ColorScheme=kmos
Font=Kappa Mono,11,-1,5,50,0,0,0,0,0

[General]
Name=kmos
Parent=FALLBACK/
EOF
  if [[ ! -e "$root/etc/xdg/konsolerc" && ! -L "$root/etc/xdg/konsolerc" ]]; then
    install -Dm0644 /dev/stdin "$root/etc/xdg/konsolerc" <<'EOF'
[Desktop Entry]
DefaultProfile=kmos.profile
EOF
  else
    warn 'Existing system Konsole settings preserved. Select the kmos profile with Kappa Mono in Konsole if necessary.'
  fi
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
  install_kappa_mono_fonts
  configure_kde_terminal "$REPOSITORY_DIR"
  # Keep iwd + networkd in charge of Wi-Fi and Ethernet until NM migration is
  # verified on the physical board; never disable the working network here.
  systemctl enable sddm.service
  systemctl set-default graphical.target
  info 'KDE installed. Headless networking remains active; NetworkManager will not start until migration is validated on the board.'
}

configure_kmos_terminal() {
  local repository_dir=$1 root=${2:-}
  local preset="$repository_dir/platforms/archlinuxarm/boards/quartz64b/assets/starship-headless.toml"
  local ssh_preset="$repository_dir/platforms/archlinux/assets/starship-presets/holow-light.toml"
  [[ -r "$preset" ]] || die 'Quartz64 headless Starship preset not found.'
  [[ -r "$ssh_preset" ]] || die 'KMOS SSH Starship preset not found.'
  install -Dm0644 "$preset" "$root/usr/share/kmos/starship-presets/quartz-headless.toml"
  install -Dm0644 "$ssh_preset" "$root/usr/share/kmos/starship-presets/holow-light.toml"
  # The SSH client renders the Nerd Font glyphs; the physical TTY remains ASCII.
  install -Dm0644 /dev/stdin "$root/etc/profile.d/10-kmos-starship.sh" <<'EOF'
if [ "${TERM:-}" = linux ]; then
  STARSHIP_CONFIG=/usr/share/kmos/starship-presets/quartz-headless.toml
elif [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]; then
  STARSHIP_CONFIG=/usr/share/kmos/starship-presets/holow-light.toml
else
  STARSHIP_CONFIG=/usr/share/kmos/starship-presets/quartz-headless.toml
fi
export STARSHIP_CONFIG
# SSH login shells read /etc/profile.d, even if they do not read bash.bashrc.
if [ -n "${BASH_VERSION:-}" ]; then
  case $- in
    *i*)
      if command -v starship >/dev/null 2>&1; then
        case "${PROMPT_COMMAND:-}" in
          *starship_precmd*) ;;
          *) eval "$(starship init bash)" ;;
        esac
      fi
      ;;
  esac
fi
EOF
  install -d -m 0755 "$root/etc"
  touch "$root/etc/bash.bashrc"
  if ! grep -q '^# kmos headless shell$' "$root/etc/bash.bashrc"; then
    cat >> "$root/etc/bash.bashrc" <<'EOF'

# kmos headless shell
if [[ $- == *i* && "${PROMPT_COMMAND:-}" != *starship_precmd* ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
if [[ $- == *i* ]] && command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
export EDITOR=nano
export VISUAL=nano
EOF
  fi
  # Reapply for interactive non-login Bash, and override older KMOS KDE/SSH
  # selection blocks on machines provisioned by a previous version.
  if ! grep -q '^# kmos Quartz64 headless prompt$' "$root/etc/bash.bashrc"; then
    cat >> "$root/etc/bash.bashrc" <<'EOF'

# kmos Quartz64 headless prompt
if [[ $- == *i* && -r /etc/profile.d/10-kmos-starship.sh ]]; then
  source /etc/profile.d/10-kmos-starship.sh
fi
EOF
  fi
}

verify_headless_prompt() {
  local config=/usr/share/kmos/starship-presets/quartz-headless.toml
  local ssh_config=/usr/share/kmos/starship-presets/holow-light.toml
  command -v starship >/dev/null 2>&1 || die 'Starship binary is missing; the headless prompt cannot work.'
  [[ -r "$config" ]] || die 'Headless Starship preset is missing.'
  [[ -r "$ssh_config" ]] || die 'SSH Starship preset is missing.'
  bash -n /etc/bash.bashrc /etc/profile.d/10-kmos-starship.sh || die 'Headless Bash startup configuration has a syntax error.'
  STARSHIP_CONFIG="$config" starship prompt >/dev/null || die 'Starship could not render the headless prompt.'
  SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' STARSHIP_CONFIG="$ssh_config" starship prompt >/dev/null || die 'Starship could not render the SSH prompt.'
  # shellcheck disable=SC2016 # These expressions expand inside the child Bash.
  if ! env -u STARSHIP_CONFIG SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' TERM=xterm-256color bash --noprofile --rcfile /etc/bash.bashrc -ic \
    '[[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/holow-light.toml && "${PROMPT_COMMAND:-}" == *starship_precmd* ]]' \
    >/dev/null 2>&1; then
    die 'Interactive Bash did not load the headless Starship prompt.'
  fi
  # shellcheck disable=SC2016 # These expressions expand inside the child Bash.
  if ! env -u STARSHIP_CONFIG SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' TERM=xterm-256color bash --noprofile --norc -ic \
    'source /etc/profile.d/10-kmos-starship.sh; [[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/holow-light.toml && "${PROMPT_COMMAND:-}" == *starship_precmd* ]]' \
    >/dev/null 2>&1; then
    die 'SSH-style login Bash did not initialize the headless Starship prompt.'
  fi
  # shellcheck disable=SC2016 # Expressions expand inside the child Bash.
  if ! env -u STARSHIP_CONFIG -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT TERM=linux bash --noprofile --norc -ic \
    'source /etc/profile.d/10-kmos-starship.sh; [[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/quartz-headless.toml && "${PROMPT_COMMAND:-}" == *starship_precmd* ]]' \
    >/dev/null 2>&1; then
    die 'Linux console Bash did not initialize the ASCII Starship prompt.'
  fi
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
    [[ "$username" != alarm ]] || { warn 'Choose a new administrator name; alarm is the initial account to remove.'; continue; }
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
    [[ "$additional" != alarm ]] || { warn 'The initial alarm account cannot be reused.'; continue; }
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

ethernet_available() {
  local interface
  while IFS= read -r interface; do
    [[ -e "/sys/class/net/$interface" && ! -d "/sys/class/net/$interface/wireless" ]] || continue
    ip -4 -o address show dev "$interface" scope global | grep -q . && return 0
  done < <(ip -4 route show default | awk '{for (i=1; i<NF; i++) if ($i=="dev") print $(i+1)}')
  return 1
}

configure_wifi() {
  local result
  ask_yes_no 'Configure persistent Wi-Fi now?' no || return
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || { warn 'No Wi-Fi adapter detected. Ethernet remains configured.'; return; }
  if "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"; then
    info 'Wi-Fi works now with a saved profile; verify reconnecting after a real reboot before depending on it.'
    return 0
  else
    result=$?
  fi
  if ((result == 2)) && ethernet_available && ask_yes_no 'Wi-Fi was cancelled. Finish installation using Ethernet only?' no; then
    WIFI_ADAPTER=""
    warn 'Finishing with Ethernet only. Wi-Fi was NOT verified; run the Wi-Fi helper separately when ready.'
    return 0
  fi
  die 'Wi-Fi setup did not complete. Provisioning stopped without claiming a working Wi-Fi connection.'
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

stage_alarm_removal() {
  local root=${1:-}
  install -Dm0755 /dev/stdin "$root/usr/local/libexec/kmos-remove-alarm-after-boot.sh" <<'ALARM_CLEANUP'
#!/usr/bin/env bash
# Runs at the next boot if alarm owned the active installer session.
set -Eeuo pipefail
if record=$(getent passwd alarm); then
  IFS=: read -r _ _ _ _ _ home shell <<< "$record"
  if [[ "$home" != /home/alarm || "$shell" != /usr/bin/nologin ]]; then
    printf 'ERROR: alarm changed since removal was scheduled; refusing to remove it.\n' >&2
    exit 1
  fi
  userdel -r alarm
fi
if getent passwd alarm >/dev/null; then
  printf 'ERROR: alarm still exists; retry or inspect the service logs.\n' >&2
  exit 1
fi
if [[ -e /home/alarm || -L /home/alarm ]]; then
  printf 'ERROR: /home/alarm still exists; inspect it before removing anything.\n' >&2
  exit 1
fi
systemctl disable kmos-remove-alarm.service
printf 'Initial alarm account and home have been removed.\n'
ALARM_CLEANUP
  install -Dm0644 /dev/stdin "$root/etc/systemd/system/kmos-remove-alarm.service" <<'EOF'
[Unit]
Description=Remove locked initial alarm account before SSH logins
After=local-fs.target
Before=sshd.service systemd-user-sessions.service

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/kmos-remove-alarm-after-boot.sh

[Install]
WantedBy=multi-user.target
EOF
  if [[ -z "$root" ]]; then
    systemctl daemon-reload
    systemctl enable kmos-remove-alarm.service
  fi
}

remove_alarm() {
  local record
  if ! record=$(getent passwd alarm); then
    [[ ! -e /home/alarm && ! -L /home/alarm ]] || die 'alarm account is absent but /home/alarm remains; inspect it before deletion.'
    info 'Initial alarm account and home are already absent.'
    return 0
  fi
  warn 'Removing alarm also deletes /home/alarm and everything inside it, including any checkout stored there.'
  ask_yes_no 'Remove the initial alarm user and its home directory?' yes || return 0
  REMOVE_ALARM_REQUESTED=1
  ALARM_HOME=$(printf '%s\n' "$record" | awk -F: '{print $6}')
  [[ "$ALARM_HOME" == /home/alarm ]] || die 'Unexpected alarm home directory; refusing automatic removal.'
  [[ "$PRIMARY_USER" != alarm ]] || die 'Cannot remove the primary administrator account.'
  id "$PRIMARY_USER" >/dev/null || die 'Administrator account is missing; alarm will not be removed.'
  id -nG "$PRIMARY_USER" | grep -qw wheel || die 'Administrator lacks sudo; alarm will not be removed.'
  # The checkout (and current directory) may live under the home being removed.
  if [[ "$PWD" == /home/alarm || "$PWD" == /home/alarm/* ]]; then
    cd /
  fi
  if [[ "${SUDO_USER:-}" != alarm ]] && userdel -r alarm; then
    getent passwd alarm >/dev/null && die 'alarm still exists after userdel.'
    [[ ! -e "$ALARM_HOME" && ! -L "$ALARM_HOME" ]] || die "alarm home still exists: $ALARM_HOME"
    info 'Initial alarm account and home removed.'
    return 0
  fi
  if ! getent passwd alarm >/dev/null; then
    [[ ! -e "$ALARM_HOME" && ! -L "$ALARM_HOME" ]] || die "alarm home still exists: $ALARM_HOME"
    info 'Initial alarm account and home removed.'
    return 0
  fi
  # userdel cannot remove the account that owns the active installer session.
  # Lock it immediately and remove it before the next boot's SSH logins.
  usermod -L -s /usr/bin/nologin alarm || die 'Could not lock alarm; removal was not scheduled.'
  stage_alarm_removal
  ALARM_REMOVAL_PENDING=1
  warn 'alarm is locked and scheduled for removal at the next boot; it is not removed yet.'
}

configure_syncthing() {
  pacman -Q syncthing >/dev/null 2>&1 || { warn 'Syncthing is not installed; its service will be skipped.'; return; }
  ask_yes_no "Enable Syncthing for $PRIMARY_USER?" no || return
  systemctl enable --now "syncthing@$PRIMARY_USER.service"
}

install_aur_helper() {
  local helper=$1 username=$2 work_dir summary
  local -a dependencies=()
  case "$helper" in
    yay) dependencies=(base-devel go) ;;
    paru) dependencies=(base-devel rust cargo) ;;
    *) die "Unknown AUR helper: $helper" ;;
  esac
  [[ "$username" != alarm && "$username" != root ]] || die 'Build the AUR helper as the new non-root administrator, not alarm or root.'
  id "$username" >/dev/null || die "AUR build user does not exist: $username"
  id -nG "$username" | grep -qw wheel || die "$username needs sudo access for makepkg dependency installation."
  if command -v "$helper" >/dev/null 2>&1 && "$helper" --version >/dev/null 2>&1; then
    info "$helper is already installed and runnable."
    return 0
  fi
  info "Building $helper from the AUR source PKGBUILD on this AArch64 board (never ${helper}-bin)."
  printf -v summary '%s ' "${dependencies[@]}"
  info "Board build packages required: ${summary% }. Go/Rust builds can take significant disk space and time."
  ask_yes_no "Install the build packages and stage $helper?" no || { info 'AUR helper skipped; headless installation remains complete.'; return 0; }
  pacman -S --needed "${dependencies[@]}"
  work_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/kmos-aur-${helper}.XXXXXXXX") || die 'Could not create a private AUR build directory.'
  chown "$username:$username" "$work_dir"
  info "AUR build checkout: $work_dir/$helper (kept for inspection)."
  runuser -u "$username" -- git clone "https://aur.archlinux.org/$helper.git" "$work_dir/$helper" || die 'AUR clone failed; inspect the retained build directory.'
  info "AUR commit for $helper: $(runuser -u "$username" -- git -C "$work_dir/$helper" rev-parse HEAD)"
  cat "$work_dir/$helper/PKGBUILD" || die 'Cannot review the AUR PKGBUILD.'
  ask_yes_no "Review complete: build and install $helper as $username?" no || { info 'Build declined; source checkout kept for review.'; return 0; }
  # shellcheck disable=SC2016 # The build path expands in the non-root child shell.
  runuser -u "$username" -- bash -c 'cd -- "$1" && makepkg -si --needed --cleanbuild' _ "$work_dir/$helper" || die "AUR source build failed; inspect $work_dir/$helper. Headless KMOS remains installed."
  if ! command -v "$helper" >/dev/null 2>&1 || ! "$helper" --version >/dev/null 2>&1; then
    die "$helper was not runnable after installation."
  fi
  info "$helper built from source and verified on this AArch64 board."
}

offer_aur_helper() {
  local choice
  ask_yes_no 'Install an optional AUR helper from source now?' no || return 0
  read -r -p 'Choose AUR helper [paru/yay/skip] (skip): ' choice
  case "${choice:-skip}" in
    paru|yay) install_aur_helper "$choice" "$PRIMARY_USER" ;;
    skip) info 'AUR helper skipped.' ;;
    *) die 'Choose paru, yay, or skip. Headless KMOS remains installed.' ;;
  esac
}

verify_installation() {
  local package
  info 'Verifying configuration.'
  for package in iwd nano openssh starship sudo "${AVAILABLE_PACKAGES[@]}"; do
    pacman -Q "$package" >/dev/null || die "Expected package missing: $package"
  done
  id "$PRIMARY_USER" >/dev/null
  id -nG "$PRIMARY_USER" | grep -qw wheel || die "$PRIMARY_USER is not in the wheel group."
  sudo -l -U "$PRIMARY_USER" >/dev/null
  [[ $(cat /etc/hostname) == "$HOSTNAME_VALUE" ]] || die 'Hostname does not match.'
  systemctl is-enabled sshd.service systemd-networkd.service systemd-resolved.service >/dev/null
  [[ -f /usr/share/kmos/starship-presets/quartz-headless.toml ]] || die 'Headless Starship preset is missing.'
  verify_headless_prompt
  if ((REMOVE_ALARM_REQUESTED)); then
    if ((ALARM_REMOVAL_PENDING)); then
      systemctl is-enabled --quiet kmos-remove-alarm.service || die 'alarm removal is not enabled for the next boot.'
      [[ $(getent passwd alarm | awk -F: '{print $7}') == /usr/bin/nologin ]] || die 'alarm is not blocked from logging in before removal.'
    else
      getent passwd alarm >/dev/null && die 'alarm was requested for removal but still exists.'
      [[ ! -e "$ALARM_HOME" && ! -L "$ALARM_HOME" ]] || die "alarm home still exists: $ALARM_HOME"
    fi
  fi
  if [[ -n "$WIFI_ADAPTER" ]]; then
    systemctl is-enabled iwd.service >/dev/null
    iwctl station "$WIFI_ADAPTER" show || warn 'Could not query Wi-Fi status.'
  fi
}

main() {
  REPOSITORY_DIR=$(find_local_repository)
  require_root_and_arm
  info "KMOS checkout commit: $(git -C "$REPOSITORY_DIR" rev-parse HEAD)"
  if [[ -n $(git -C "$REPOSITORY_DIR" status --porcelain --untracked-files=no) ]]; then
    warn 'This checkout has local changes; the files used may differ from the displayed commit.'
  fi
  info 'Arch Linux ARM will be updated and configured from this KMOS checkout.'
  ask_yes_no 'Continue with provisioning?' no || die 'Cancelled without modifying the system.'
  initialize_pacman
  install_kmos_packages "$REPOSITORY_DIR"
  install_kappa_mono_fonts
  configure_kmos_terminal "$REPOSITORY_DIR"
  configure_identity
  create_administrator
  configure_ssh
  configure_networkd
  configure_swap
  configure_syncthing
  remove_alarm
  info 'Quartz64 KDE provisioning is disabled until it can be validated on physical hardware.'
  info 'Wi-Fi is not configured during headless provisioning; Ethernet remains in use. The Wi-Fi helper is separate.'
  verify_installation
  info 'KMOS headless provisioning complete.'
  offer_aur_helper
  info 'Reboot when convenient, then check networking and any graphical session locally.'
}

board_maintenance() {
  local operation=$1 answer repository_dir
  require_root_and_arm "$operation"
  repository_dir=$(find_local_repository)
  REPOSITORY_DIR=$repository_dir
  case "$operation" in
    repair-prompt)
      if ! pacman -Q starship >/dev/null 2>&1; then
        warn 'Starship is missing. Installing it requires a full Arch Linux ARM update, which may update the board kernel.'
        read -r -p 'Backed up the working card and continue with pacman -Syu starship? [y/N]: ' answer
        [[ "$answer" =~ ^[Yy]$ ]] || die 'Cancelled without updating packages.'
        pacman -Syu --needed starship
      fi
      configure_kmos_terminal "$repository_dir"
      verify_headless_prompt
      info 'Headless Starship prompt repaired. Start a new SSH session to check it.'
      ;;
    fonts)
      install_kappa_mono_fonts
      info 'Kappa Mono is installed on the Quartz64. SSH glyphs depend on the client terminal font.'
      ;;
    aur|remove-alarm)
      PRIMARY_USER=${SUDO_USER:-}
      if [[ -z "$PRIMARY_USER" || "$PRIMARY_USER" == root || "$PRIMARY_USER" == alarm ]]; then
        read -r -p 'Name of your new wheel administrator (not alarm): ' PRIMARY_USER
      fi
      if [[ "$operation" == aur ]]; then
        offer_aur_helper
      else
        remove_alarm
        if ((REMOVE_ALARM_REQUESTED == 0)); then
          info 'alarm removal was declined; no account was removed.'
        elif ((ALARM_REMOVAL_PENDING)); then
          info 'After reboot, check: getent passwd alarm (must produce no output).'
        else
          info 'alarm removal verified.'
        fi
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-provision}" in
    -h|--help) usage ;;
    provision) (($# <= 1)) || die 'Unexpected arguments. Run --help for commands.'; main ;;
    repair-prompt|fonts|aur|remove-alarm)
      (($# == 1)) || die 'Unexpected arguments. Run --help for commands.'
      board_maintenance "$1"
      ;;
    *) die "Unknown command: $1. Run --help for commands." ;;
  esac
fi
