#!/bin/bash
# KMOS KDE Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
KDE_METAPACKAGE_DIR="$SCRIPT_DIR/metapackages/kde"
KDE_METAPACKAGE_URL="https://raw.githubusercontent.com/kamilomelo/KMOS/main/metapackages/kde/PKGBUILD"
KDE_METAPACKAGE_PKGBUILD=""

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

load_kde_metapackage() {
  local pkgbuild="$KDE_METAPACKAGE_DIR/PKGBUILD"
  local tmp_pkgbuild="/tmp/kmos-kde.PKGBUILD"

  if [[ ! -r "$pkgbuild" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$KDE_METAPACKAGE_URL" -o "$tmp_pkgbuild" || die "Could not fetch KDE metapackage."
      pkgbuild="$tmp_pkgbuild"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$tmp_pkgbuild" "$KDE_METAPACKAGE_URL" || die "Could not fetch KDE metapackage."
      pkgbuild="$tmp_pkgbuild"
    else
      die "KDE metapackage not found locally and neither curl nor wget is available."
    fi
  fi

  KDE_METAPACKAGE_PKGBUILD="$pkgbuild"
  mapfile -t KDE_PACKAGES < <(source "$pkgbuild"; printf '%s\n' "${depends[@]}" | sort -u)
  [[ ${#KDE_PACKAGES[@]} -gt 0 ]] || die "KDE metapackage has no dependencies."

  detail "Metapackage" "kmos-kde"
  detail "Packages" "${#KDE_PACKAGES[@]}"
}

install_kde_packages() {
  arch-chroot "$MOUNT_POINT" pacman -S --needed --noconfirm "${KDE_PACKAGES[@]}"
  success "KDE packages installed."
}

install_kde_assets() {
  if [[ -r "$KDE_METAPACKAGE_PKGBUILD" ]]; then
    install -Dm0644 "$KDE_METAPACKAGE_PKGBUILD" "$MOUNT_POINT/usr/share/kmos/metapackages/kde/PKGBUILD"
  fi
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
  arch-chroot "$MOUNT_POINT" systemctl enable NetworkManager.service
  arch-chroot "$MOUNT_POINT" systemctl enable sddm.service
  success "NetworkManager and SDDM enabled."
}

main() {
  init_ui
  parse_args "$@"
  print_banner
  require_root
  require_tools
  verify_target
  load_kde_metapackage
  install_kde_packages
  install_kde_assets
  disable_kwallet
  migrate_wifi_to_networkmanager
  enable_kde_services
  final_success "KDE desktop layer installed. Reboot when ready."
}

main "$@"
