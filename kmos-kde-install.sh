#!/bin/bash
# KMOS KDE Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
METAPACKAGE_ROOT_DIR="$SCRIPT_DIR/metapackages"
METAPACKAGE_RAW_ROOT_URL="https://raw.githubusercontent.com/kamilomelo/KMOS/main/metapackages"
KDE_POST_INSTALLER_URL="https://raw.githubusercontent.com/kamilomelo/KMOS/main/kmos-kde-post.sh"
KDE_PROFILE="${KMOS_KDE_PROFILE:-full}"
PRUNE_LIST_FILE="$SCRIPT_DIR/assets/package-prune/kde-remove-packages.txt"

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
FINAL_SUCCESS_ICON="✔"

KDE_PACKAGES=()
declare -a RESOLVED_METAPACKAGES=()
declare -a SELECTED_METAPACKAGES=()

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_HEADER=$'\033[34m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${KMOS_ASCII_UI:-0}}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

info() {
  printf '%b%s%b\n' "${UI_INFO}${UI_BOLD}" "$*" "$UI_RESET" >&2
}

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

final_success() {
  printf '\n%b%s%b %s\n\n' "$UI_SUCCESS" "$FINAL_SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

detail() {
  local key="$1"
  local value="$2"
  printf '  %b%-14s%b %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value" >&2
}

print_banner() {
  printf '\n' >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "KMOS KDE Install" "$UI_RESET" >&2
  log "Lean KDE Plasma desktop layer for an existing KMOS minimal install."
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  while true; do
    if [[ "$default" == "yes" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    elif [[ "$default" == "no" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [y/n]: " answer
    fi

    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root from the Arch ISO."
}

require_tools() {
  local missing=()
  local tools=(arch-chroot basename cat chmod find findmnt grep head install mkdir sed sort)
  local tool=""

  for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        shift
        [[ $# -gt 0 ]] || die "--target requires a mount point."
        MOUNT_POINT="$1"
        ;;
      --profile)
        shift
        [[ $# -gt 0 ]] || die "--profile requires a value."
        KDE_PROFILE="$1"
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

verify_target() {
  findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || die "$MOUNT_POINT is not mounted."
  [[ -d "$MOUNT_POINT/etc" ]] || die "$MOUNT_POINT does not look like an installed system."
}

select_kde_metapackages() {
  case "$KDE_PROFILE" in
    test)
      SELECTED_METAPACKAGES=(
        kmos-kde-test
      )
      ;;
    full)
      SELECTED_METAPACKAGES=(
        kmos-audio
        kmos-browsers
        kmos-devices
        kmos-docs
        kmos-filesystems
        kmos-fonts
        kmos-graphics
        kmos-kde-base
        kmos-kde-multimedia
        kmos-kde-utils
        kmos-maintenance
        kmos-network
        kmos-privacy
      )
      ;;
    *)
      die "Unknown KDE profile: $KDE_PROFILE"
      ;;
  esac
}

load_kde_metapackages() {
  local metapackage=""
  local pkgbuild=""

  KDE_PACKAGES=()
  RESOLVED_METAPACKAGES=()
  for metapackage in "${SELECTED_METAPACKAGES[@]}"; do
    pkgbuild="$(get_metapackage_pkgbuild "$metapackage")"
    resolve_metapackage_depends "$pkgbuild"
  done
  mapfile -t KDE_PACKAGES < <(printf '%s\n' "${KDE_PACKAGES[@]}" | sort -u)
  [[ ${#KDE_PACKAGES[@]} -gt 0 ]] || die "KDE metapackage has no dependencies."

  detail "Profile" "$KDE_PROFILE"
  detail "Metapackages" "${SELECTED_METAPACKAGES[*]}"
  detail "Packages" "${#KDE_PACKAGES[@]}"
}

append_unique() {
  local -n values_ref="$1"
  local value="$2"
  local current=""

  for current in "${values_ref[@]}"; do
    [[ "$current" == "$value" ]] && return 0
  done

  values_ref+=("$value")
}

metapackage_relative_path_for_name() {
  case "$1" in
    kmos-audio) printf 'desktop-shared/audio/PKGBUILD\n' ;;
    kmos-browsers) printf 'desktop-shared/browsers/PKGBUILD\n' ;;
    kmos-deprecated) printf 'desktop-shared/deprecated/PKGBUILD\n' ;;
    kmos-devices) printf 'desktop-shared/devices/PKGBUILD\n' ;;
    kmos-docs) printf 'desktop-shared/docs/PKGBUILD\n' ;;
    kmos-filesystems) printf 'desktop-shared/filesystems/PKGBUILD\n' ;;
    kmos-fonts) printf 'desktop-shared/fonts/PKGBUILD\n' ;;
    kmos-graphics) printf 'desktop-shared/graphics/PKGBUILD\n' ;;
    kmos-kde-full) printf 'desktop-shared/full/PKGBUILD\n' ;;
    kmos-maintenance) printf 'desktop-shared/maintenance/PKGBUILD\n' ;;
    kmos-network) printf 'desktop-shared/network/PKGBUILD\n' ;;
    kmos-privacy) printf 'desktop-shared/privacy/PKGBUILD\n' ;;
    kmos-kde-base) printf 'kde/base/PKGBUILD\n' ;;
    kmos-kde-multimedia) printf 'kde/multimedia/PKGBUILD\n' ;;
    kmos-kde-plasma) printf 'kde/base/plasma/PKGBUILD\n' ;;
    kmos-kde-test) printf 'kde/test/PKGBUILD\n' ;;
    kmos-kde-utils) printf 'kde/utils/PKGBUILD\n' ;;
    *)
      return 1
      ;;
  esac
}

