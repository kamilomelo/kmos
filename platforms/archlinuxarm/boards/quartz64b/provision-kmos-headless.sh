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
WIFI_BACKEND=""
WIFI_BOOTSTRAP_IWD=0
WIFI_REBOOT_UNSAFE=0
REMOVE_ALARM_REQUESTED=0
ALARM_REMOVAL_PENDING=0
AVAILABLE_PACKAGES=()
SKIPPED_PACKAGES=()
KDE_PACKAGES=()
KDE_METAPACKAGES=()
KDE_PROFILE=""

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
Usage: ./provision-kmos-headless.sh [provision|kde|repair-prompt|fonts|aur|remove-alarm|wifi-fallback]

Run this script from a complete local KMOS Git checkout on an already booted
Quartz64. Optionally configures Wi-Fi before package updates with the standalone
helper. Uses the checkout's package manifests, assets and helper scripts.
No argument provisions KMOS and offers KDE or headless mode at the end. The
kde command offers KDE on an already-provisioned board without repeating user,
swap or Wi-Fi setup. Other commands repair the prompt, install Kappa Mono,
choose an AUR helper, remove alarm, or switch Wi-Fi to wpa_supplicant.
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

kde_graphics_available() {
  local device
  for device in /dev/dri/card[0-9]*; do
    [[ -e "$device" ]] && return 0
  done
  return 1
}

kde_network_conflict() {
  # The x86 KDE manifest includes NM and plasma-nm; neither may take over the
  # working Quartz64 wpa_supplicant/networkd adapter at the next boot.
  case "$1" in
    networkmanager|networkmanager-openvpn|plasma-nm|plasma-login-manager) return 0 ;;
    *) return 1 ;;
  esac
}