get_metapackage_pkgbuild() {
  local pkgname="$1"
  local relative_path="${2:-}"
  local local_path=""
  local remote_url=""
  local fetched_path=""

  if [[ -z "$relative_path" ]]; then
    relative_path="$(metapackage_relative_path_for_name "$pkgname")" || die "Unknown KMOS metapackage: $pkgname"
  fi

  local_path="$METAPACKAGE_ROOT_DIR/$relative_path"
  if [[ -r "$local_path" ]]; then
    printf '%s\n' "$local_path"
    return 0
  fi

  remote_url="$METAPACKAGE_RAW_ROOT_URL/$relative_path"
  fetched_path="/tmp/${pkgname}.PKGBUILD"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$remote_url" -o "$fetched_path" || die "Could not fetch KMOS metapackage: $pkgname"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$fetched_path" "$remote_url" || die "Could not fetch KMOS metapackage: $pkgname"
  else
    die "Metapackage $pkgname not found locally and neither curl nor wget is available."
  fi

  printf '%s\n' "$fetched_path"
}

resolve_metapackage_depends() {
  local pkgbuild="$1"
  local pkgname=""
  local dependency=""
  local -a depends=()
  local dep_pkgbuild=""

  pkgname="$(source "$pkgbuild"; printf '%s\n' "$pkgname")"
  [[ -n "$pkgname" ]] || die "Could not read pkgname from $pkgbuild"

  for dependency in "${RESOLVED_METAPACKAGES[@]}"; do
    [[ "$dependency" == "$pkgname" ]] && return 0
  done
  RESOLVED_METAPACKAGES+=("$pkgname")

  mapfile -t depends < <(source "$pkgbuild"; printf '%s\n' "${depends[@]}")

  for dependency in "${depends[@]}"; do
    [[ -n "$dependency" ]] || continue
    if [[ "$dependency" == kmos-* ]]; then
      dep_pkgbuild="$(get_metapackage_pkgbuild "$dependency")"
      resolve_metapackage_depends "$dep_pkgbuild"
    else
      append_unique KDE_PACKAGES "$dependency"
    fi
  done
}

install_kde_packages() {
  arch-chroot "$MOUNT_POINT" pacman -S --needed --noconfirm "${KDE_PACKAGES[@]}"
  success "KDE packages installed."
}

install_kde_assets() {
  local metapackage=""
  local pkgbuild=""
  local relative_path=""

  for metapackage in "${SELECTED_METAPACKAGES[@]}"; do
    relative_path="$(metapackage_relative_path_for_name "$metapackage")" || continue
    pkgbuild="$(get_metapackage_pkgbuild "$metapackage" "$relative_path")"
    install -Dm0644 "$pkgbuild" "$MOUNT_POINT/usr/share/kmos/metapackages/$relative_path"
  done
}

remove_kwallet_helpers() {
  local package=""
  local installed=()

  for package in kwallet-pam kwalletmanager ksshaskpass; do
    if arch-chroot "$MOUNT_POINT" pacman -Q "$package" >/dev/null 2>&1; then
      installed+=("$package")
    fi
  done

  if [[ ${#installed[@]} -gt 0 ]]; then
    arch-chroot "$MOUNT_POINT" pacman -Rns --noconfirm "${installed[@]}" || warn "Could not remove optional KWallet helper packages."
  fi
}

remove_unwanted_packages() {
  local package=""
  local line=""
  local installed=()
  local remove_list=()

  if [[ -f "$PRUNE_LIST_FILE" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -n "$line" ]] || continue
      remove_list+=("$line")
    done < "$PRUNE_LIST_FILE"
  else
    warn "Prune list not found: $PRUNE_LIST_FILE"
  fi

  for package in "${remove_list[@]}"; do
    if arch-chroot "$MOUNT_POINT" pacman -Q "$package" >/dev/null 2>&1; then
      installed+=("$package")
    fi
  done

  if [[ ${#installed[@]} -gt 0 ]]; then
    arch-chroot "$MOUNT_POINT" pacman -Rns --noconfirm "${installed[@]}" || warn "Could not remove one or more unwanted packages: ${installed[*]}"
    success "Removed unwanted packages when present: ${installed[*]}"
  fi
}

write_kwallet_config() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'KWALLETRC'
[Wallet]
Enabled=false
First Use=false

[org.freedesktop.secrets]
apiEnabled=false
KWALLETRC
}

disable_kwallet() {
  local home_dir=""
  local username=""

  remove_kwallet_helpers
  write_kwallet_config "$MOUNT_POINT/etc/xdg/kwalletrc"
  write_kwallet_config "$MOUNT_POINT/etc/skel/.config/kwalletrc"
  write_kwallet_config "$MOUNT_POINT/root/.config/kwalletrc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_kwallet_config "$home_dir/.config/kwalletrc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/kwalletrc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "KWallet disabled by default."
}

read_wpa_value() {
  local key="$1"
  local file="$2"

  sed -n "s/^[[:space:]]*$key=\"\\(.*\\)\"[[:space:]]*$/\\1/p" "$file" | sed 's/\\"/"/g; s/\\\\/\\/g' | head -n 1
}

write_nm_connection() {
  local interface="$1"
  local ssid="$2"
  local psk="$3"
  local hidden="$4"
  local uuid=""
  local connection_file="$MOUNT_POINT/etc/NetworkManager/system-connections/kmos-$interface.nmconnection"

  uuid="$(cat /proc/sys/kernel/random/uuid)"
  install -d -m 0700 "$MOUNT_POINT/etc/NetworkManager/system-connections"

  {
    printf '[connection]\n'
    printf 'id=KMOS Wi-Fi %s\n' "$ssid"
    printf 'uuid=%s\n' "$uuid"
    printf 'type=wifi\n'
    printf 'interface-name=%s\n' "$interface"
    printf 'autoconnect=true\n'
    printf '\n'
    printf '[wifi]\n'
    printf 'mode=infrastructure\n'
    printf 'ssid=%s\n' "$ssid"
    [[ "$hidden" == "1" ]] && printf 'hidden=true\n'
    printf '\n'
    printf '[wifi-security]\n'
    printf 'auth-alg=open\n'
    printf 'key-mgmt=wpa-psk\n'
    printf 'psk=%s\n' "$psk"
    printf '\n'
    printf '[ipv4]\n'
    printf 'method=auto\n'
    printf '\n'
    printf '[ipv6]\n'
    printf 'method=auto\n'
  } > "$connection_file"

  chmod 600 "$connection_file"
}

migrate_wifi_to_networkmanager() {
  local conf=""
  local interface=""
  local ssid=""
  local psk=""
  local hidden="0"
  local migrated=0

  for conf in "$MOUNT_POINT"/etc/wpa_supplicant/wpa_supplicant-*.conf; do
    [[ -e "$conf" ]] || continue
    interface="${conf##*/wpa_supplicant-}"
    interface="${interface%.conf}"
    ssid="$(read_wpa_value ssid "$conf")"
    psk="$(read_wpa_value psk "$conf")"
    hidden="0"
    grep -q '^[[:space:]]*scan_ssid=1' "$conf" && hidden="1"

    if [[ -z "$interface" || -z "$ssid" || -z "$psk" ]]; then
      warn "Could not migrate Wi-Fi config: $conf"
      continue
    fi

    write_nm_connection "$interface" "$ssid" "$psk" "$hidden"
    arch-chroot "$MOUNT_POINT" systemctl disable "wpa_supplicant@$interface.service" "dhcpcd@$interface.service" >/dev/null 2>&1 || true
    migrated=1
  done

  if ((migrated == 1)); then
    success "Wi-Fi migrated to NetworkManager system connection."
  else
    warn "No existing Wi-Fi config was migrated to NetworkManager."
  fi
}

enable_kde_services() {
  if arch-chroot "$MOUNT_POINT" pacman -Q networkmanager >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl disable dhcpcd.service >/dev/null 2>&1 || true
    arch-chroot "$MOUNT_POINT" systemctl enable NetworkManager.service
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q sddm >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl enable sddm.service
    arch-chroot "$MOUNT_POINT" systemctl set-default graphical.target >/dev/null 2>&1 || true
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q bluez >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl enable bluetooth.service
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q cups >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl enable cups.service
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q packagekit >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl enable packagekit.service
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q pipewire >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl --global enable pipewire.socket
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q pipewire-pulse >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl --global enable pipewire-pulse.socket
  fi

  if arch-chroot "$MOUNT_POINT" pacman -Q wireplumber >/dev/null 2>&1; then
    arch-chroot "$MOUNT_POINT" systemctl --global enable wireplumber.service
  fi

  success "Desktop services enabled."
}

run_kde_post_installer() {
  local local_installer="$SCRIPT_DIR/kmos-kde-post.sh"
  local fetched_installer="/tmp/kmos-kde-post.sh"

  if [[ -f "$local_installer" ]]; then
    bash "$local_installer" --target "$MOUNT_POINT" --profile "$KDE_PROFILE"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$KDE_POST_INSTALLER_URL" -o "$fetched_installer" || die "Could not fetch KDE post installer."
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$fetched_installer" "$KDE_POST_INSTALLER_URL" || die "Could not fetch KDE post installer."
  else
    die "KDE post installer not found locally and neither curl nor wget is available."
  fi

  bash "$fetched_installer" --target "$MOUNT_POINT" --profile "$KDE_PROFILE"
}

main() {
  init_ui
  parse_args "$@"
  print_banner
  require_root
  require_tools
  verify_target
  select_kde_metapackages
  load_kde_metapackages
  install_kde_packages
  remove_unwanted_packages
  install_kde_assets
  disable_kwallet
  migrate_wifi_to_networkmanager
  enable_kde_services
  run_kde_post_installer
  final_success "KDE desktop layer installed. Reboot when ready."
}

main "$@"