offer_kde_desktop() {
  local profile package summary="" missing_summary="" excluded_summary="" metapackage
  local -a available=() installed=() missing=() excluded=()
  local -a full=(kmos-audio kmos-browsers kmos-devices kmos-docs kmos-filesystems kmos-fonts kmos-graphics kmos-kde-base kmos-kde-multimedia kmos-kde-utils kmos-maintenance kmos-network kmos-privacy)
  info 'Your base system is ready. Select no to keep it headless.'
  ask_yes_no 'Do you want to install a desktop?' yes || return 0
  if ! kde_graphics_available; then
    warn 'No DRM graphics card was found; a KDE session may not render on this board.'
    ask_yes_no 'Try KDE without detected DRM graphics?' no || return 0
  fi
  if systemctl is-enabled --quiet NetworkManager.service || systemctl is-active --quiet NetworkManager.service; then
    die 'NetworkManager is already enabled or active. Review its ownership before installing KDE alongside wpa_supplicant/networkd.'
  fi
  read -r -p 'KDE profile [full/noapps] (full): ' profile
  profile=${profile:-full}
  KDE_PACKAGES=()
  KDE_METAPACKAGES=()
  case "$profile" in
    noapps) resolve_kde_metapackage kmos-kde-noapps ;;
    full)
      for metapackage in "${full[@]}"; do resolve_kde_metapackage "$metapackage"; done
      ;;
    *) die 'Invalid KDE profile; the headless system remains available.' ;;
  esac
  for package in "${KDE_PACKAGES[@]}"; do
    if kde_network_conflict "$package"; then
      excluded+=("$package")
    elif pacman -Si "$package" >/dev/null 2>&1; then
      available+=("$package")
    elif pacman -Q "$package" >/dev/null 2>&1; then
      installed+=("$package")
    else
      missing+=("$package")
    fi
  done
  if ((${#excluded[@]} > 0)); then
    printf -v excluded_summary '%s ' "${excluded[@]}"
    info "Excluded to preserve wpa_supplicant/networkd and SDDM: ${excluded_summary% }."
  fi
  for package in plasma-desktop plasma-workspace kwin sddm; do
    if ! printf '%s\n' "${available[@]}" "${installed[@]}" | grep -Fxq "$package"; then
      warn "Essential KDE component unavailable on ARM: $package. Keeping the system headless."
      return 0
    fi
  done
  if ((${#missing[@]} > 0)); then
    printf -v missing_summary '%s ' "${missing[@]}"
    warn "Unavailable ARM packages: ${missing_summary% }."
    info 'No x86 binaries or unreviewed AUR replacements will be installed.'
    ask_yes_no 'Skip these packages and continue with KDE?' yes || { info 'KDE deferred; the headless system remains available.'; return 0; }
  fi
  if ((${#available[@]} > 0)); then
    printf -v summary '%s ' "${available[@]}"
    info "KDE $profile will install: ${summary% }"
  else
    info "KDE $profile packages are already installed."
  fi
  ask_yes_no 'Install KDE on the Quartz64?' no || return 0
  if ((${#available[@]} > 0)); then
    pacman -S --needed --noconfirm "${available[@]}" || die 'KDE packages could not be installed; the headless boot target was not changed.'
  fi
  if systemctl is-enabled --quiet NetworkManager.service || systemctl is-active --quiet NetworkManager.service; then
    die 'NetworkManager became enabled or active during KDE installation; resolve the competing network manager before changing the boot target.'
  fi
  for package in plasma-desktop plasma-workspace kwin sddm; do
    pacman -Q "$package" >/dev/null || die "KDE component missing after installation: $package"
  done
  configure_kde_terminal "$REPOSITORY_DIR"
  # Only SDDM takes the new graphical target; networking stays with networkd
  # and wpa_supplicant. Never enable NM or a second Wi-Fi manager here.
  systemctl enable sddm.service
  systemctl set-default graphical.target
  systemctl is-enabled --quiet sddm.service || die 'SDDM was not enabled.'
  [[ $(systemctl get-default) == graphical.target ]] || die 'Graphical boot target was not selected.'
  KDE_PROFILE=$profile
  info 'KDE installed. NetworkManager remains disabled; verify graphics on a real reboot.'
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

bootstrap_network() {
  # Only bring up temporary Wi-Fi when no Ethernet connection can update ARM.
  ethernet_available && return 0
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || die 'No Ethernet connection or Wi-Fi adapter available for package updates.'
  if systemctl is-enabled --quiet "wpa_supplicant@$WIFI_ADAPTER.service"; then
    "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh" --check \
      || die 'Existing wpa_supplicant connection cannot update packages; inspect it before provisioning.'
    WIFI_BACKEND=wpa
    return 0
  fi
  info 'No Ethernet route. Using iwd temporarily for package updates; persistent Wi-Fi is offered at the end.'
  if "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"; then
    WIFI_BACKEND=iwd
    WIFI_BOOTSTRAP_IWD=1
    info 'Temporary iwd connection verified for package updates.'
    return 0
  fi
  die 'No network is available for package updates; provisioning stopped.'
}

configure_persistent_wifi() {
  if ! ask_yes_no 'Configure persistent Wi-Fi with wpa_supplicant now?' yes; then
    info 'wpa_supplicant setup skipped; existing Wi-Fi configuration was not replaced.'
    if ((WIFI_BOOTSTRAP_IWD)); then
      systemctl disable iwd.service || die 'Could not disable the temporary iwd boot service.'
      warn 'Temporary iwd will not start after reboot. Connect Ethernet or configure persistent Wi-Fi before rebooting.'
      ethernet_available || WIFI_REBOOT_UNSAFE=1
    fi
    WIFI_BACKEND=""
    return 0
  fi
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || { warn 'No Wi-Fi adapter found; persistent Wi-Fi was not configured.'; return 0; }
  if systemctl is-enabled --quiet "wpa_supplicant@$WIFI_ADAPTER.service"; then
    "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh" --check \
      || die 'Existing wpa_supplicant Wi-Fi could not be verified; it was not overwritten.'
  else
    pacman -S --needed --noconfirm wpa_supplicant
    "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" --wpa-fallback \
      || die 'wpa_supplicant was not verified; inspect the rollback before rebooting.'
  fi
  WIFI_BACKEND=wpa
  info 'wpa_supplicant is configured for Wi-Fi boot; verify a real reboot before relying on it.'
}

disable_active_swapfile() {
  local swaps_file=${1:-/proc/swaps} active
  active=$(awk 'NR > 1 && $1 == "/swapfile" { print "active"; exit }' "$swaps_file") \
    || die "Could not inspect active swap devices: $swaps_file"
  if [[ "$active" == active ]]; then
    swapoff /swapfile || die 'Could not disable the active /swapfile; refusing to replace it.'
  fi
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
  disable_active_swapfile
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
  userdel alarm
fi
if getent passwd alarm >/dev/null; then
  printf 'ERROR: alarm still exists; retry or inspect the service logs.\n' >&2
  exit 1
fi
systemctl disable kmos-remove-alarm.service
printf 'Initial alarm account removed; /home/alarm retained for manual review.\n'
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
  local record alarm_home
  if ! record=$(getent passwd alarm); then
    info 'Initial alarm account is already absent; any old home directory is preserved.'
    return 0
  fi
  REMOVE_ALARM_REQUESTED=1
  alarm_home=$(printf '%s\n' "$record" | awk -F: '{print $6}')
  [[ "$alarm_home" == /home/alarm ]] || die 'Unexpected alarm home directory; refusing automatic removal.'
  [[ "$PRIMARY_USER" != alarm ]] || die 'Cannot remove the primary administrator account.'
  id "$PRIMARY_USER" >/dev/null || die 'Administrator account is missing; alarm will not be removed.'
  id -nG "$PRIMARY_USER" | grep -qw wheel || die 'Administrator lacks sudo; alarm will not be removed.'
  # Remove the login without deleting files or a checkout under /home/alarm.
  if [[ "${SUDO_USER:-}" != alarm ]] && userdel alarm; then
    getent passwd alarm >/dev/null && die 'alarm still exists after userdel.'
    info 'Initial alarm account removed; /home/alarm retained for manual review.'
    return 0
  fi
  if ! getent passwd alarm >/dev/null; then
    info 'Initial alarm account removed; /home/alarm retained for manual review.'
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
  pacman -Q syncthing >/dev/null 2>&1 || { warn 'Syncthing is not installed; its service will be skipped.'; return 0; }
  ask_yes_no "Enable Syncthing for $PRIMARY_USER?" no || { info 'Syncthing skipped; continuing installation.'; return 0; }
  if ! systemctl enable --now "syncthing@$PRIMARY_USER.service"; then
    warn "Could not enable or start syncthing@$PRIMARY_USER.service; continuing installation. Check: systemctl status syncthing@$PRIMARY_USER.service"
  fi
  return 0
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
  pacman -S --needed --noconfirm "${dependencies[@]}"
  work_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/kmos-aur-${helper}.XXXXXXXX") || die 'Could not create a private AUR build directory.'
  chown "$username:$username" "$work_dir"
  info "AUR build checkout: $work_dir/$helper (kept for inspection)."
  runuser -u "$username" -- git clone "https://aur.archlinux.org/$helper.git" "$work_dir/$helper" || die 'AUR clone failed; inspect the retained build directory.'
  info "AUR commit for $helper: $(runuser -u "$username" -- git -C "$work_dir/$helper" rev-parse HEAD)"
  [[ -r "$work_dir/$helper/PKGBUILD" ]] || die 'AUR PKGBUILD is missing; refusing to build.'
  # shellcheck disable=SC2016 # The build path expands in the non-root child shell.
  runuser -u "$username" -- bash -c 'cd -- "$1" && makepkg -si --noconfirm --needed --cleanbuild' _ "$work_dir/$helper" || die "AUR source build failed; inspect $work_dir/$helper. Headless KMOS remains installed."
  if ! command -v "$helper" >/dev/null 2>&1 || ! "$helper" --version >/dev/null 2>&1; then
    die "$helper was not runnable after installation."
  fi
  info "$helper built from source and verified on this AArch64 board."
}

offer_aur_helper() {
  local choice
  ask_yes_no 'Install an optional AUR helper from source now?' yes || return 0
  info 'AUR helper options'
  info 'Source builds install board packages: paru needs base-devel, rust and cargo; yay needs base-devel and go.'
  printf '  1) paru\n  2) yay\n' >&2
  while true; do
    read -r -p 'Select [1-2] (default: 1): ' choice
    case "${choice:-1}" in
      1) install_aur_helper paru "$PRIMARY_USER"; return ;;
      2) install_aur_helper yay "$PRIMARY_USER"; return ;;
      *) warn 'Invalid selection.' ;;
    esac
  done
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
    fi
  fi
  if [[ "$WIFI_BACKEND" == iwd ]]; then
    systemctl is-enabled iwd.service >/dev/null
    iwctl station "$WIFI_ADAPTER" show || warn 'Could not query Wi-Fi status.'
  elif [[ "$WIFI_BACKEND" == wpa ]]; then
    systemctl is-enabled "wpa_supplicant@$WIFI_ADAPTER.service" >/dev/null
    wpa_cli -i "$WIFI_ADAPTER" status || warn 'Could not query wpa_supplicant status.'
  fi
}

verify_runtime_network() {
  local service
  for service in sshd.service systemd-networkd.service systemd-resolved.service; do
    systemctl is-active --quiet "$service" || die "$service is not active. Fix networking/SSH before rebooting."
  done
  if [[ "$WIFI_BACKEND" == wpa ]]; then
    systemctl is-active --quiet "wpa_supplicant@$WIFI_ADAPTER.service" \
      || die 'wpa_supplicant is not active. Do not reboot expecting Wi-Fi.'
    "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh" --check \
      || die 'wpa_supplicant Wi-Fi was lost during provisioning. Do not reboot expecting Wi-Fi.'
  fi
  [[ -n $(ip -4 route show default) ]] || die 'No IPv4 default route. Fix networking before rebooting.'
  command -v curl >/dev/null 2>&1 || die 'curl is needed to verify live internet access before rebooting.'
  if ! curl --fail --silent --show-error --location --connect-timeout 5 --max-time 15 --output /dev/null https://github.com/; then
    die 'Live internet access could not be verified after provisioning. Keep Ethernet connected; diagnose the network before rebooting.'
  fi
  info 'SSH and network services, IPv4 default route, and live internet access verified before reboot.'
}

countdown_or_reboot() {
  local fd=$1 remaining status
  for ((remaining=10; remaining>0; remaining--)); do
    printf '\rRebooting in %2d seconds. Press any key to stay... ' "$remaining" >&2
    if IFS= read -r -s -n 1 -t 1 -u "$fd"; then
      printf '\nStaying in the current session. Reboot manually when ready.\n' >&2
      return 0
    else
      status=$?
      if ((status < 128)); then
        printf '\n' >&2
        warn 'Terminal input closed; automatic reboot skipped. Reboot manually when ready.'
        return 0
      fi
    fi
  done
  printf '\nRebooting now.\n' >&2
  systemctl reboot || die 'Automatic reboot failed. Reboot manually when ready.'
}

finish_installation() {
  local fd
  printf '\n+-------------------------------------+\n' >&2
  if [[ -n "$KDE_PROFILE" ]]; then
    printf '| KMOS KDE installation complete      |\n' >&2
  else
    printf '| KMOS headless installation complete |\n' >&2
  fi
  printf '+-------------------------------------+\n' >&2
  if ((WIFI_REBOOT_UNSAFE)); then
    warn 'Automatic reboot skipped: persistent Wi-Fi was declined and Ethernet is unavailable. Reboot only after arranging a recovery connection.'
    return 0
  fi
  if ! { exec {fd}</dev/tty; } 2>/dev/null; then
    warn 'No interactive terminal; automatic reboot skipped. Reboot manually when ready.'
    return 0
  fi
  countdown_or_reboot "$fd"
  exec {fd}<&-
}

main() {
  REPOSITORY_DIR=$(find_local_repository)
  require_root_and_arm
  info "KMOS checkout commit: $(git -C "$REPOSITORY_DIR" rev-parse HEAD)"
  if [[ -n $(git -C "$REPOSITORY_DIR" status --porcelain --untracked-files=no) ]]; then
    warn 'This checkout has local changes; the files used may differ from the displayed commit.'
  fi
  info 'Arch Linux ARM will be updated and configured from this KMOS checkout.'
  ask_yes_no 'Continue with provisioning and the full Arch Linux ARM update?' yes || die 'Cancelled without modifying the system.'
  bootstrap_network
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
  verify_installation
  configure_persistent_wifi
  offer_kde_desktop
  if [[ "$KDE_PROFILE" != noapps ]]; then offer_aur_helper; fi
  verify_runtime_network
  finish_installation
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
    kde)
      warn 'KDE installation requires a full Arch Linux ARM update, which may update the board kernel.'
      ask_yes_no 'Update Arch Linux ARM and offer KDE?' no || die 'Cancelled without changing the desktop.'
      pacman -Syu --needed --noconfirm
      offer_kde_desktop
      verify_runtime_network
      ;;
    wifi-fallback)
      if ! pacman -Q wpa_supplicant >/dev/null 2>&1; then
        warn 'Installing ARM wpa_supplicant needs a full package update and may update the board kernel.'
        ask_yes_no 'Update Arch Linux ARM and install wpa_supplicant?' no \
          || die 'Cancelled without changing the Wi-Fi backend.'
        pacman -Syu --needed --noconfirm wpa_supplicant
      fi
      "$repository_dir/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" --wpa-fallback
      info 'wpa_supplicant fallback configured; a real reboot test is still required.'
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
          info 'alarm account was already absent.'
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
    repair-prompt|fonts|aur|remove-alarm|wifi-fallback|kde)
      (($# == 1)) || die 'Unexpected arguments. Run --help for commands.'
      board_maintenance "$1"
      ;;
    *) die "Unknown command: $1. Run --help for commands." ;;
  esac
fi
